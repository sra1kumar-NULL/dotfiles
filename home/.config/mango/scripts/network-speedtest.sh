#!/usr/bin/env bash
set -uo pipefail
if command -v speedtest-cli >/dev/null; then
    exec kitty --class mango-float -e sh -c 'speedtest-cli; echo; read -rp "press enter "'
fi
notify-send -a Network "speedtest-cli not installed" "sudo dnf install speedtest-cli" 2>/dev/null
exit 1
