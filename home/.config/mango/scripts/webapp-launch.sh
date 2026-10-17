#!/usr/bin/env bash
# Launch a web app, or focus it if it is already open (omarchy-launch-or-focus-webapp).
#
#   webapp-launch.sh <slug>      slug = basename of the .desktop file
#
# Chrome on Wayland names an --app window "chrome-<host>__<path>-<profile>",
# e.g. chrome-www.youtube.com__-Default; --class only applies under X11, so both
# forms are matched. mango focuses by client id: `mmsg dispatch focusid client,<id>`
# switches to the window's tag and focuses it.
set -uo pipefail

slug="${1:-}"
desk="$HOME/.local/share/applications/$slug.desktop"
[ -n "$slug" ] && [ -r "$desk" ] || { notify-send -a "Web apps" "no web app: $slug" 2>/dev/null; exit 1; }

url="$(sed -n 's/^X-WebApp-URL=//p' "$desk" | head -1)"
host="$(sed -n 's/^X-WebApp-Host=//p' "$desk" | head -1)"
[ -n "$url" ] || { notify-send -a "Web apps" "$slug has no X-WebApp-URL" 2>/dev/null; exit 1; }

browser="${WEBAPP_BROWSER:-google-chrome-stable}"
command -v "$browser" >/dev/null || { notify-send -a "Web apps" "install $browser" 2>/dev/null; exit 1; }

if command -v mmsg >/dev/null && command -v jq >/dev/null; then
    id="$(mmsg get all-clients 2>/dev/null | jq -r --arg c "webapp-$slug" --arg h "chrome-${host}__" '
        .clients[] | select((.appid | ascii_downcase) == $c or (.appid | startswith($h)))
        | .id' | head -1)"
    if [ -n "$id" ]; then
        mmsg dispatch focusid "client,$id" >/dev/null 2>&1 && exit 0
    fi
fi

exec setsid "$browser" --app="$url" --class="webapp-$slug" >/dev/null 2>&1
