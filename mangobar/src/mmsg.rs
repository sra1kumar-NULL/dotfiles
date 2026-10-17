// Minimal reader for mango's `mmsg` JSON IPC.
//
// Why this exists: upstream mangobar talks dwl-ipc-unstable-v2 over Wayland and
// shells out to the old mangowc `mmsg -g -t` / `-g -k` / `-s -t` CLI. mango 0.18
// supports neither. Its registry advertises no zdwl_ipc_manager_v2 (verified by
// dumping the globals of this session with WAYLAND_DEBUG=1), and the current CLI
// answers `{"error":"unknown command"}` to every old-style flag. What it does
// expose is `mmsg get all-monitors`, which returns tags, focus and size
// for every output in one shot.
//
// This is a field scanner, not a general JSON parser: mango's emitter has a
// fixed shape, so scanning for `"key":` keeps the dependency list at zero.

use crate::Tag;
use std::process::Command;

#[derive(Clone, Debug)]
pub struct MonitorState {
    pub name: String,
    /// The focused monitor. Dispatchers act on it, so a bar on a different
    /// output cannot switch tags for its own monitor.
    pub active: bool,
    pub tags: Vec<Tag>,
    /// Logical pixels — the same space GTK lays out in. mango divides the panel
    /// through by the scale before reporting (eDP-1 is a 1920px panel at 1.333x
    /// and reports 1440), so this needs no further conversion.
    pub width: i32,
    /// Fractional, e.g. 1.3333330154418945 for the 1.33x panel. Only the test
    /// below reads it, and deliberately so: it pins down that `width` is logical
    /// and `width * scale` is the framebuffer, which is the relationship that
    /// made the bar 75% wide on this panel when the scale was applied twice.
    #[allow(dead_code)]
    pub scale: f64,
}

impl MonitorState {
    /// Width in the logical pixels GTK lays out in.
    ///
    /// This is `width` as-is. Dividing by `scale` here is the obvious-looking
    /// mistake: it makes the bar 75% of the panel on eDP-1 while leaving DP-1
    /// (scale 1.0) correct, so it reads as "one monitor is fine, the other is
    /// short". `scale` is kept on the struct because the device size
    /// (`width * scale`) is what a screenshot measures against.
    pub fn logical_width(&self) -> i32 {
        self.width
    }
}

pub fn monitors() -> Result<Vec<MonitorState>, String> {
    let out = Command::new("mmsg")
        .args(["get", "all-monitors"])
        .output()
        .map_err(|err| err.to_string())?;

    if !out.status.success() {
        return Err(String::from_utf8_lossy(&out.stderr).trim().to_string());
    }

    let parsed = parse_monitors(&String::from_utf8_lossy(&out.stdout));
    if parsed.is_empty() {
        Err("mmsg returned no monitors".to_string())
    } else {
        Ok(parsed)
    }
}

/// Pick the monitor this bar belongs to: the one named with `--output`, else the
/// focused one, else the first. Without `--output` the bar follows focus, which
/// is the best guess available — layer-shell does not report which output the
/// compositor placed an unanchored surface on.
pub fn select<'a>(all: &'a [MonitorState], filter: Option<&str>) -> Option<&'a MonitorState> {
    if let Some(name) = filter {
        return all.iter().find(|monitor| monitor.name == name);
    }

    all.iter()
        .find(|monitor| monitor.active)
        .or_else(|| all.first())
}

pub fn parse_monitors(raw: &str) -> Vec<MonitorState> {
    let Some(list) = array_slice(raw, "monitors") else {
        return Vec::new();
    };

    objects(list).into_iter().filter_map(parse_monitor).collect()
}

fn parse_monitor(src: &str) -> Option<MonitorState> {
    // Read `active` out of the head of the object only. Each tag carries its own
    // `is_active`, and reading the whole object would be one typo away from
    // picking up the wrong one.
    let head = &src[..src.find("\"tags\":").unwrap_or(src.len())];

    Some(MonitorState {
        name: field_str(head, "name")?.to_string(),
        active: field_bool(head, "active").unwrap_or(false),
        tags: array_slice(src, "tags").map(parse_tags).unwrap_or_default(),
        width: field_u32(head, "width").unwrap_or(0) as i32,
        scale: field_f64(head, "scale").unwrap_or(1.0),
    })
}

fn parse_tags(list: &str) -> Vec<Tag> {
    let mut tags: Vec<Tag> = objects(list)
        .into_iter()
        .filter_map(|obj| {
            Some(Tag {
                number: field_u32(obj, "index")?,
                active: field_bool(obj, "is_active").unwrap_or(false),
                urgent: field_bool(obj, "is_urgent").unwrap_or(false),
                occupied: field_u32(obj, "client_count").unwrap_or(0) > 0,
                // mango does not report this per tag; nothing in the bar reads it.
                focused_client: false,
            })
        })
        .collect();

    tags.sort_by_key(|tag| tag.number);
    tags
}

fn after_key<'a>(src: &'a str, key: &str) -> Option<&'a str> {
    let needle = format!("\"{key}\":");
    let at = src.find(&needle)?;
    Some(&src[at + needle.len()..])
}

