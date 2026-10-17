#!/usr/bin/env bash
# Wallpaper for the mango light stack (swaybg + swaylock image).
#
# Setting a wallpaper only re-themes when the active theme is "wallpaper"
# (colours derived from the image). With a curated theme it just sets the image.
#
# `next` cycles, omarchy-style, through the active theme's backgrounds/ dir when
# it has one, otherwise through ~/Pictures/Wallpapers (or $WALLPAPER_DIR).
#
#   wallpaper.sh [next]       # next wallpaper in the current set
#   wallpaper.sh set <path>   # specific image
#   wallpaper.sh restore      # re-apply the saved one (login); never re-themes
#   wallpaper.sh current      # print the saved path
#   wallpaper.sh dir          # print the directory `next` cycles through
set -uo pipefail

MANGO="$HOME/.config/mango"
STATE="$HOME/.local/state/mango-wallpaper"
USER_DIR="${WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}"

current()       { [ -r "$STATE" ] && cat "$STATE"; }
current_theme() { cat "$MANGO/current-theme" 2>/dev/null; }

wall_dir() {
    local t bg
    t="$(current_theme)"
    bg="$MANGO/themes/$t/backgrounds"
    if [ -n "$t" ] && [ "$t" != wallpaper ] && [ -d "$bg" ] \
       && [ -n "$(find -L "$bg" -maxdepth 1 -type f | head -1)" ]; then
        printf '%s' "$bg"
    else
        printf '%s' "$USER_DIR"
    fi
}

pick_next() {
    local dir; dir="$(wall_dir)"
    mapfile -t all < <(find -L "$dir" -maxdepth 1 -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) | sort)
    [ "${#all[@]}" -eq 0 ] && return 1
    local cur idx=0
    cur="$(current)"
    for i in "${!all[@]}"; do [ "${all[$i]}" = "$cur" ] && { idx=$(( (i+1) % ${#all[@]} )); break; }; done
    printf '%s' "${all[$idx]}"
}

apply() {
    local wall="$1" retheme="$2"
    [ -r "$wall" ] || { echo "no such wallpaper: $wall" >&2; exit 1; }
    mkdir -p "$(dirname "$STATE")"
    printf '%s' "$wall" > "$STATE"

    # swaybg cannot reload, so replace it.
    pkill -x swaybg 2>/dev/null
    setsid swaybg -m fill -i "$wall" >/dev/null 2>&1 &
    disown 2>/dev/null || true

    # The lock screens read this link; pre-blur it for gtklock in the background.
    ln -sfn "$wall" "$MANGO/lockscreen"
    setsid "$MANGO/scripts/lock.sh" --prerender >/dev/null 2>&1 < /dev/null &

    if [ "$retheme" = 1 ] && [ "$(current_theme)" = wallpaper ]; then
        "$MANGO/scripts/theme-set.sh" wallpaper >/dev/null
    fi
    echo "wallpaper: $wall"
}

case "${1:-next}" in
    next)    w="$(pick_next)" || { echo "no wallpapers in $(wall_dir)" >&2; exit 1; }; apply "$w" 1 ;;
    set)     apply "${2:?usage: wallpaper.sh set <path>}" 1 ;;
    restore) w="$(current)"; if [ -n "$w" ] && [ -r "$w" ]; then apply "$w" 0; else exec "$0" next; fi ;;
    current) current; echo ;;
    dir)     wall_dir; echo ;;
    *)       echo "usage: wallpaper.sh [next|set <path>|restore|current|dir]" >&2; exit 2 ;;
esac
