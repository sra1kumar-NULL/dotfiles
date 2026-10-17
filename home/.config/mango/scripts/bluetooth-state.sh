#!/usr/bin/env bash
set -uo pipefail
powered="$(bluetoothctl show 2>/dev/null | awk '/Powered:/ { print $2; exit }')"
[ "$powered" = "yes" ] || { echo "off"; exit 0; }
name="$(bluetoothctl devices Connected 2>/dev/null | head -1 | cut -d' ' -f3-)"
[ -n "$name" ] && echo "$name" || echo "on"
