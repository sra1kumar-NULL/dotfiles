#!/usr/bin/env bash
# Apply a theme to the whole mango light stack, omarchy-style.
#
# A theme is a directory ~/.config/mango/themes/<name>/ holding ONE colour file,
# colors.sh (shell variables, same names as ~/.config/mango/palette.sh), plus an
# optional backgrounds/ directory. Everything else is rendered from colors.sh
# here, so there is exactly one code path for every theme:
#
#   colors.sh ─┬─ ~/.config/mango/palette.sh          (sourced by scripts)
#              ├─ ~/.config/mango/dms/colors-user.conf (mango 0.18 colour keys)
#              ├─ ~/.config/mango/mangobar.css         (@define-color, bar reloads on USR1)
#              ├─ ~/.config/fuzzel/fuzzel.ini
#              ├─ ~/.config/mako/config
#              ├─ ~/.config/swaylock/config
#              ├─ ~/.config/mango/hyprlock.conf       (lock.sh: hyprlock -c)
#              ├─ ~/.config/kitty/theme.conf           (included by kitty.conf)
#              └─ ~/.config/btop/themes/matugen.theme  (btop.conf points at "matugen")
#
# The special theme "wallpaper" first asks matugen to write
# themes/wallpaper/colors.sh from the current wallpaper (matugen does nothing
# else), then renders exactly like a curated theme.
#
#   theme-set.sh <name>                    # apply, switch to the theme's first background
#   theme-set.sh <name> --keep-wallpaper   # apply, leave the wallpaper alone
#   theme-set.sh <name> --no-reload        # render only, do not poke running apps
#   theme-set.sh --list | --current
#
# THEME_OUT=<dir> renders into <dir> (mirrors ~/.config layout) instead of
# ~/.config and implies --no-reload --keep-wallpaper -- used for testing.
set -uo pipefail

MANGO="$HOME/.config/mango"
THEMES="$MANGO/themes"
CURRENT="$MANGO/current-theme"
MODE_STATE="$HOME/.local/state/mango-thememode"   # wallpaper theme: dark|light
WALL_STATE="$HOME/.local/state/mango-wallpaper"

die() { echo "theme-set: $*" >&2; notify-send -a Theme "Theme" "$*" 2>/dev/null; exit 1; }

