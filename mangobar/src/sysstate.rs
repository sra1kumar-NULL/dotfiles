// Battery and indicator state for the bar, polled every SYS_INTERVAL_MS (3s).
//
// Almost everything is read straight out of sysfs/procfs rather than shelling
// out to the *-state.sh scripts the menus use (nmcli and bluetoothctl take
// hundreds of ms each):
//   battery     /sys/class/power_supply/BAT*/{capacity,status}
//   network     /sys/class/net/*/{operstate,wireless,device} + /proc/net/wireless
//   bluetooth   /sys/class/rfkill/*/{type,soft,hard} + /sys/class/bluetooth/hci*:*
//   night       a wlsunset process in /proc (same test as night-state.sh)
//   stay-awake  swayidle absent (inhibit-state.sh) or inhibit.sh's pid alive
//   recording   $XDG_RUNTIME_DIR/mango-recording.pid names a live pid
// Do-not-disturb is the one subprocess: mako only exposes its mode over D-Bus,
// so `makoctl mode` runs once per tick with a short timeout.

use crate::settings::SYS_INTERVAL_MS;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;
use tokio::process::Command;
use tokio::runtime::Handle;
use tokio::sync::watch;
use tokio::time::{MissedTickBehavior, interval, timeout};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Battery {
    pub percent: u8,
    pub charging: bool,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum Network {
    /// Associated Wi-Fi; link quality 0-100 when /proc/net/wireless has it.
    Wifi(Option<u8>),
    Ethernet,
    #[default]
    Off,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum Bluetooth {
    #[default]
    Off,
    On,
    Connected,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct Indicators {
    pub network: Network,
    pub bluetooth: Bluetooth,
    pub dnd: bool,
    pub recording: bool,
    pub night: bool,
    pub awake: bool,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct SysState {
    /// None on a desktop, or if the kernel exposes no BAT* device.
    pub battery: Option<Battery>,
    pub indicators: Indicators,
}

pub fn spawn(handle: &Handle, tx: watch::Sender<SysState>) {
    handle.spawn(async move {
        let mut tick = interval(Duration::from_millis(SYS_INTERVAL_MS));
        tick.set_missed_tick_behavior(MissedTickBehavior::Skip);

        loop {
            tick.tick().await;
            let procs = process_names(&["wlsunset", "swayidle"]);
            let next = SysState {
                battery: battery(),
                indicators: Indicators {
                    network: network(),
                    bluetooth: bluetooth(),
                    dnd: dnd().await,
                    recording: recording(),
                    night: procs[0],
                    awake: !procs[1] || pidfile_alive("mango-inhibit.pid"),
                },
            };

            let _ = tx.send_if_modified(|current| {
                if *current == next {
                    false
                } else {
                    *current = next;
                    true
                }
            });
        }
    });
}

/// The first BAT* power supply. Deliberately not every power supply: this
/// laptop also exposes `hidpp_battery_0` (a wireless mouse) and an AC adapter,
/// neither of which belongs in a battery indicator.
fn battery() -> Option<Battery> {
    let entries = fs::read_dir("/sys/class/power_supply").ok()?;

    let mut paths: Vec<PathBuf> = entries
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| {
            path.file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| name.starts_with("BAT"))
        })
        .collect();
    paths.sort();

    let path = paths.first()?;
    let percent = read_trimmed(&path.join("capacity"))?.parse::<u8>().ok()?;
    let status = read_trimmed(&path.join("status")).unwrap_or_default();

    Some(Battery {
        percent: percent.min(100),
        charging: status == "Charging",
    })
}

/// Physical interfaces only (those with a `device` link — skips lo, docker,
/// virbr, tun). Wired wins over Wi-Fi when both are up, as NetworkManager's
/// default route would.
fn network() -> Network {
    let Ok(entries) = fs::read_dir("/sys/class/net") else {
        return Network::Off;
    };

    let mut wifi_up: Option<String> = None;
    for path in entries.filter_map(Result::ok).map(|entry| entry.path()) {
        if !path.join("device").exists() {
            continue;
        }
        if read_trimmed(&path.join("operstate")).as_deref() != Some("up") {
            continue;
        }
        if path.join("wireless").exists() || path.join("phy80211").exists() {
            if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                wifi_up = Some(name.to_string());
            }
        } else {
            return Network::Ethernet;
        }
    }

    match wifi_up {
        Some(iface) => Network::Wifi(wifi_quality(&iface)),
        None => Network::Off,
    }
}

/// Link quality from /proc/net/wireless, scaled from the usual /70 to /100.
fn wifi_quality(iface: &str) -> Option<u8> {
    let text = fs::read_to_string("/proc/net/wireless").ok()?;
    parse_wifi_quality(&text, iface)
}

fn parse_wifi_quality(text: &str, iface: &str) -> Option<u8> {
    let line = text
        .lines()
        .find(|line| line.trim_start().starts_with(&format!("{iface}:")))?;
    let quality: f32 = line
        .split_whitespace()
        .nth(2)?
        .trim_end_matches('.')
        .parse()
        .ok()?;
    Some(((quality / 70.0) * 100.0).clamp(0.0, 100.0) as u8)
}

/// Powered ~= the bluetooth rfkill switch is unblocked and an hci adapter
/// exists (bluez auto-powers on unblock). Connected = an ACL link, which the
/// kernel exposes as `hciN:<handle>` under /sys/class/bluetooth.
fn bluetooth() -> Bluetooth {
    let Ok(entries) = fs::read_dir("/sys/class/bluetooth") else {
        return Bluetooth::Off;
    };
    let names: Vec<String> = entries
        .filter_map(Result::ok)
        .filter_map(|entry| entry.file_name().into_string().ok())
        .collect();

    if !names.iter().any(|name| !name.contains(':')) {
        return Bluetooth::Off;
    }

    let unblocked = fs::read_dir("/sys/class/rfkill")
        .map(|entries| {
            entries.filter_map(Result::ok).any(|entry| {
                let path = entry.path();
                read_trimmed(&path.join("type")).as_deref() == Some("bluetooth")
                    && read_trimmed(&path.join("soft")).as_deref() == Some("0")
                    && read_trimmed(&path.join("hard")).as_deref() == Some("0")
            })
        })
        .unwrap_or(false);

    if !unblocked {
        Bluetooth::Off
    } else if names.iter().any(|name| name.contains(':')) {
        Bluetooth::Connected
    } else {
        Bluetooth::On
    }
}

async fn dnd() -> bool {
    let run = Command::new("makoctl").arg("mode").kill_on_drop(true).output();
    match timeout(Duration::from_millis(500), run).await {
        Ok(Ok(out)) if out.status.success() => {
            String::from_utf8_lossy(&out.stdout).contains("do-not-disturb")
        }
        _ => false,
    }
}

/// Contract with the screen-recording script: it writes its pid here.
fn recording() -> bool {
    pidfile_alive("mango-recording.pid")
}

fn pidfile_alive(name: &str) -> bool {
    let dir = std::env::var_os("XDG_RUNTIME_DIR").unwrap_or_else(|| "/tmp".into());
    let Some(pid) = read_trimmed(&Path::new(&dir).join(name)) else {
        return false;
    };
    pid.parse::<u32>().is_ok_and(|pid| pid > 0 && Path::new(&format!("/proc/{pid}")).exists())
}

/// One pass over /proc/*/comm, answering "is a process with this exact name
/// running?" for each of `wanted` (same semantics as `pgrep -x`).
fn process_names<const N: usize>(wanted: &[&str; N]) -> [bool; N] {
    let mut found = [false; N];
    let Ok(entries) = fs::read_dir("/proc") else {
        return found;
    };
    for entry in entries.filter_map(Result::ok) {
        let name = entry.file_name();
        let Some(name) = name.to_str() else { continue };
        if !name.bytes().all(|b| b.is_ascii_digit()) {
            continue;
        }
        let Some(comm) = read_trimmed(&entry.path().join("comm")) else {
            continue;
        };
        for (index, want) in wanted.iter().enumerate() {
            if comm == *want {
                found[index] = true;
            }
        }
        if found.iter().all(|f| *f) {
            break;
        }
    }
    found
}

fn read_trimmed(path: &Path) -> Option<String> {
    fs::read_to_string(path).ok().map(|s| s.trim().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wifi_quality_parses_proc_net_wireless() {
        let text = "Inter-| sta-|   Quality        |   Discarded packets\n \
                    face | tus | link level noise |  nwid  crypt\n\
                    wlp3s0: 0000   56.  -54.  -256        0      0\n";
        assert_eq!(parse_wifi_quality(text, "wlp3s0"), Some(80));
        assert_eq!(parse_wifi_quality(text, "wlan0"), None);
    }

    #[test]
    fn process_scan_finds_nothing_bogus() {
        assert_eq!(process_names(&["no-such-process-xyz"]), [false]);
    }
}
