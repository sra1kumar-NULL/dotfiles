#!/usr/bin/env bash
# Run a terminal program in a floating, centred kitty window (omarchy's "TUI as
# app"). The window class is tui-float, matched by a window_rule in rules.conf.
#
#   tui.sh <program> [args...]        e.g. tui.sh bluetui, tui.sh btop
#   tui.sh --hold <program> [args...] keep the window open after it exits
#
# mango's spawn does not run a login shell, so ~/.cargo/bin and ~/.local/bin
# (where bluetui/wiremix live) are added to PATH here.
set -uo pipefail
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

hold=()
if [ "${1:-}" = "--hold" ]; then
    hold=(--hold)
    shift
fi
[ $# -gt 0 ] || { echo "usage: tui.sh [--hold] <program> [args...]" >&2; exit 2; }

if ! command -v "$1" >/dev/null 2>&1; then
    notify-send -a mango "$1 not found" "install $1 to use this" 2>/dev/null
    exit 1
fi

exec setsid kitty --class tui-float --title "$(basename "$1")" "${hold[@]}" -e "$@" >/dev/null 2>&1
