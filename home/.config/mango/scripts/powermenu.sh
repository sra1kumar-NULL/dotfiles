#!/usr/bin/env bash
# fuzzel-based power menu.
set -uo pipefail
choice="$(printf '%s\n' \
    "  Lock" \
    "  Suspend" \
    "  Log out" \
    "  Reboot" \
    "  Shut down" \
    | fuzzel --dmenu --prompt "power  " --lines 5 --width 18)"
case "$choice" in
    *Lock)      exec "$HOME/.config/mango/scripts/lock.sh" ;;
    *Suspend)   systemctl suspend ;;
    *"Log out") mmsg dispatch quit ;;
    *Reboot)    systemctl reboot ;;
    *"Shut down") systemctl poweroff ;;
esac
