#!/usr/bin/env bash
# Route-driven menu for the mango light stack, modelled on omarchy-menu.
#
# Menus are data, not code: each route is a JSON file in ~/.config/mango/menus/.
# Adding an entry means editing JSON, never this script.
#
#   menu.sh              # the root menu
#   menu.sh hardware     # jump straight to a route
#   menu.sh --list       # every route and entry, for the cheat sheet
#
# Entry schema (all fields optional except label):
#   icon   nerd-font glyph shown in the left column
#   label  the text
#   state  shell snippet whose stdout is shown after a middle dot
#   menu   route to navigate to
#   run    script in ~/.config/mango/scripts/ (argv-split on spaces)
#   exec   raw shell command
#   keep   true to reopen this menu afterwards instead of exiting
set -uo pipefail

DIR="$HOME/.config/mango/menus"
SCRIPTS="$HOME/.config/mango/scripts"

route="${1:-root}"
case "$route" in
    --list|-l)
        for f in "$DIR"/*.json; do
            r="$(basename "$f" .json)"
            jq -r --arg r "$r" '.items[] | "\($r)\t\(.label)\t\(.menu // .run // .exec // "-")"' "$f"
        done
        exit 0
        ;;
esac

file="$DIR/$route.json"
[ -r "$file" ] || { notify-send -a mango "menu" "no such route: $route" 2>/dev/null; exit 1; }

title="$(jq -r '.title // "menu"' "$file")"
parent="$(jq -r '.parent // empty' "$file")"

# Build the visible lines. `state` is evaluated per entry, so a menu always
# shows live values rather than whatever was true when it was written.
render() {
    local n icon label state out
    n="$(jq '.items | length' "$file")"
    for ((i = 0; i < n; i++)); do
        icon="$(jq -r --argjson i "$i" '.items[$i].icon // " "' "$file")"
        label="$(jq -r --argjson i "$i" '.items[$i].label' "$file")"
        state="$(jq -r --argjson i "$i" '.items[$i].state // empty' "$file")"

        if [ -n "$state" ]; then
            out="$(cd "$SCRIPTS" && eval "$state" 2>/dev/null | head -1)"
            [ -n "$out" ] && label="$label  ·  $out"
        fi
        printf '%s  %s\n' "$icon" "$label"
    done
    [ -n "$parent" ] && printf '%s  %s\n' "$(printf '')" "Back  (esc)"
    return 0
}

lines="$(render)"
# fuzzel sizes to content; cap it so a long route does not fill the screen.
count="$(printf '%s\n' "$lines" | grep -c . || true)"
[ "$count" -gt 14 ] && count=14

# --no-exit-on-keyboard-focus-loss matters for the Escape handling below: without
# it, clicking another window also makes fuzzel exit non-zero, which would read
# as "go back" and walk the user up the tree for no reason.
choice="$(printf '%s\n' "$lines" |
    fuzzel --dmenu --no-exit-on-keyboard-focus-loss \
        --prompt "$title  " --lines "$count" --width 44)"
dismissed=$?

# Escape steps back up one level instead of tearing the whole menu down, so a
# wrong turn costs one keypress rather than a re-open. The root has no parent,
# so Escape closes there as usual.
if [ "$dismissed" -ne 0 ] || [ -z "$choice" ]; then
    [ -n "$parent" ] && exec "$0" "$parent"
    exit 0
fi

# Strip the icon column and any live-state suffix to recover the label.
label="${choice#*  }"
label="${label%%  ·  *}"

case "$label" in
    Back*)
        exec "$0" "$parent"
        ;;
esac

entry="$(jq -c --arg l "$label" '.items[] | select(.label == $l)' "$file" | head -1)"
[ -n "$entry" ] || exit 0

next="$(jq -r '.menu // empty' <<<"$entry")"
run="$(jq -r '.run // empty' <<<"$entry")"
raw="$(jq -r '.exec // empty' <<<"$entry")"
keep="$(jq -r '.keep // false' <<<"$entry")"

if [ -n "$next" ]; then
    exec "$0" "$next"
fi

if [ -n "$run" ]; then
    # Deliberately unquoted: `run` may carry arguments, e.g. "wallpaper.sh next".
    # shellcheck disable=SC2086
    "$SCRIPTS"/$run
elif [ -n "$raw" ]; then
    setsid sh -c "$raw" >/dev/null 2>&1 &
fi

[ "$keep" = "true" ] && exec "$0" "$route"
exit 0
