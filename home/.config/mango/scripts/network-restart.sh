#!/usr/bin/env bash
# Bounce the radio. Faster than restarting NetworkManager and does not drop
# a wired connection along with it.
set -uo pipefail
notify-send -a Network "Restarting Wi-Fi" 2>/dev/null
nmcli radio wifi off
sleep 2
nmcli radio wifi on
sleep 3
notify-send -a Network "Wi-Fi restarted" "$(./network-state.sh)" 2>/dev/null
