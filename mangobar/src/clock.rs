use crate::status::{CLOCK_CAP, ClockState};
use libc::{localtime_r, strftime, time, time_t, tm};
use std::mem::MaybeUninit;
use std::time::Duration;
use tokio::sync::watch;
use tokio::time::{MissedTickBehavior, interval};

// Upstream copied exactly CLOCK_LEN bytes out of the strftime buffer, so the
// format had to be fixed-width or the label picked up trailing NULs. This copies
// only what strftime actually wrote, so the format below is free to change.
const CLOCK_FORMAT: &[u8] = b"%a %d %b %I:%M %p\0";
const CLOCK_FALLBACK: &[u8] = b"--:--";

fn from_slice(src: &[u8]) -> ClockState {
    let len = src.len().min(CLOCK_CAP);
    let mut out = [0u8; CLOCK_CAP];
    out[..len].copy_from_slice(&src[..len]);
    ClockState::from_bytes(out, len as u8)
}

pub fn now() -> ClockState {
    let mut raw: time_t = 0;
    let mut local = MaybeUninit::<tm>::uninit();
    let mut buf = [0u8; CLOCK_CAP + 1];

    let written = unsafe {
        time(&mut raw);

        if localtime_r(&raw, local.as_mut_ptr()).is_null() {
            return from_slice(CLOCK_FALLBACK);
        }

        strftime(
            buf.as_mut_ptr().cast(),
            buf.len(),
            CLOCK_FORMAT.as_ptr().cast(),
            local.as_ptr(),
        )
    };

    if written == 0 || written > CLOCK_CAP {
        return from_slice(CLOCK_FALLBACK);
    }

    from_slice(&buf[..written])
}

pub fn spawn(tx: watch::Sender<ClockState>) {
    tokio::spawn(async move {
        // Still a 1s tick even though the format stops at minutes: send_if_modified
        // drops the duplicates, so the label only repaints when the text changes.
        let mut tick = interval(Duration::from_secs(1));
        tick.set_missed_tick_behavior(MissedTickBehavior::Skip);

        loop {
            tick.tick().await;
            let next = now();
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
