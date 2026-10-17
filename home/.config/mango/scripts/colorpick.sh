#!/usr/bin/env bash
# Screen colour picker: grabs a single pixel with grim+slurp and reads it
# back with ImageMagick (no compositor-specific picker needed).
set -uo pipefail
for cmd in grim slurp magick wl-copy; do
    command -v "$cmd" >/dev/null || { notify-send -a Colour "$cmd not installed" 2>/dev/null; exit 1; }
done

region="$(slurp -p)" || exit 0
hex="$(grim -g "$region" -t ppm - |
    magick - -format '%[hex:p{0,0}]' info: 2>/dev/null)"
[ -n "$hex" ] || { notify-send -a Colour "Could not read pixel" 2>/dev/null; exit 1; }

# magick may hand back 8-bit-per-channel RRGGBBAA; keep the first 6 digits.
hex="#${hex:0:6}"
printf '%s' "$hex" | wl-copy
notify-send -a Colour "$hex" "copied to clipboard" 2>/dev/null
