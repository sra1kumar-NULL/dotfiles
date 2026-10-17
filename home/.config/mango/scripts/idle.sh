#!/usr/bin/env bash
# Start the idle daemon (lock at 10 min, screen off at 15). Single definition,
# used by autostart and by inhibit.sh when stay-awake is turned off.
S=/home/sasuke/.config/mango/scripts
pgrep -x swayidle >/dev/null && exit 0
exec /usr/bin/swayidle -w \
    timeout 600 "$S/lock.sh" \
    timeout 900 "$S/dpms.sh off" resume "$S/dpms.sh on" \
    before-sleep "$S/lock.sh"
