#!/usr/bin/env bash
# Reveal the saved PSK for a Wi-Fi connection and copy it to the clipboard.
# nmcli needs --show-secrets; without it the psk field comes back empty.
set -uo pipefail
ssid="${1:-}"
if [ -z "$ssid" ]; then
    ssid="$(nmcli -t -f NAME,TYPE connection show 2>/dev/null |
        awk -F: '$2 == "802-11-wireless" { print $1 }' |
        fuzzel --dmenu --prompt "password for  " --lines 10 --width 40)"
fi
[ -n "$ssid" ] || exit 0

psk="$(nmcli --show-secrets -t -f 802-11-wireless-security.psk connection show "$ssid" 2>/dev/null |
    cut -d: -f2-)"
if [ -z "$psk" ]; then
    notify-send -a Network "No saved password" "$ssid" 2>/dev/null
    exit 1
fi
printf '%s' "$psk" | wl-copy
notify-send -a Network "$ssid" "$psk

copied to clipboard" 2>/dev/null