list() {
    local d
    for d in "$THEMES"/*/; do
        d="${d%/}"
        [ -r "$d/colors.sh" ] || [ "$(basename "$d")" = wallpaper ] || continue
        basename "$d"
    done
}

name="" keep_wall=0 reload=1
for a in "$@"; do
    case "$a" in
        --list|-l)        list; exit 0 ;;
        --current|-c)     cat "$CURRENT" 2>/dev/null; echo; exit 0 ;;
        --keep-wallpaper) keep_wall=1 ;;
        --no-reload)      reload=0 ;;
        -h|--help)        sed -n '2,29p' "$0"; exit 0 ;;
        -*)               die "unknown option $a" ;;
        *)                name="$a" ;;
    esac
done
[ -n "$name" ] || die "usage: theme-set.sh <name> [--keep-wallpaper] [--no-reload] | --list"
[ -d "$THEMES/$name" ] || die "no such theme: $name (have: $(list | tr '\n' ' '))"

OUT="${THEME_OUT:-$HOME/.config}"
if [ -n "${THEME_OUT:-}" ]; then reload=0; keep_wall=1; fi
DIR="$THEMES/$name"
COLORS="$DIR/colors.sh"

# ── wallpaper theme: matugen produces colors.sh, nothing more ───────────────
if [ "$name" = wallpaper ]; then
    command -v matugen >/dev/null || die "matugen not installed"
    wall="$(cat "$WALL_STATE" 2>/dev/null)"
    [ -n "$wall" ] && [ -r "$wall" ] || die "no current wallpaper (set one with wallpaper.sh first)"
    mode="$(cat "$MODE_STATE" 2>/dev/null)"
    [ "$mode" = light ] || mode=dark
    # --source-color-index 0 = most dominant colour, no prompt. Never --prefer:
    # it chooses a different source colour and drifts the whole palette.
    matugen image "$wall" -c "$HOME/.config/matugen/config.toml" \
        -m "$mode" -t scheme-tonal-spot --source-color-index 0 -q \
        || die "matugen failed on $wall"
fi

[ -r "$COLORS" ] || die "$COLORS missing"

# ── load + validate the palette ──────────────────────────────────────────────
VARS=(PRIMARY ON_PRIMARY PRIMARY_CONTAINER SECONDARY SECONDARY_CONTAINER TERTIARY
      SURFACE ON_SURFACE SURFACE_CONTAINER SURFACE_CONTAINER_HIGH ON_SURFACE_VARIANT
      OUTLINE OUTLINE_VARIANT ERROR ON_ERROR
      TERM_BG TERM_FG SELECTION_BG SELECTION_FG CURSOR
      COLOR0 COLOR1 COLOR2 COLOR3 COLOR4 COLOR5 COLOR6 COLOR7
      COLOR8 COLOR9 COLOR10 COLOR11 COLOR12 COLOR13 COLOR14 COLOR15)
NAME="$name" MODE=dark OPPOSITE=""
# shellcheck source=/dev/null
. "$COLORS"
for v in "${VARS[@]}"; do
    val="${!v:-}"
    [[ "$val" =~ ^#[0-9a-fA-F]{6}$ ]] || die "$COLORS: $v='$val' is not #rrggbb"
    printf -v "$v" '%s' "${val,,}"
done

# "#a7c080" -> "a7c080"
h() { local v="${!1}"; printf '%s' "${v#\#}"; }
# "#a7c080" -> "167, 192, 128"
rgb() { local v="${!1}"; printf '%d, %d, %d' $((16#${v:1:2})) $((16#${v:3:2})) $((16#${v:5:2})); }

# Write stdin to $1 atomically, keeping a one-time <file>.pre-theme backup of
# whatever was there before this theme system existed.
put() {
    local dst="$1" tmp
    mkdir -p "$(dirname "$dst")"
    if [ -z "${THEME_OUT:-}" ] && [ -e "$dst" ] && [ ! -e "$dst.pre-theme" ]; then
        cp -p "$dst" "$dst.pre-theme"
    fi
    tmp="$(mktemp "$dst.XXXXXX")" || return 1
    cat > "$tmp" && mv -f "$tmp" "$dst" || { rm -f "$tmp"; return 1; }
}

HDR="Generated by ~/.config/mango/scripts/theme-set.sh from themes/$name/colors.sh -- do not edit."

# ── palette.sh (sourced by scripts) ──────────────────────────────────────────
{
    echo "# $HDR"
    echo "# Theme: $NAME ($MODE). Same variable names as every themes/*/colors.sh."
    echo "THEME='$name'"
    echo "NAME='$NAME'"
    echo "MODE='$MODE'"
    for v in "${VARS[@]}"; do echo "$v='${!v}'"; done
} | put "$OUT/mango/palette.sh"

# ── mango 0.18 colours (sourced last by config.conf) ─────────────────────────
put "$OUT/mango/dms/colors-user.conf" <<EOF
# $HDR
# mango 0.18 key names only (the pre-0.18 bordercolor/focuscolor/urgentcolor
# are rejected with "Unknown keyword").

# ── Window states ───────────────────────────────────────────────────────────
root_color             = 0x$(h SURFACE)ff
border_color           = 0x$(h OUTLINE_VARIANT)ff
focus_color            = 0x$(h PRIMARY)ff
urgent_color           = 0x$(h ERROR)ff
drop_color             = 0x$(h PRIMARY)55
split_color            = 0x$(h TERTIARY)ff
maximized_screen_color = 0x$(h SECONDARY)ff
scratchpad_color       = 0x$(h TERTIARY)ff
global_color           = 0x$(h PRIMARY_CONTAINER)ff
overlay_color          = 0x$(h SECONDARY_CONTAINER)ff

