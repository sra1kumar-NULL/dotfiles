#!/usr/bin/env bash
# Screenshots for mango (omarchy-capture-screenshot equivalent).
#
#   screenshot.sh region    drag a rectangle (default)
#   screenshot.sh window    click one of the visible windows
#   screenshot.sh output    the focused monitor
#   screenshot.sh all       every monitor
#
# Every capture is saved to ~/Pictures/Screenshots, copied to the clipboard and
# announced with a notification. If satty is installed the notification offers
# an "Edit" action that opens the shot in satty (saving over the same file).
set -uo pipefail

DIR="${SCREENSHOT_DIR:-$HOME/Pictures/Screenshots}"
mode="${1:-region}"

for cmd in grim slurp wl-copy; do
    command -v "$cmd" >/dev/null || { notify-send -a Screenshot "install $cmd" 2>/dev/null; exit 1; }
done
mkdir -p "$DIR"
file="$DIR/$(date +%Y%m%d-%H%M%S).png"

case "$mode" in
    region)
        geom="$(slurp -d)" || exit 0
        grim -g "$geom" "$file"
        ;;
    window)
        # mango reports client geometry in global layout coordinates, which is
        # exactly what slurp and grim use. -r restricts slurp to these boxes,
        # so a click picks a whole window.
        geom="$(mmsg get all-clients 2>/dev/null |
            jq -r '.clients[] | select(.is_visible and (.is_minimized | not))
                   | "\(.x),\(.y) \(.width)x\(.height)"' |
            slurp -r)" || exit 0
        grim -g "$geom" "$file"
        ;;
    output)
        mon="$(mmsg get all-monitors 2>/dev/null | jq -r '.monitors[] | select(.active) | .name' | head -1)"
        if [ -n "$mon" ]; then grim -o "$mon" "$file"; else grim "$file"; fi
        ;;
    all)
        grim "$file"
        ;;
    *)
        echo "usage: screenshot.sh [region|window|output|all]" >&2
        exit 2
        ;;
esac

[ -s "$file" ] || { notify-send -a Screenshot "Screenshot failed" 2>/dev/null; exit 1; }
wl-copy --type image/png <"$file"

# Notify in the background: notify-send --action blocks until the toast closes.
(
    if command -v satty >/dev/null; then
        act="$(notify-send -a Screenshot -i "$file" \
            --action=edit=Edit "Screenshot saved" "${file/#$HOME/\~}  ·  copied")"
        [ "$act" = "edit" ] && satty --filename "$file" --output-filename "$file" \
            --copy-command wl-copy --early-exit
    else
        notify-send -a Screenshot -i "$file" "Screenshot saved" \
            "${file/#$HOME/\~}  ·  copied  (install satty to annotate)"
    fi
) >/dev/null 2>&1 &
disown
exit 0
