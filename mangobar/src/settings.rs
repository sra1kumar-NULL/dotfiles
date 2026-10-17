// Riced for the mango light stack (replaces the DMS bar on this compositor).
//
// Colours are NOT here — they live in the generated palette.rs so a wallpaper
// change can re-bake them without touching any taste decision. Everything in
// this file is a taste decision and is safe to hand-edit.
pub use crate::palette::*;

pub const APP_ID: &str = "dev.mangowm.mangobar";

// 22px total: 4px padding, the 14px text line, 4px padding.
pub const BAR_HEIGHT: i32 = 22;

/// Which screen edge the bar anchors to. Flip to `false` to put it back on top.
pub const BAR_AT_BOTTOM: bool = true;

pub const UI_TICK_MS: u64 = 16;
pub const VOLUME_INTERVAL_MS: u64 = 100;
// nmcli and bluetoothctl are an order of magnitude slower than wpctl, so the
// network/bluetooth modules get their own slow timer.
pub const SYS_INTERVAL_MS: u64 = 3000;
pub const VOLUME_TIMEOUT_MS: u64 = 80;

// Same family as kitty and the cheatsheet so the nf-md glyphs in status.rs
// render instead of tofu (coverage verified with fc-query).
pub const FONT: &str = "13px \"JetBrainsMono Nerd Font\"";

pub const LEFT_PADDING: i32 = 10;
pub const RIGHT_PADDING: i32 = 12;
pub const TAG_MIN_WIDTH: i32 = 22;
pub const TAG_MIN_HEIGHT: i32 = 14;
pub const BAR_TOP_PADDING: i32 = 4;
pub const BAR_BOTTOM_PADDING: i32 = 4;
/// Logical px; matches the 14px text line.
pub const TRAY_ICON_SIZE: i32 = 14;
