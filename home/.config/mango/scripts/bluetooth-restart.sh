#!/usr/bin/env bash
set -uo pipefail
notify-send -a Bluetooth "Restarting" 2>/dev/null
bluetoothctl power off >/dev/null 2>&1
sleep 2
bluetoothctl power on >/dev/null 2>&1
notify-send -a Bluetooth "Bluetooth restarted" 2>/dev/null
