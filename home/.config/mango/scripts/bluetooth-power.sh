#!/usr/bin/env bash
set -uo pipefail
powered="$(bluetoothctl show 2>/dev/null | awk '/Powered:/ { print $2; exit }')"
case "${1:-toggle}" in
    on)  want=on ;;
    off) want=off ;;
    *)   [ "$powered" = "yes" ] && want=off || want=on ;;
esac
bluetoothctl power "$want" >/dev/null 2>&1
notify-send -a Bluetooth "Bluetooth" "${want^}" 2>/dev/null
