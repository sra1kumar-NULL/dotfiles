#!/usr/bin/env bash
# Lock the session. gtklock first (styled by theme-set.sh: ~/.config/gtklock/),
# swaylock as the fallback when gtklock isn't installed.
#
# gtklock runs with -d: it returns once the session is locked, so swayidle's
# before-sleep hook lets the suspend proceed and swayidle -w is never left
# blocked waiting on the locker.
#
# `lock.sh --prerender` only refreshes the blurred background; wallpaper.sh
# calls it on every change so locking itself never waits on ImageMagick.

# gtklock has no blur, so it locks over a blurred copy of the wallpaper.
# Re-rendered only when the wallpaper changed (keyed by path + mtime).
prerender() {
    local wall blur stamp key
    wall="$(readlink -f "$HOME/.config/mango/lockscreen" 2>/dev/null)"
    blur="$HOME/.cache/mango/lock-blur.jpg"
    stamp="$blur.src"
    if [ -f "$wall" ] && command -v magick >/dev/null; then
        key="$wall $(stat -c %Y "$wall")"
        if [ ! -f "$blur" ] || [ "$(cat "$stamp" 2>/dev/null)" != "$key" ]; then
            mkdir -p "${blur%/*}"
            magick "$wall" -resize 1920x1080^ -blur 0x18 -fill black -colorize 25% \
                -quality 85 "$blur.tmp.jpg" && mv -f "$blur.tmp.jpg" "$blur" &&
                printf '%s' "$key" > "$stamp"
        fi
    fi
}

if [ "${1:-}" = --prerender ]; then prerender; exit 0; fi

pgrep -x gtklock >/dev/null && exit 0
pgrep -x swaylock >/dev/null && exit 0

if command -v gtklock >/dev/null; then
    prerender
    exec gtklock -d
fi

exec swaylock -f