fn field_str<'a>(src: &'a str, key: &str) -> Option<&'a str> {
    let rest = after_key(src, key)?.trim_start().strip_prefix('"')?;
    // Monitor names and layout names carry no escapes, so the first quote ends it.
    rest.find('"').map(|end| &rest[..end])
}

fn field_bool(src: &str, key: &str) -> Option<bool> {
    let rest = after_key(src, key)?.trim_start();
    if rest.starts_with("true") {
        Some(true)
    } else if rest.starts_with("false") {
        Some(false)
    } else {
        None
    }
}

fn field_u32(src: &str, key: &str) -> Option<u32> {
    let rest = after_key(src, key)?.trim_start();
    let end = rest
        .find(|ch: char| !ch.is_ascii_digit())
        .unwrap_or(rest.len());
    rest[..end].parse().ok()
}

fn field_f64(src: &str, key: &str) -> Option<f64> {
    let rest = after_key(src, key)?.trim_start();
    let end = rest
        .find(|ch: char| !ch.is_ascii_digit() && ch != '.' && ch != '-')
        .unwrap_or(rest.len());
    rest[..end].parse().ok()
}

/// The contents of `"key":[ ... ]`, brace-matched so nested arrays and objects
/// do not end it early.
fn array_slice<'a>(src: &'a str, key: &str) -> Option<&'a str> {
    let rest = after_key(src, key)?.trim_start().strip_prefix('[')?;
    let mut depth = 0usize;
    let mut in_string = false;
    let mut escaped = false;

    for (at, ch) in rest.char_indices() {
        if escaped {
            escaped = false;
            continue;
        }

        match ch {
            '\\' if in_string => escaped = true,
            '"' => in_string = !in_string,
            '[' | '{' if !in_string => depth += 1,
            '}' if !in_string => depth = depth.saturating_sub(1),
            ']' if !in_string => {
                if depth == 0 {
                    return Some(&rest[..at]);
                }
                depth -= 1;
            }
            _ => {}
        }
    }

    None
}

/// Every top-level `{ ... }` in a slice, brace-matched.
fn objects(src: &str) -> Vec<&str> {
    let mut out = Vec::new();
    let mut depth = 0usize;
    let mut start = 0usize;
    let mut in_string = false;
    let mut escaped = false;

    for (at, ch) in src.char_indices() {
        if escaped {
            escaped = false;
            continue;
        }

        match ch {
            '\\' if in_string => escaped = true,
            '"' => in_string = !in_string,
            '{' if !in_string => {
                if depth == 0 {
                    start = at;
                }
                depth += 1;
            }
            '}' if !in_string => {
                depth = depth.saturating_sub(1);
                if depth == 0 {
                    out.push(&src[start..=at]);
                }
            }
            _ => {}
        }
    }

    out
}

#[cfg(test)]
mod tests {
    use super::*;

    // Captured verbatim from `mmsg get all-monitors` on mango 0.18.0.
    const SAMPLE: &str = r#"{"monitors":[{"name":"DP-1","active":true,"is_hdr":false,"x":1440,"y":0,"width":1920,"height":1080,"scale":1,"layout_symbol":"DW","tag_num":9,"tags":[{"index":1,"is_active":false,"is_urgent":false,"layout":"DW","client_count":1},{"index":2,"is_active":true,"is_urgent":false,"layout":"DW","client_count":0}],"active_tags":[2],"active_client":{"id":5,"title":"a, b","appid":"chrome"},"keymode":"default","keyboardlayout":"English (US)"},{"name":"eDP-1","active":false,"width":1440,"height":810,"scale":1.3333330154418945,"tags":[{"index":1,"is_active":true,"is_urgent":true,"layout":"DW","client_count":2}],"active_tags":[1],"keyboardlayout":"Russian"}]}"#;

    #[test]
    fn parses_both_monitors() {
        let all = parse_monitors(SAMPLE);
        assert_eq!(all.len(), 2);
        assert_eq!(all[0].name, "DP-1");
        assert!(all[0].active);
        assert_eq!(all[0].logical_width(), 1920);
        assert_eq!(all[1].name, "eDP-1");
        assert!(!all[1].active);
        // The 1920px panel at 1.333x reports 1440 logical px of layout space,
        // which is what the bar must request to span the whole screen. Applying
        // the scale a second time asked for 1080 and left a quarter of the
        // panel bare, while DP-1 at scale 1.0 looked perfectly fine.
        assert_eq!(all[1].logical_width(), 1440);
        let framebuffer = (f64::from(all[1].logical_width()) * all[1].scale).round() as i32;
        assert_eq!(framebuffer, 1920);
    }

    #[test]
    fn tag_state_survives_the_nested_objects() {
        let all = parse_monitors(SAMPLE);
        let dp = &all[0].tags;
        assert_eq!(dp.len(), 2);
        assert!(!dp[0].active && dp[0].occupied);
        assert!(dp[1].active && !dp[1].occupied);

        let edp = &all[1].tags;
        assert!(edp[0].active && edp[0].urgent && edp[0].occupied);
    }

    #[test]
    fn select_prefers_the_named_monitor_then_focus() {
        let all = parse_monitors(SAMPLE);
        assert_eq!(select(&all, Some("eDP-1")).unwrap().name, "eDP-1");
        assert_eq!(select(&all, None).unwrap().name, "DP-1");
        assert!(select(&all, Some("HDMI-A-1")).is_none());
    }
}
