#!/usr/bin/env bash
# One-line Wi-Fi state. Shared by menu.sh and the bar module so both agree.
set -uo pipefail
[ "$(nmcli -t radio wifi 2>/dev/null)" = "enabled" ] || { echo "off"; exit 0; }
ssid="$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null |
    awk -F: '$2 == "802-11-wireless" { print $1; exit }')"
if [ -z "$ssid" ]; then
    # Wired counts as connected even with the radio on and no AP associated.
    wired="$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null |
        awk -F: '$2 == "802-3-ethernet" { print $1; exit }')"
    [ -n "$wired" ] && echo "wired" || echo "disconnected"
    exit 0
fi
sig="$(nmcli -t -f ACTIVE,SIGNAL device wifi list --rescan no 2>/dev/null |
    awk -F: '$1 == "yes" { print $2; exit }')"
[ -n "$sig" ] && echo "$ssid  ${sig}%" || echo "$ssid"
