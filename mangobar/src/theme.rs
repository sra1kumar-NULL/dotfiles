// Runtime colours.
//
// Colours used to be compiled in (palette.rs, regenerated from palette.sh), so
// every theme change meant a cargo build. Now the bar reads
// ~/.config/mango/mangobar.css at startup and again on SIGUSR1.
//
// CONTRACT: that file holds GTK `@define-color` lines for exactly
//   bg, fg, accent, muted, urgent, occupied, surface, border
// and the structural CSS below refers to them only by name.
//
// Everything is concatenated into ONE CssProvider — built-in fallback defines
// (palette.rs, everforest), then the user file, then the structural rules. GTK
// keeps the last @define-color for a name, so the user file overrides the
// fallbacks and any name it leaves out still resolves. A single provider also
// sidesteps @define-color visibility between providers.

use crate::settings::*;
use gtk::CssProvider;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};

/// Path of the runtime colour file.
pub fn user_css_path() -> Option<PathBuf> {
    let mut path = PathBuf::from(std::env::var_os("HOME")?);
    path.push(".config/mango/mangobar.css");
    Some(path)
}

/// Built-in defines, equal to the palette the bar was last baked with.
pub fn fallback_defines() -> String {
    format!(
        "@define-color bg {BACKGROUND};\n\
         @define-color fg {FOREGROUND};\n\
         @define-color accent {ACCENT};\n\
         @define-color muted {DIM_FOREGROUND};\n\
         @define-color urgent {URGENT};\n\
         @define-color occupied {SURFACE_ALT};\n\
         @define-color surface {SURFACE_ALT};\n\
         @define-color border {OUTLINE};\n"
    )
}

/// The full stylesheet for a given user file body (None = file missing).
pub fn stylesheet(user: Option<&str>) -> String {
    let mut css = fallback_defines();
    if let Some(user) = user {
        css.push_str("\n/* ~/.config/mango/mangobar.css */\n");
        css.push_str(user);
        css.push('\n');
    }
    css.push_str(&structural());
    css
}

/// Re-read the user file and replace the provider's contents.
pub fn load(provider: &CssProvider) {
    let user = user_css_path().and_then(|path| std::fs::read_to_string(path).ok());
    provider.load_from_data(&stylesheet(user.as_deref()));
}

static RELOAD: AtomicBool = AtomicBool::new(false);

extern "C" fn on_sigusr1(_: libc::c_int) {
    // Only an atomic store: async-signal-safe. The UI tick picks it up on the
    // main thread, so GTK is never touched from the handler.
    RELOAD.store(true, Ordering::Relaxed);
}

/// Install the SIGUSR1 handler. glib 0.22 no longer re-exports
/// unix_signal_add_local, so this is a plain sigaction flag polled by the
/// existing main-thread UI tick.
pub fn install_sigusr1() {
    unsafe {
        let mut action: libc::sigaction = std::mem::zeroed();
        action.sa_sigaction = on_sigusr1 as extern "C" fn(libc::c_int) as usize;
        action.sa_flags = libc::SA_RESTART;
        libc::sigemptyset(&mut action.sa_mask);
        libc::sigaction(libc::SIGUSR1, &action, std::ptr::null_mut());
    }
}

/// True once per received SIGUSR1 (coalesced).
pub fn take_reload() -> bool {
    RELOAD.swap(false, Ordering::Relaxed)
}

fn structural() -> String {
    // Centre the tags vertically; their margins must not push the bar past BAR_HEIGHT.
    let tag_vmargin = (BAR_HEIGHT - BAR_TOP_PADDING - BAR_BOTTOM_PADDING - TAG_MIN_HEIGHT).max(0) / 2;
    format!(
        "
        window {{ background: @bg; }}

        .bar {{
            background: @bg;
            color: @fg;
            font: {FONT};
        }}

        .tags {{ margin-left: {LEFT_PADDING}px; }}

        /* Tight line box so there is no dead descender space under the text;
           the padding lives on .bar-root instead. */
        .bar label {{ line-height: 0.8; padding-top: 1px; }}
        .bar-root {{ padding: {BAR_TOP_PADDING}px 0 {BAR_BOTTOM_PADDING}px 0; }}

        /* Square corners on purpose: mango runs border_radius=0, so a rounded
           bar would be the only rounded thing on screen. */
        label.tag {{
            min-width: {TAG_MIN_WIDTH}px;
            min-height: {TAG_MIN_HEIGHT}px;
            margin: {tag_vmargin}px 3px {tag_vmargin}px 0;
            padding: 0 2px;
            color: @muted;
        }}

        /* has windows but not focused: brighter text only, no box. Only the
           active tag gets a background. */
        label.tag.occupied {{ color: @fg; }}

        label.tag.active {{
            background: @accent;
            color: @bg;
            font-weight: bold;
        }}

        label.tag.urgent {{
            background: @urgent;
            color: @bg;
            font-weight: bold;
        }}

        .modules {{ margin-right: {RIGHT_PADDING}px; }}
        label.module {{ padding: 0 6px; color: @fg; }}

        /* Tray: the only clickable part of the bar, so it alone gets a hover. */
        .tray {{ margin-right: 4px; }}
        button.tray-item {{
            min-width: 0;
            min-height: 0;
            margin: 0;
            padding: 0 4px;
            border: 0;
            border-radius: 0;
            background: transparent;
            background-image: none;
            box-shadow: none;
        }}
        button.tray-item:hover {{ background: @surface; }}

        /* Indicator strip: icon-only, tighter than the text modules. */
        .indicators {{ margin-right: 4px; }}
        label.module.indicator {{ padding: 0 4px; }}
        label.module.indicator.off {{ color: @muted; }}
        label.module.indicator.recording {{ color: @urgent; }}
        "
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn user_defines_come_after_fallbacks_and_before_rules() {
        let css = stylesheet(Some("@define-color accent #ff0000;"));
        let fallback = css.find("@define-color accent").unwrap();
        let user = css.find("@define-color accent #ff0000").unwrap();
        let rule = css.find("label.tag {").unwrap();
        assert!(fallback < user && user < rule);
    }

    #[test]
    fn every_contract_name_has_a_fallback() {
        let defines = fallback_defines();
        for name in ["bg", "fg", "accent", "muted", "urgent", "occupied", "surface", "border"] {
            assert!(defines.contains(&format!("@define-color {name} ")), "{name}");
        }
    }

    #[test]
    fn structural_css_has_no_baked_colours() {
        assert!(!structural().contains('#'));
    }
}
