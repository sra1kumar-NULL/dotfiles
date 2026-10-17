#!/usr/bin/env bash
# Show a joinable Wi-Fi QR code, the format phone cameras expect.
set -uo pipefail

command -v qrencode >/dev/null || {
    notify-send -a Network "qrencode not installed" "sudo dnf install qrencode" 2>/dev/null
    exit 1
}

ssid="${1:-$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null |
    awk -F: '$2 == "802-11-wireless" { print $1; exit }')}"
[ -n "$ssid" ] || { notify-send -a Network "Not on Wi-Fi" 2>/dev/null; exit 1; }

# --show-secrets is required; without it nmcli returns the key as empty.
psk="$(nmcli --show-secrets -t -f 802-11-wireless-security.psk connection show "$ssid" 2>/dev/null |
    cut -d: -f2-)"
auth="WPA"
[ -z "$psk" ] && auth="nopass"

# \ ; , : and " are delimiters in the WIFI: payload and have to be escaped.
esc() { sed 's/[\;,:"]/\\&/g' <<<"$1"; }

png="$(mktemp -t mango-wifi-XXXXXX.png)"
trap 'rm -f "$png"' EXIT
qrencode -o "$png" -s 10 -m 3 "WIFI:T:$auth;S:$(esc "$ssid");P:$(esc "$psk");;" || {
    notify-send -a Network "Could not generate QR" 2>/dev/null
    exit 1
}

# kitty renders it inline with its own image protocol. No standalone image
# viewer is installed on this box (imv/swayimg/loupe/eog are all absent), and
# the registered image/png handler is a full photo manager — far too heavy for
# glancing at a QR code.
if command -v kitten >/dev/null; then
    kitty --class mango-float -o confirm_os_window_close=0 \
        -e sh -c "clear; echo; echo '  $ssid'; echo; kitten icat --align left '$png'; echo; read -rp '  press enter '"
else
    xdg-open "$png" >/dev/null 2>&1
    sleep 5   # the trap would delete the file before the viewer reads it
fi