# ── Group bar (SUPER+G) ─────────────────────────────────────────────────────
group_bar_decorate_fg_color       = 0x$(h ON_SURFACE_VARIANT)ff
group_bar_decorate_bg_color       = 0x$(h SURFACE_CONTAINER)ff
group_bar_decorate_focus_fg_color = 0x$(h ON_PRIMARY)ff
group_bar_decorate_focus_bg_color = 0x$(h PRIMARY)ff
group_bar_decorate_border_color   = 0x$(h OUTLINE_VARIANT)ff
group_bar_button_color            = 0x$(h ERROR)ff

# ── Auto tab bar (monocle / deck) ──────────────────────────────────────────
tab_bar_decorate_fg_color       = 0x$(h ON_SURFACE_VARIANT)ff
tab_bar_decorate_bg_color       = 0x$(h SURFACE_CONTAINER)ff
tab_bar_decorate_focus_fg_color = 0x$(h ON_PRIMARY)ff
tab_bar_decorate_focus_bg_color = 0x$(h PRIMARY)ff
tab_bar_decorate_border_color   = 0x$(h OUTLINE_VARIANT)ff

# ── Overview jump labels (SUPER+SHIFT+A) ───────────────────────────────────
jump_label_decorate_fg_color       = 0x$(h ON_SURFACE)ff
jump_label_decorate_bg_color       = 0x$(h SURFACE_CONTAINER_HIGH)ff
jump_label_decorate_focus_fg_color = 0x$(h ON_PRIMARY)ff
jump_label_decorate_focus_bg_color = 0x$(h PRIMARY)ff
jump_label_decorate_border_color   = 0x$(h PRIMARY)ff
EOF

# ── mangobar (GTK4 CSS; the bar's built-in stylesheet uses these names) ──────
put "$OUT/mango/mangobar.css" <<EOF
/* $HDR */
/* Contract with mangobar: these @define-color names; reloaded on SIGUSR1. */
@define-color bg       $SURFACE;
@define-color fg       $ON_SURFACE;
@define-color accent   $PRIMARY;
@define-color muted    rgba($(rgb ON_SURFACE_VARIANT), 0.55);
@define-color urgent   $ERROR;
@define-color occupied $SURFACE_CONTAINER;
@define-color surface  $SURFACE_CONTAINER_HIGH;
@define-color border   $OUTLINE_VARIANT;
/* extras, safe to ignore */
@define-color on_accent $ON_PRIMARY;
@define-color on_urgent $ON_ERROR;
EOF

# ── fuzzel ───────────────────────────────────────────────────────────────────
put "$OUT/fuzzel/fuzzel.ini" <<EOF
# $HDR
# Launcher, menus, clipboard picker, power menu and cheat sheet all use this.
[main]
font=Google Sans Flex:size=11
dpi-aware=no
terminal=kitty -e
layer=overlay
prompt=">  "
icon-theme=Tela-circle
lines=12
width=46
tabs=4
horizontal-pad=20
vertical-pad=16
inner-pad=8

[border]
width=2
radius=0

[colors]
background=$(h SURFACE)f2
text=$(h ON_SURFACE)ff
prompt=$(h PRIMARY)ff
placeholder=$(h ON_SURFACE_VARIANT)aa
input=$(h ON_SURFACE)ff
match=$(h PRIMARY)ff
selection=$(h PRIMARY)ff
selection-text=$(h ON_PRIMARY)ff
selection-match=$(h ON_PRIMARY)ff
counter=$(h ON_SURFACE_VARIANT)ff
border=$(h PRIMARY)ff
EOF

