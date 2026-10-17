#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct VolumeState {
    percent: u16,
    known: bool,
    muted: bool,
}

impl VolumeState {
    pub const UNKNOWN: Self = Self {
        percent: 0,
        known: false,
        muted: false,
    };

    pub const fn new(percent: u16, muted: bool) -> Self {
        Self {
            percent,
            known: true,
            muted,
        }
    }


}

pub const CLOCK_CAP: usize = 48;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ClockState {
    bytes: [u8; CLOCK_CAP],
    len: u8,
}

impl ClockState {

    pub const fn from_bytes(bytes: [u8; CLOCK_CAP], len: u8) -> Self {
        Self { bytes, len }
    }

}

/// One rendered bar module: a nerd-font glyph and the text beside it.
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct Module {
    pub icon: String,
    pub text: String,
}

impl Module {
    pub fn new(icon: char, text: impl Into<String>) -> Self {
        Self {
            icon: icon.to_string(),
            text: text.into(),
        }
    }

    pub fn label(&self) -> String {
        if self.text.is_empty() {
            self.icon.clone()
        } else {
            format!("{} {}", self.icon, self.text)
        }
    }
}

/// Everything on the right-hand side of the bar, rebuilt whenever any input
/// changes. Sent as one value so the UI thread does a single pass of updates.
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct Modules {
    pub volume: Module,
    pub battery: Module,
    pub clock: Module,
    pub indicators: crate::sysstate::Indicators,
}

impl VolumeState {
    pub fn module(self) -> Module {
        if !self.known {
            return Module::new('\u{f0581}', "--");
        }

        let value = if self.muted { 0 } else { self.percent };
        let icon = match (self.muted, value) {
            (true, _) => '\u{f0581}',
            (_, 0..=33) => '\u{f057f}',
            (_, 34..=66) => '\u{f0580}',
            _ => '\u{f057e}',
        };
        Module::new(icon, format!("{value}%"))
    }
}

impl ClockState {
    pub fn module(self) -> Module {
        Module::new(
            '\u{f0150}',
            std::str::from_utf8(&self.bytes[..self.len as usize])
                .unwrap_or("")
                .to_string(),
        )
    }
}

/// `nf-md` battery glyphs, picked per decile the way a tray icon would.
/// Coverage for every codepoint here was checked with fc-query first.
pub fn battery_module(battery: Option<crate::sysstate::Battery>) -> Module {
    let Some(battery) = battery else {
        // No BAT* device: a desktop, or a kernel that does not expose one.
        return Module::default();
    };

    let icon = if battery.charging {
        '\u{f0084}'
    } else {
        match battery.percent {
            0..=9 => '\u{f008e}',
            10..=19 => '\u{f007a}',
            20..=29 => '\u{f007b}',
            30..=39 => '\u{f007c}',
            40..=49 => '\u{f007d}',
            50..=59 => '\u{f007e}',
            60..=69 => '\u{f007f}',
            70..=79 => '\u{f0080}',
            80..=89 => '\u{f0081}',
            90..=99 => '\u{f0082}',
            _ => '\u{f0079}',
        }
    };

    Module::new(icon, format!("{}%", battery.percent))
}

/// Indicator glyphs (nf-md, coverage checked against the installed
/// JetBrainsMono Nerd Font charset). `None` means hidden: an indicator that is
/// off takes no space on the bar. Network is always shown.
pub mod indicator {
    use crate::sysstate::{Bluetooth, Network};

    pub fn network(network: Network) -> char {
        match network {
            Network::Ethernet => '\u{f0200}',
            Network::Wifi(None) => '\u{f05a9}',
            Network::Wifi(Some(q)) => match q {
                0..=24 => '\u{f091f}',
                25..=49 => '\u{f0922}',
                50..=74 => '\u{f0925}',
                _ => '\u{f0928}',
            },
            Network::Off => '\u{f092e}',
        }
    }

    pub fn bluetooth(bluetooth: Bluetooth) -> Option<char> {
        match bluetooth {
            Bluetooth::Off => None,
            Bluetooth::On => Some('\u{f00af}'),
            Bluetooth::Connected => Some('\u{f00b1}'),
        }
    }

    pub const DND: char = '\u{f009b}';
    pub const RECORDING: char = '\u{f044a}';
    pub const NIGHT: char = '\u{f0594}';
    pub const AWAKE: char = '\u{f0176}';
}
