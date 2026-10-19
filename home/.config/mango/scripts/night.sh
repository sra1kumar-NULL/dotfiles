#!/usr/bin/env bash
# Toggle wlsunset.
set -uo pipefail
if pgrep -x wlsunset >/dev/null; then
    pkill -x wlsunset
    notify-send "Night light" "Off" 2>/dev/null || true
else
    # Fixed temperatures rather than coordinates, so no location lookup is needed.
    setsid wlsunset -t 4000 -T 6500 -S 07:00 -s 17:00 -d 300 >/dev/null 2>&1 &
    notify-send "Night light" "On (4000K)" 2>/dev/null || true
fi
