#!/usr/bin/env bash
# Volume/brightness with a wob overlay.
set -uo pipefail
FIFO="${XDG_RUNTIME_DIR:-/tmp}/wob.fifo"
emit() { [ -p "$FIFO" ] && printf '%s\n' "$1" > "$FIFO" || true; }

vol() { wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{printf "%d", $2*100}'; }

case "${1:-}" in
    volume)
        case "${2:-}" in
            up)   wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+ ;;
            down) wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- ;;
            mute) wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
            mic)  wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle; exit 0 ;;
        esac
        if wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q MUTED; then emit 0; else emit "$(vol)"; fi ;;
    brightness)
        case "${2:-}" in
            up)   brightnessctl -q set 5%+ ;;
            down) brightnessctl -q set 5%- ;;
        esac
        emit "$(brightnessctl -m | cut -d, -f4 | tr -d '%')" ;;
    *) echo "usage: osd.sh {volume {up|down|mute|mic}|brightness {up|down}}" >&2; exit 2 ;;
esac
