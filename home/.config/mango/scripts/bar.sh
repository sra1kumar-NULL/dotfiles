#!/usr/bin/env bash
# Start one mangobar per connected output.
#
# mangobar anchors a single layer surface and takes --output <name>. Without it
# the compositor decides which output gets the bar, so on this dual-head setup
# one screen ends up with no bar at all. This starts one instance per monitor
# that mango reports.
#
#   bar.sh            # start (no-op for instances already running)
#   bar.sh restart    # after a monitor hotplug, or to pick up a rebuild
#   bar.sh stop
#   bar.sh reload     # re-read ~/.config/mango/mangobar.css (SIGUSR1), no restart
set -uo pipefail

BIN="$HOME/.local/bin/mangobar"

case "${1:-start}" in
    stop)
        pkill -x mangobar
        exit 0
        ;;
    reload)
        pkill -USR1 -x mangobar
        exit 0
        ;;
    restart)
        pkill -x mangobar
        sleep 0.3
        ;;
    start) ;;
    *)
        echo "usage: bar.sh [start|restart|stop|reload]" >&2
        exit 2
        ;;
esac

[ -x "$BIN" ] || {
    echo "bar.sh: $BIN missing — run ~/.config/mango/scripts/rebuild-mangobar.sh" >&2
    exit 1
}

# Already up (and not a restart)? Leave it alone.
if [ "${1:-start}" = "start" ] && pgrep -x mangobar >/dev/null; then
    exit 0
fi

# mango's monitor objects are the only place "name" appears, so this needs no
# JSON parser. active_client carries title/appid, not name.
# At exec_once time the compositor may not have enumerated outputs yet, so give
# it a moment rather than falling back to a single bar on a cold login.
monitors=()
for _ in 1 2 3 4 5 6 7 8 9 10; do
    mapfile -t monitors < <(
        mmsg get all-monitors 2>/dev/null |
            grep -o '"name":"[^"]*"' |
            cut -d'"' -f4
    )
    [ "${#monitors[@]}" -gt 0 ] && break
    sleep 0.5
done

if [ "${#monitors[@]}" -eq 0 ]; then
    # Compositor not answering yet: one bar is better than none, and it will
    # land on whichever output mango picks.
    echo "bar.sh: mmsg reported no monitors, starting a single unpinned bar" >&2
    ( setsid "$BIN" >/dev/null 2>&1 & )
    exit 0
fi

for monitor in "${monitors[@]}"; do
    ( setsid "$BIN" --output "$monitor" >/dev/null 2>&1 & )
done

echo "bar.sh: started ${#monitors[@]} bar(s): ${monitors[*]}"
