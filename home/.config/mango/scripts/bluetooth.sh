#!/usr/bin/env bash
# Bluetooth menu for the mango light stack.
set -uo pipefail

menu() { fuzzel --dmenu --prompt "$1  " --lines "${2:-12}" --width "${3:-48}"; }
note() { notify-send -a "Bluetooth" "$1" "${2:-}" 2>/dev/null || true; }

powered="$(bluetoothctl show 2>/dev/null | awk '/Powered:/ { print $2; exit }')"

# `bluetoothctl devices` lists what is known; Connected is per-device, so it has
# to be read from `info` rather than the list.
device_lines() {
    local mac name
    bluetoothctl devices 2>/dev/null | while read -r _ mac name; do
        [ -n "$mac" ] || continue
        if bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes"; then
            printf ' %s  %s\n' "$mac" "$name"
        else
            printf '  %s  %s\n' "$mac" "$name"
        fi
    done
}

mac_of() {
    # Lines are "<mark> <MAC>  <name>"; the MAC is the only field with colons.
    printf '%s' "$1" | tr ' ' '\n' | grep -m1 -E '^([0-9A-F]{2}:){5}[0-9A-F]{2}$'
}

main() {
    local header choice mac
    if [ "$powered" = "yes" ]; then
        header=$'  Turn Bluetooth off\n  Scan for 10s\n  Manager (blueman)'
    else
        header=$'  Turn Bluetooth on\n  Manager (blueman)'
    fi

    choice="$(
        {
            printf '%s\n' "$header"
            [ "$powered" = "yes" ] && device_lines
        } | menu "bt"
    )"
    [ -n "$choice" ] || exit 0

    case "$choice" in
        *"Turn Bluetooth off") bluetoothctl power off >/dev/null; note "Bluetooth" "Off" ;;
        *"Turn Bluetooth on")  bluetoothctl power on >/dev/null; note "Bluetooth" "On" ;;
        *"Manager (blueman)")  setsid blueman-manager >/dev/null 2>&1 & ;;
        *"Scan for 10s")
            note "Scanning" "10 seconds"
            bluetoothctl --timeout 10 scan on >/dev/null 2>&1
            exec "$0"
            ;;
        *)
            mac="$(mac_of "$choice")"
            [ -n "$mac" ] || exit 0
            if bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes"; then
                bluetoothctl disconnect "$mac" >/dev/null 2>&1
                note "Disconnected" "$mac"
            else
                note "Connecting" "$mac"
                # Pair first if it is a new device; already-paired returns an
                # error that is safe to ignore.
                bluetoothctl pair "$mac" >/dev/null 2>&1
                bluetoothctl trust "$mac" >/dev/null 2>&1
                if bluetoothctl connect "$mac" >/dev/null 2>&1; then
                    note "Connected" "$mac"
                else
                    note "Failed" "Could not connect to $mac"
                fi
            fi
            ;;
    esac
}

main
