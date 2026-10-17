#!/usr/bin/env bash
# Theme picker: fuzzel list of ~/.config/mango/themes/* with a colour swatch per
# theme (and the current wallpaper as the icon for "From wallpaper").
#
# fuzzel speaks Rofi's extended dmenu protocol, "label\0icon\x1f<png>". bash
# drops NUL bytes on assignment, so entries are printf'ed straight into the pipe.
# Swatches are cached in ~/.cache/mango/theme-swatches, keyed on a hash of the
# theme's colors.sh, so editing a palette regenerates its swatch.
#
#   theme-pick.sh            # pick and apply
#   theme-pick.sh --rebuild  # drop the swatch cache first
set -uo pipefail

MANGO="$HOME/.config/mango"
THEMES="$MANGO/themes"
CACHE="$HOME/.cache/mango/theme-swatches"
SIZE=96

[ "${1:-}" = "--rebuild" ] && rm -rf "$CACHE"
mkdir -p "$CACHE"

current="$(cat "$MANGO/current-theme" 2>/dev/null)"
mark="$(printf '')"   # nf-fa-check

# Background square with the accent as a wide band and four ANSI chips below.
swatch() {
    local dir="$1" key png
    key="$(sha256sum "$dir/colors.sh" | cut -c1-16)"
    png="$CACHE/$(basename "$dir")-$key.png"
    if [ ! -f "$png" ]; then
        (
            # shellcheck source=/dev/null
            . "$dir/colors.sh"
            local s=$SIZE b=$((SIZE / 8)) c=$(( (SIZE - 2 * (SIZE / 8)) / 4 ))
            magick -size "${s}x${s}" "xc:$TERM_BG" \
                -fill "$SURFACE_CONTAINER" -draw "rectangle $b $b $((s - b - 1)) $((s / 2))" \
                -fill "$PRIMARY" -draw "rectangle $((b * 2)) $((b * 2)) $((s - b * 2 - 1)) $((s / 2 - b))" \
                -fill "$COLOR1" -draw "rectangle $b $((s / 2 + b)) $((b + c - 1)) $((s - b - 1))" \
                -fill "$COLOR2" -draw "rectangle $((b + c)) $((s / 2 + b)) $((b + 2 * c - 1)) $((s - b - 1))" \
                -fill "$COLOR3" -draw "rectangle $((b + 2 * c)) $((s / 2 + b)) $((b + 3 * c - 1)) $((s - b - 1))" \
                -fill "$COLOR4" -draw "rectangle $((b + 3 * c)) $((s / 2 + b)) $((s - b - 1)) $((s - b - 1))" \
                "$png" 2>/dev/null
        ) || return 1
    fi
    printf '%s' "$png"
}

wall_thumb() {
    local wall key png
    wall="$(cat "$HOME/.local/state/mango-wallpaper" 2>/dev/null)"
    [ -r "$wall" ] || return 1
    key="$(printf '%s' "$wall" | sha256sum | cut -c1-16)"
    png="$CACHE/wallpaper-$key.png"
    if [ ! -f "$png" ] || [ "$wall" -nt "$png" ]; then
        magick "$wall[0]" -thumbnail "${SIZE}x${SIZE}^" -gravity center \
            -extent "${SIZE}x${SIZE}" "$png" 2>/dev/null || return 1
    fi
    printf '%s' "$png"
}

pretty() {
    sed -n "s/^NAME='\(.*\)'$/\1/p" "$1/colors.sh" 2>/dev/null | head -1
}

# label -> theme dir name
declare -A theme_of
order=()
for d in "$THEMES"/*/; do
    d="${d%/}"; n="$(basename "$d")"
    [ "$n" = wallpaper ] && continue
    [ -r "$d/colors.sh" ] || continue
    label="$(pretty "$d")"; label="${label:-$n}"
    theme_of[$label]="$n"; order+=("$label")
done
theme_of["From wallpaper"]=wallpaper; order+=("From wallpaper")

entries() {
    local label n icon shown
    for label in "${order[@]}"; do
        n="${theme_of[$label]}"
        if [ "$n" = wallpaper ]; then icon="$(wall_thumb)"; else icon="$(swatch "$THEMES/$n")"; fi
        shown="$label"; [ "$n" = "$current" ] && shown="$label  $mark"
        if [ -n "$icon" ]; then printf '%s\0icon\x1f%s\n' "$shown" "$icon"
        else printf '%s\n' "$shown"; fi
    done
}

command -v magick >/dev/null || { notify-send -a Theme "ImageMagick not installed" 2>/dev/null; }

choice="$(entries |
    fuzzel --dmenu --no-exit-on-keyboard-focus-loss \
        --prompt "theme  " --lines "${#order[@]}" --width 36)"
[ -n "$choice" ] || exit 0
choice="${choice%  "$mark"}"
name="${theme_of[$choice]:-}"
[ -n "$name" ] || exit 0
exec "$MANGO/scripts/theme-set.sh" "$name"