# ── mako ─────────────────────────────────────────────────────────────────────
put "$OUT/mako/config" <<EOF
# $HDR
# mako has no include directive, so the whole config is generated.
font=Google Sans Flex 11
background-color=#$(h SURFACE_CONTAINER)f2
text-color=#$(h ON_SURFACE)
border-color=#$(h PRIMARY)
progress-color=over #$(h PRIMARY)
border-size=2
border-radius=0
padding=12
margin=8
default-timeout=6000
# 1, not 0: with 0 mako HONOURS whatever expire-timeout the sending app asks
# for, and apps that ask for 0 ("never expire") then pile up on screen forever.
# With 1 every notification uses the timeouts below instead.
ignore-timeout=1
anchor=top-right
layer=overlay
max-visible=5
icons=1
max-icon-size=48
width=380
height=160

[urgency=low]
border-color=#$(h OUTLINE_VARIANT)
default-timeout=4000

# Critical gets a longer timeout rather than 0: apps (uwsm's fumon, portals,
# updaters) send "critical" for things that need no action, and with 0 those
# toasts stayed on screen until clicked. Only the battery warning persists.
[urgency=critical]
border-color=#$(h ERROR)
text-color=#$(h ON_SURFACE)
default-timeout=15000

[app-name=Battery urgency=critical]
default-timeout=0
EOF

# ── swaylock ─────────────────────────────────────────────────────────────────
put "$OUT/swaylock/config" <<EOF
# $HDR
ignore-empty-password
show-failed-attempts
indicator-caps-lock
image=$HOME/.config/mango/lockscreen
scaling=fill
effect-blur=12x4
effect-vignette=0.3:0.6
font=Google Sans Flex
indicator-radius=96
indicator-thickness=6
ring-color=$(h PRIMARY)
ring-ver-color=$(h TERTIARY)
ring-wrong-color=$(h ERROR)
ring-clear-color=$(h SECONDARY)
inside-color=$(h SURFACE)
inside-ver-color=$(h SURFACE_CONTAINER)
inside-wrong-color=$(h SURFACE_CONTAINER)
inside-clear-color=$(h SURFACE_CONTAINER)
key-hl-color=$(h TERTIARY)
bs-hl-color=$(h ERROR)
text-color=$(h ON_SURFACE)
text-ver-color=$(h ON_SURFACE)
text-wrong-color=$(h ERROR)
text-clear-color=$(h ON_SURFACE)
line-color=00000000
separator-color=00000000
layout-bg-color=$(h SURFACE_CONTAINER)
layout-text-color=$(h ON_SURFACE)
EOF

# ── gtklock (lock.sh's first choice) ─────────────────────────────────────────
# background is a blurred copy of the wallpaper that lock.sh renders at lock
# time (gtklock has no blur of its own).
put "$OUT/gtklock/config.ini" <<EOF
# $HDR
[main]
gtk-theme=Adwaita-dark
style=$HOME/.config/gtklock/style.css
background=$HOME/.cache/mango/lock-blur.jpg
time-format=%H:%M
date-format=%A, %d %B
idle-hide=true
idle-timeout=30
EOF

put "$OUT/gtklock/style.css" <<EOF
/* $HDR */
window {
    background-size: cover;
    background-position: center;
    background-color: #$(h SURFACE);
}
#window-box { padding: 48px; }
#clock-label {
    font-family: "Google Sans Flex", sans-serif;
    font-size: 110px;
    font-weight: 300;
    color: #$(h ON_SURFACE);
    text-shadow: 0 2px 12px rgba(0, 0, 0, 0.5);
}
#date-label {
    font-family: "Google Sans Flex", sans-serif;
    font-size: 20px;
    color: #$(h PRIMARY);
    margin-bottom: 36px;
}
#input-label { opacity: 0; }
#input-field {
    min-width: 300px;
    min-height: 44px;
    padding: 0 16px;
    border-radius: 22px;
    border: 2px solid #$(h PRIMARY);
    background: #$(h SURFACE_CONTAINER);
    color: #$(h ON_SURFACE);
    caret-color: #$(h PRIMARY);
    box-shadow: none;
    font-family: "JetBrainsMono Nerd Font", monospace;
}
#input-field:focus { border-color: #$(h TERTIARY); }
#unlock-button { opacity: 0; min-width: 0; min-height: 0; padding: 0; }
#error-label { color: #$(h ERROR); }
#warning-label { color: #$(h TERTIARY); }
EOF

