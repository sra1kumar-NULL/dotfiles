#!/usr/bin/env bash
# Idle-lock state, shared by the toggle menu and mangobar's stay-awake icon.
# Single source of truth: inhibit.sh's pid file. A live systemd-inhibit pid
# means "inhibited" (stay awake); anything else means idle locking is on.
PIDF="${XDG_RUNTIME_DIR:-/tmp}/mango-inhibit.pid"
if [ -r "$PIDF" ] && kill -0 "$(cat "$PIDF" 2>/dev/null)" 2>/dev/null; then
    echo "inhibited"
else
    echo "on"
fi
