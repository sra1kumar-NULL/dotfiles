#!/usr/bin/env bash
# Blank/unblank every connected output. mango's sleep_monitor/wakeup_monitor take
# a single monitor_spec (there is no "all"), so iterate the live output list.
set -uo pipefail
act="${1:-off}"
mapfile -t outs < <(wlr-randr --json 2>/dev/null | jq -r '.[] | select(.enabled==true) | .name' 2>/dev/null)
[ "${#outs[@]}" -eq 0 ] && mapfile -t outs < <(wlr-randr 2>/dev/null | awk '/^[A-Za-z]/ {print $1}')
for o in "${outs[@]}"; do
    [ -n "$o" ] || continue
    case "$act" in
        off) mmsg dispatch sleep_monitor "$o"  >/dev/null 2>&1 ;;
        on)  mmsg dispatch wakeup_monitor "$o" >/dev/null 2>&1 ;;
    esac
done
