#!/usr/bin/env bash
# Scan a QR code (or barcode) in a screen region with zbarimg and copy its
# contents to the clipboard.
set -uo pipefail

for cmd in grim slurp wl-copy zbarimg; do
    if ! command -v "$cmd" >/dev/null; then
        hint="$cmd"
        [ "$cmd" = zbarimg ] && hint="zbar"
        notify-send -a QR "install $hint" "sudo dnf install $hint" 2>/dev/null
        exit 1
    fi
done

geom="$(slurp -d)" || exit 0
data="$(grim -g "$geom" -t png - | zbarimg -q --raw - 2>/dev/null)"

if [ -z "$data" ]; then
    notify-send -a QR "No code found" 2>/dev/null
    exit 1
fi
printf '%s' "$data" | wl-copy
notify-send -a QR "QR contents copied" "$(printf '%s' "$data" | head -c 200)" 2>/dev/null
