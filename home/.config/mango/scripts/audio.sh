#!/usr/bin/env bash
# Audio device switching over wpctl.
#
#   audio.sh sink     pick an output
#   audio.sh source   pick an input
#   audio.sh mute     toggle output mute
set -uo pipefail

action="${1:-sink}"

case "$action" in
    mute)
        wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
        exec "$HOME/.config/mango/scripts/osd.sh" volume
        ;;
    sink)   section="Sinks:";   target="@DEFAULT_AUDIO_SINK@";   label="Output" ;;
    source) section="Sources:"; target="@DEFAULT_AUDIO_SOURCE@"; label="Input" ;;
    *) echo "usage: audio.sh [sink|source|mute]" >&2; exit 2 ;;
esac

# `wpctl status` prints a tree. Two things make this fiddly: the box-drawing
# characters mean lines cannot be anchored on indentation, and "Sinks:"/"Sources:"
# appear under BOTH the Audio and the Video section — so this stops at the first
# heading after the one it wants rather than letting the Video block back in.
# The current default device is the one marked with an asterisk.
devices() {
    wpctl status 2>/dev/null | awk -v want="$section" '
        !grab && index($0, want) { grab = 1; next }
        grab && /(Devices|Sinks|Sources|Filters|Streams):/ { exit }
        grab && match($0, /[0-9]+\. /) {
            star = (index($0, "*") > 0) ? "*" : " ";
            rest = substr($0, RSTART);
            id = rest; sub(/\..*/, "", id);
            name = rest; sub(/^[0-9]+\. */, "", name); sub(/ *\[vol:.*$/, "", name);
            gsub(/[ \t]+$/, "", name);
            if (name != "") printf "%s %s\t%s\n", star, id, name;
        }'
}

list="$(devices)"
[ -n "$list" ] || { notify-send -a Audio "No $label devices found" 2>/dev/null; exit 1; }

choice="$(cut -f2- <<<"$list" | fuzzel --dmenu --prompt "$(tr 'A-Z' 'a-z' <<<"$label")  " --lines 8 --width 56)"
[ -n "$choice" ] || exit 0

id="$(awk -F'\t' -v c="$choice" '$2 == c { print $1 }' <<<"$list" | tr -dc '0-9')"
[ -n "$id" ] || exit 0

wpctl set-default "$id"
notify-send -a Audio "$label" "$choice" 2>/dev/null
