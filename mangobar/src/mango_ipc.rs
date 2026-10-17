// Tag event source for mango 0.18.
//
// Upstream bound zdwl_ipc_manager_v2 and waited for Wayland events. mango 0.18
// does not advertise that global, so upstream's loop only ever logged
// "MangoWM direct IPC failed" and the bar stayed empty. `mmsg watch` exists but
// emits nothing until something changes, so it cannot seed the initial state on
// its own; polling one `mmsg get all-monitors` covers it.
//
// The poll is cheap by the bar's own standards — the volume poller already forks
// `wpctl` every 100ms — and only changes are forwarded, so the UI still repaints
// on change rather than on tick.

use crate::{Tag, mmsg};
use std::sync::mpsc;
use std::thread;
use std::time::Duration;

const POLL_INTERVAL_MS: u64 = 200;
const RETRY_INTERVAL_MS: u64 = 1000;

#[derive(Clone, Debug)]
pub enum MangoEvent {
    Tags(Vec<Tag>),
}

pub fn spawn(output_filter: Option<String>, tx: mpsc::Sender<MangoEvent>) {
    thread::spawn(move || {
        let mut last_tags: Option<Vec<Tag>> = None;

        loop {
            let all = match mmsg::monitors() {
                Ok(all) => all,
                Err(err) => {
                    // The compositor is gone or still starting; say so once per
                    // second rather than spinning on it.
                    eprintln!("mangobar: mmsg get all-monitors failed: {err}");
                    thread::sleep(Duration::from_millis(RETRY_INTERVAL_MS));
                    continue;
                }
            };

            if let Some(monitor) = mmsg::select(&all, output_filter.as_deref()) {
                if last_tags.as_ref() != Some(&monitor.tags) {
                    if tx.send(MangoEvent::Tags(monitor.tags.clone())).is_err() {
                        return;
                    }
                    last_tags = Some(monitor.tags.clone());
                }
            }

            thread::sleep(Duration::from_millis(POLL_INTERVAL_MS));
        }
    });
}
