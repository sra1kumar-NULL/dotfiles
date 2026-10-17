#!/usr/bin/env bash
# Low-battery warning, run every minute by ~/.config/systemd/user/battery-warn.timer.
#
# Notifies once per discharge crossing:
#   <= 15%  normal toast
#   <=  5%  critical toast (mako keeps critical toasts until dismissed)
# The "already warned" level is remembered in $XDG_RUNTIME_DIR and reset as
# soon as the battery is charging again, so the next discharge warns afresh.
#
# Only BAT* is read: /sys/class/power_supply also lists hidpp_battery_* (a
# wireless mouse), the AC adapter and USB-C sources.
set -uo pipefail

LOW=15
CRITICAL=5
state="${BATTERY_STATE:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/battery-warn.level}"

bat=""
for b in "${BATTERY_SYSFS:-/sys/class/power_supply}"/BAT*; do
    [ -r "$b/capacity" ] && { bat="$b"; break; }
done
[ -n "$bat" ] || exit 0

cap="$(cat "$bat/capacity" 2>/dev/null)" || exit 0
status="$(cat "$bat/status" 2>/dev/null)" || exit 0
warned="$(cat "$state" 2>/dev/null || echo 100)"

if [ "$status" != "Discharging" ]; then
    rm -f "$state"
    exit 0
fi

if [ "$cap" -le "$CRITICAL" ] && [ "$warned" -gt "$CRITICAL" ]; then
    notify-send -a Battery -u critical -i battery-caution \
        "Battery critical: ${cap}%" "Plug in now -- the laptop will shut down soon."
    echo "$CRITICAL" >"$state"
elif [ "$cap" -le "$LOW" ] && [ "$warned" -gt "$LOW" ]; then
    notify-send -a Battery -u normal -i battery-low \
        "Battery low: ${cap}%" "Consider plugging in."
    echo "$LOW" >"$state"
fi
exit 0
