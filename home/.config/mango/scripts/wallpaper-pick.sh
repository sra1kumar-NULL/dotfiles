#!/usr/bin/env bash
# Wallpaper picker with thumbnails. Selecting one applies it immediately.
#
# fuzzel speaks Rofi's extended dmenu protocol -- "label\0icon\x1f<path>" -- and
# renders PNGs, so the picker can show the actual wallpapers instead of a list of
# filenames. Thumbnails are cached and only regenerated when the source file is
# newer, so the first run pays for them once.
#
#   wallpaper-pick.sh            # pick one
#   wallpaper-pick.sh --rebuild  # drop the thumbnail cache first
set -uo pipefail

DIR="${WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}"
# The active theme's backgrounds/ (if any) are listed first, then your own.
THEME_DIR="$("$HOME/.config/mango/scripts/wallpaper.sh" dir)"
CACHE="$HOME/.cache/mango/wallpaper-thumbs"
SIZE=128

[ "${1:-}" = "--rebuild" ] && rm -rf "$CACHE"
mkdir -p "$CACHE"

command -v magick >/dev/null || {
    notify-send -a Wallpaper "ImageMagick not installed" "sudo dnf install ImageMagick" 2>/dev/null
    exit 1
}

list_dir() {
    find -L "$1" -maxdepth 1 -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) | sort
}
mapfile -t walls < <({ [ "$THEME_DIR" != "$DIR" ] && list_dir "$THEME_DIR"; list_dir "$DIR"; })
# label -> path, so the selection resolves across both directories
declare -A path_of
for w in "${walls[@]}"; do n="$(basename "$w")"; [ -n "${path_of[$n]:-}" ] || path_of[$n]="$w"; done
[ "${#walls[@]}" -gt 0 ] || { notify-send -a Wallpaper "No wallpapers in $DIR" 2>/dev/null; exit 1; }

current="$(cat "$HOME/.local/state/mango-wallpaper" 2>/dev/null)"
mark="$(printf '')"

# Written straight to the pipe, never collected in a variable: the dmenu
# protocol separates the label from the icon with a NUL, and bash silently drops
# NUL bytes on assignment, so building this as a string would have shipped a
# payload with no separators at all.
entries() {
    local wall key thumb name
    for wall in "${walls[@]}"; do
        # Key the cache on the full path so two files with the same basename in
        # different directories cannot collide.
        key="$(printf '%s' "$wall" | sha256sum | cut -c1-16)"
        thumb="$CACHE/$key.png"

        if [ ! -f "$thumb" ] || [ "$wall" -nt "$thumb" ]; then
            # ^ then -extent crops to a square centre, so tall and wide
            # wallpapers both read as the same tile instead of being letterboxed.
            magick "$wall[0]" -thumbnail "${SIZE}x${SIZE}^" -gravity center \
                -extent "${SIZE}x${SIZE}" "$thumb" 2>/dev/null || continue
        fi

        name="$(basename "$wall")"
        [ "$wall" = "$current" ] && name="$mark $name"
        printf '%s\0icon\x1f%s\n' "$name" "$thumb"
    done
}

choice="$(entries |
    fuzzel --dmenu --no-exit-on-keyboard-focus-loss \
        --prompt "wallpaper  " --lines 12 --width 42)"
[ -n "$choice" ] || exit 0

# Strip the "currently set" marker back off before resolving the path.
choice="${choice#"$mark" }"
exec "$HOME/.config/mango/scripts/wallpaper.sh" set "${path_of[$choice]:-$DIR/$choice}"