# ── hyprlock (lock.sh runs hyprlock -c this file; ~/.config/hypr is Hyprland's) ─
put "$OUT/mango/hyprlock.conf" <<EOF
# $HDR
general {
    hide_cursor = true
    ignore_empty_input = true
}

background {
    monitor =
    path = $HOME/.config/mango/lockscreen
    blur_passes = 3
    blur_size = 8
    brightness = 0.6
    vibrancy = 0.15
}

# clock
label {
    monitor =
    text = cmd[update:1000] date +'%H:%M'
    color = rgb($(h ON_SURFACE))
    font_size = 120
    font_family = Google Sans Flex Bold
    position = 0, 200
    halign = center
    valign = center
}

# date
label {
    monitor =
    text = cmd[update:60000] date +'%A, %d %B'
    color = rgb($(h ON_SURFACE_VARIANT))
    font_size = 22
    font_family = Google Sans Flex
    position = 0, 90
    halign = center
    valign = center
}

input-field {
    monitor =
    size = 320, 56
    outline_thickness = 3
    rounding = 12
    dots_size = 0.25
    dots_spacing = 0.4
    dots_center = true
    outer_color = rgb($(h PRIMARY))
    inner_color = rgba($(h SURFACE)e6)
    font_color = rgb($(h ON_SURFACE))
    font_family = Google Sans Flex
    check_color = rgb($(h TERTIARY))
    fail_color = rgb($(h ERROR))
    capslock_color = rgb($(h SECONDARY))
    fade_on_empty = false
    placeholder_text = <span foreground="#$(h ON_SURFACE_VARIANT)">Password</span>
    fail_text = <span foreground="#$(h ERROR)">\$FAIL (\$ATTEMPTS)</span>
    position = 0, -40
    halign = center
    valign = center
}

# user
label {
    monitor =
    text = \$USER
    color = rgb($(h PRIMARY))
    font_size = 16
    font_family = JetBrainsMono Nerd Font
    position = 0, 60
    halign = center
    valign = bottom
}
EOF

# ── kitty (colours + tab bar; kitty.conf: include theme.conf) ────────────────
{
    cat <<EOF
# $HDR
foreground            $TERM_FG
background            $TERM_BG
selection_foreground  $SELECTION_FG
selection_background  $SELECTION_BG
cursor                $CURSOR
cursor_text_color     $TERM_BG
url_color             $PRIMARY
active_border_color   $PRIMARY
inactive_border_color $OUTLINE_VARIANT

EOF
    for i in $(seq 0 15); do v="COLOR$i"; printf 'color%-3s %s\n' "$i" "${!v}"; done
    cat <<EOF

tab_bar_edge            top
tab_bar_style           powerline
tab_powerline_style     slanted
tab_bar_align           left
tab_bar_min_tabs        2
tab_bar_margin_width    0.0
tab_bar_margin_height   2.5 1.5
tab_bar_margin_color    $TERM_BG
tab_bar_background      $TERM_BG

active_tab_foreground   $ON_PRIMARY
active_tab_background   $PRIMARY
active_tab_font_style   bold
inactive_tab_foreground $TERM_FG
inactive_tab_background $TERM_BG
inactive_tab_font_style normal

tab_activity_symbol     " ● "
tab_title_template        "{fmt.fg.red}{bell_symbol}{activity_symbol}{fmt.fg.tab}{title[:30]}{title[30:] and '…'} [{index}]"
active_tab_title_template "{fmt.fg.red}{bell_symbol}{activity_symbol}{fmt.fg.tab}{title[:30]}{title[30:] and '…'} [{index}]"
EOF
} | put "$OUT/kitty/theme.conf"

