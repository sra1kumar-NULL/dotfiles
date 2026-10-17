#!/usr/bin/env bash
# Light/dark toggle.
#   - "wallpaper" theme: flips matugen between dark and light and re-renders.
#   - curated theme with a counterpart (OPPOSITE= in its colors.sh, e.g.
#     catppuccin <-> catppuccin-latte, rose-pine <-> rose-pine-dawn): switches to it.
#   - otherwise: says there is no light/dark variant.
set -uo pipefail
MANGO="$HOME/.config/mango"
STATE="$HOME/.local/state/mango-thememode"
theme="$(cat "$MANGO/current-theme" 2>/dev/null)"
[ -n "$theme" ] || theme=everforest

if [ "$theme" = wallpaper ]; then
    cur="$(cat "$STATE" 2>/dev/null || echo dark)"
    new=$([ "$cur" = dark ] && echo light || echo dark)
    mkdir -p "$(dirname "$STATE")"; printf '%s' "$new" > "$STATE"
    exec "$MANGO/scripts/theme-set.sh" wallpaper
fi

OPPOSITE="$(sed -n "s/^OPPOSITE='\(.*\)'$/\1/p" "$MANGO/themes/$theme/colors.sh" 2>/dev/null)"
if [ -n "$OPPOSITE" ] && [ -d "$MANGO/themes/$OPPOSITE" ]; then
    exec "$MANGO/scripts/theme-set.sh" "$OPPOSITE" --keep-wallpaper
fi
notify-send -a Theme "Theme" "$theme has no light/dark variant" 2>/dev/null || true
echo "theme: $theme has no light/dark variant" >&2
exit 1
