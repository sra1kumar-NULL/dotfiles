#!/usr/bin/env bash
# cliphist history through fuzzel.
set -uo pipefail
cliphist list \
    | fuzzel --dmenu --prompt "clip  " --lines 14 --width 70 \
    | cliphist decode \
    | wl-copy
