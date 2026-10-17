#!/usr/bin/env bash
# Extract text from a screen region (omarchy-capture-text): slurp a rectangle,
# run it through tesseract and put the text on the clipboard.
set -uo pipefail

for cmd in grim slurp wl-copy tesseract; do
    if ! command -v "$cmd" >/dev/null; then
        hint="$cmd"
        [ "$cmd" = tesseract ] && hint="tesseract tesseract-langpack-eng"
        notify-send -a OCR "install $hint" "sudo dnf install $hint" 2>/dev/null
        exit 1
    fi
done

geom="$(slurp -d)" || exit 0
text="$(grim -g "$geom" -t png - | tesseract - - -l "${OCR_LANG:-eng}" 2>/dev/null)"
text="$(printf '%s' "$text" | sed -e 's/[[:space:]]*$//' -e '/./,$!d')"

if [ -z "$text" ]; then
    notify-send -a OCR "No text found" 2>/dev/null
    exit 1
fi
printf '%s' "$text" | wl-copy
notify-send -a OCR "Text copied" "$(printf '%s' "$text" | head -c 200)" 2>/dev/null
