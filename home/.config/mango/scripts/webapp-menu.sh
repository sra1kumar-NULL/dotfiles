#!/usr/bin/env bash
# Install -> Web App: pick one of omarchy's defaults or type a name + URL.
# Nothing is installed until you choose it here.
set -uo pipefail
DIR="$(dirname "$(readlink -f "$0")")"
ICON_CDN="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png"

# name|url|icon (icon falls back to the site favicon if the CDN lacks it)
suggestions="YouTube|https://youtube.com/|$ICON_CDN/youtube.png
ChatGPT|https://chatgpt.com/|$ICON_CDN/chatgpt.png
Claude|https://claude.ai/|$ICON_CDN/claude-ai.png
GitHub|https://github.com/|$ICON_CDN/github.png
WhatsApp|https://web.whatsapp.com/|$ICON_CDN/whatsapp.png
Google Photos|https://photos.google.com/|$ICON_CDN/google-photos.png
Google Maps|https://maps.google.com/|$ICON_CDN/google-maps.png
Gmail|https://mail.google.com/|$ICON_CDN/gmail.png
X|https://x.com/|$ICON_CDN/x.png
Basecamp|https://launchpad.37signals.com/|$ICON_CDN/basecamp.png
HEY|https://app.hey.com/|$ICON_CDN/hey.png"

custom="Custom…"
pick="$( { printf '%s\n' "$custom"; printf '%s\n' "$suggestions" | cut -d'|' -f1; } |
    fuzzel --dmenu --prompt 'web app  ' --lines 12)" || exit 0
[ -n "$pick" ] || exit 0

if [ "$pick" = "$custom" ]; then
    name="$(fuzzel --dmenu --prompt-only 'name  ' --placeholder 'e.g. Notion' </dev/null)" || exit 0
    [ -n "$name" ] || exit 0
    url="$(fuzzel --dmenu --prompt-only 'url  ' --placeholder 'https://…' </dev/null)" || exit 0
    [ -n "$url" ] || exit 0
    icon=""
else
    line="$(printf '%s\n' "$suggestions" | awk -F'|' -v n="$pick" '$1 == n { print; exit }')"
    [ -n "$line" ] || exit 0
    IFS='|' read -r name url icon <<<"$line"
fi

if ! out="$("$DIR/webapp-install.sh" "$name" "$url" "$icon" 2>&1)"; then
    notify-send -a "Web apps" -u critical "Could not install $name" "$out" 2>/dev/null
    exit 1
fi
