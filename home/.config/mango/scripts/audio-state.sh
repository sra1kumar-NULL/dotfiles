#!/usr/bin/env bash
set -uo pipefail
out="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)" || { echo "--"; exit 0; }
case "$out" in *MUTED*) echo "muted"; exit 0 ;; esac
awk '{ printf "%d%%\n", $2 * 100 }' <<<"$out"
