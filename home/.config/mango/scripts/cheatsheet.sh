#!/usr/bin/env bash
# Keybind cheat sheet generated from binds.conf.
set -uo pipefail
CONF="$HOME/.config/mango/conf/binds.conf"
awk -F',' '
    /^#/ { next }
    /^(bind|bindl|bindr|bindc|binds)=/ {
        split($0, a, "=");
        mods = $1; sub(/^[a-z]+=/, "", mods);
        key = $2;
        action = $3;
        arg = "";
        for (i = 4; i <= NF; i++) arg = arg (i > 4 ? "," : "") $i;
        printf "%-28s  %s %s\n", mods "+" key, action, arg;
    }
' "$CONF" | sed 's/  *$//' | fuzzel --dmenu --prompt "keys  " --lines 20 --width 84 >/dev/null
