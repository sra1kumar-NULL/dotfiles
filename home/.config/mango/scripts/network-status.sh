#!/usr/bin/env bash
# Detailed connection status, as a notification. Mirrors omarchy-network-status.
set -uo pipefail
dev="$(nmcli -t -f DEVICE,STATE device 2>/dev/null | awk -F: '$2 == "connected" { print $1; exit }')"
[ -n "$dev" ] || { notify-send -a Network "Not connected" 2>/dev/null; exit 0; }

info="$(nmcli -t device show "$dev" 2>/dev/null)"
get() { awk -F: -v k="$1" '$1 == k { sub(/^[^:]*:/, ""); print; exit }' <<<"$info"; }

ip="$(get IP4.ADDRESS[1])"
gw="$(get IP4.GATEWAY)"
dns="$(get IP4.DNS[1])"
conn="$(get GENERAL.CONNECTION)"

notify-send -a Network "$conn" \
    "device   $dev
ip       ${ip:-–}
gateway  ${gw:-–}
dns      ${dns:-–}" 2>/dev/null
