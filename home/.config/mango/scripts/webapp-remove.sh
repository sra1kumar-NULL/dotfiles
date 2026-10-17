#!/usr/bin/env bash
# Remove a web app made by webapp-install.sh.
#
#   webapp-remove.sh <slug|name>   remove that one
#   webapp-remove.sh               pick from the installed web apps (fuzzel)
#
# Only .desktop files carrying X-WebApp-URL are touched, so Chrome's own
# chrome-*-Default.desktop PWAs and every other launcher are left alone.
set -uo pipefail

APPS="$HOME/.local/share/applications"

list() {
    grep -l '^X-WebApp-URL=' "$APPS"/*.desktop 2>/dev/null | while read -r f; do
        printf '%s\t%s\n' "$(basename "$f" .desktop)" "$(sed -n 's/^Name=//p' "$f" | head -1)"
    done
}

target="${1:-}"
if [ -z "$target" ]; then
    entries="$(list)"
    [ -n "$entries" ] || { notify-send -a "Web apps" "No web apps installed" 2>/dev/null; exit 0; }
    pick="$(printf '%s\n' "$entries" | cut -f2 | fuzzel --dmenu --prompt 'remove web app  ' \
        --lines "$(printf '%s\n' "$entries" | wc -l)")" || exit 0
    target="$(printf '%s\n' "$entries" | awk -F'\t' -v n="$pick" '$2 == n { print $1; exit }')"
fi
[ -n "$target" ] || exit 0

# Accept a display name as well as a slug.
desk="$APPS/$target.desktop"
if [ ! -r "$desk" ]; then
    slug="$(list | awk -F'\t' -v n="$target" '$2 == n { print $1; exit }')"
    desk="$APPS/$slug.desktop"
fi
if [ ! -r "$desk" ] || ! grep -q '^X-WebApp-URL=' "$desk"; then
    echo "not a web app: $target" >&2
    exit 1
fi

slug="$(basename "$desk" .desktop)"
name="$(sed -n 's/^Name=//p' "$desk" | head -1)"
rm -f "$desk" "$APPS/icons/$slug.png"
command -v update-desktop-database >/dev/null && update-desktop-database "$APPS" 2>/dev/null || true
echo "removed $name"
notify-send -a "Web apps" "$name removed" 2>/dev/null || true