# ── btop (btop.conf already says color_theme = "matugen"; read at btop start) ─
put "$OUT/btop/themes/matugen.theme" <<EOF
# $HDR
theme[main_bg]="$TERM_BG"
theme[main_fg]="$TERM_FG"
theme[title]="$TERM_FG"
theme[hi_fg]="$PRIMARY"
theme[selected_bg]="$SURFACE_CONTAINER_HIGH"
theme[selected_fg]="$PRIMARY"
theme[inactive_fg]="$OUTLINE"
theme[graph_text]="$ON_SURFACE_VARIANT"
theme[meter_bg]="$SURFACE_CONTAINER_HIGH"
theme[proc_misc]="$ON_SURFACE_VARIANT"
theme[cpu_box]="$COLOR5"
theme[mem_box]="$COLOR2"
theme[net_box]="$COLOR1"
theme[proc_box]="$PRIMARY"
theme[div_line]="$OUTLINE"
theme[temp_start]="$COLOR2"
theme[temp_mid]="$COLOR3"
theme[temp_end]="$COLOR1"
theme[cpu_start]="$COLOR6"
theme[cpu_mid]="$COLOR4"
theme[cpu_end]="$COLOR5"
theme[free_start]="$COLOR5"
theme[free_mid]="$COLOR4"
theme[free_end]="$COLOR6"
theme[cached_start]="$COLOR4"
theme[cached_mid]="$COLOR6"
theme[cached_end]="$COLOR5"
theme[available_start]="$COLOR3"
theme[available_mid]="$COLOR1"
theme[available_end]="$COLOR1"
theme[used_start]="$COLOR2"
theme[used_mid]="$COLOR6"
theme[used_end]="$COLOR4"
theme[download_start]="$COLOR3"
theme[download_mid]="$COLOR1"
theme[download_end]="$COLOR1"
theme[upload_start]="$COLOR2"
theme[upload_mid]="$COLOR6"
theme[upload_end]="$COLOR4"
theme[process_start]="$COLOR6"
theme[process_mid]="$COLOR4"
theme[process_end]="$COLOR5"
EOF

[ -n "${THEME_OUT:-}" ] && { echo "theme: $name rendered into $OUT"; exit 0; }

printf '%s\n' "$name" | put "$CURRENT"

# ── wallpaper: switch to the theme's own backgrounds, omarchy-style ──────────
# Skipped for "wallpaper" (the colours came FROM the wallpaper) and when the
# current wallpaper already belongs to this theme. current-theme is written
# first, so wallpaper.sh will not re-theme (it only does that for "wallpaper").
if [ "$keep_wall" -eq 0 ] && [ "$name" != wallpaper ] && [ -d "$DIR/backgrounds" ]; then
    cur="$(cat "$WALL_STATE" 2>/dev/null)"
    if [ "${cur#"$DIR/backgrounds/"}" = "$cur" ]; then
        first="$(find -L "$DIR/backgrounds" -maxdepth 1 -type f \
            \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) | sort | head -1)"
        [ -n "$first" ] && "$MANGO/scripts/wallpaper.sh" set "$first" >/dev/null
    fi
fi

[ "$reload" -eq 1 ] || { echo "theme: $name (no reload)"; exit 0; }

# ── reload everything that is running ────────────────────────────────────────
# Send SIGUSR1 only to processes that actually handle it (caught, or blocked
# for a signalfd as kitty does). Its default action is to terminate, so an
# older mangobar without a reload handler would otherwise just die.
usr1() {
    local pid cgt blk
    for pid in $(pgrep -x "$1"); do
        read -r cgt blk < <(awk '/^SigCgt:/{c=$2} /^SigBlk:/{b=$2} END{print c, b}' \
            "/proc/$pid/status" 2>/dev/null)
        # bit 9 = signal 10 = SIGUSR1
        if (( (16#${cgt:-0} | 16#${blk:-0}) & 0x200 )); then
            kill -USR1 "$pid" 2>/dev/null
        fi
    done
}

mmsg dispatch reload_config >/dev/null 2>&1
makoctl reload >/dev/null 2>&1
usr1 kitty
usr1 mangobar

notify-send -a Theme "Theme" "$NAME" 2>/dev/null || true
echo "theme: $name"
