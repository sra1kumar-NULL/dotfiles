#!/usr/bin/env bash
# Toggle stay-awake. swayidle ignores logind (systemd-inhibit) idle locks, so
# stay-awake stops swayidle outright and idle.sh restarts it. The holder
# process still blocks suspend and its pid file is the state the bar/menu read.
set -uo pipefail
PIDF="${XDG_RUNTIME_DIR:-/tmp}/mango-inhibit.pid"
S=/home/sasuke/.config/mango/scripts
if [ -r "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; then
    kill "$(cat "$PIDF")" 2>/dev/null; rm -f "$PIDF"
    setsid "$S/idle.sh" >/dev/null 2>&1 &
    notify-send "Keep awake" "Off" 2>/dev/null || true
else
    pkill -x swayidle
    setsid systemd-inhibit --what=idle:sleep --who=mango --why="user requested" sleep infinity >/dev/null 2>&1 &
    echo $! > "$PIDF"
    notify-send "Keep awake" "On" 2>/dev/null || true
fi
