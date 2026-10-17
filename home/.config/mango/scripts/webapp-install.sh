#!/usr/bin/env bash
# Install a web app (omarchy-webapp-install for mango + Chrome).
#
#   webapp-install.sh <name> <url> [icon-url]
#
# Writes ~/.local/share/applications/<slug>.desktop whose Exec goes through
# webapp-launch.sh, so launching an app that is already open focuses it instead
# of opening a second window. The icon is downloaded to
# ~/.local/share/applications/icons/<slug>.png; without an icon URL (or if the
# download fails) the site's favicon is used.
set -euo pipefail

APPS="$HOME/.local/share/applications"
ICONS="$APPS/icons"
LAUNCH="$HOME/.config/mango/scripts/webapp-launch.sh"

name="${1:-}" url="${2:-}" icon_url="${3:-}"
if [ -z "$name" ] || [ -z "$url" ]; then
    echo "usage: webapp-install.sh <name> <url> [icon-url]" >&2
    exit 2
fi
case "$name" in */*) echo "name cannot contain '/': $name" >&2; exit 1 ;; esac

# Schemeless input gets https://; anything that is not http(s) is refused,
# because --app= would happily run javascript:/file:/data: URLs.
[[ $url =~ ^[a-zA-Z][a-zA-Z0-9+.-]*: ]] || url="https://$url"
if [[ ! ${url,,} =~ ^https?:// ]] || [[ $url =~ [[:space:]] ]]; then
    echo "url must be http(s) with no spaces: $url" >&2
    exit 1
fi

slug="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^[:alnum:]]\+/-/g; s/^-//; s/-$//')"
[ -n "$slug" ] || { echo "name has no usable characters" >&2; exit 1; }
host="$(printf '%s' "$url" | sed -E 's#^[a-zA-Z]+://##; s#[/?#].*$##')"

mkdir -p "$ICONS"
icon="$ICONS/$slug.png"
fetch() {
    curl -fsSL --max-time 10 -o "$icon.tmp" "$1" 2>/dev/null &&
        [ -s "$icon.tmp" ] && file -b --mime-type "$icon.tmp" | grep -q '^image/' &&
        mv -f "$icon.tmp" "$icon"
}
if ! { [ -n "$icon_url" ] && fetch "$icon_url"; }; then
    fetch "https://www.google.com/s2/favicons?domain=$host&sz=256" || true
fi
rm -f "$icon.tmp"
[ -s "$icon" ] || icon="web-browser"

cat >"$APPS/$slug.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$name
Comment=Web app: $url
Exec=$LAUNCH $slug
Icon=$icon
Terminal=false
Categories=Network;WebBrowser;
StartupNotify=true
X-WebApp-URL=$url
X-WebApp-Host=$host
EOF
chmod 644 "$APPS/$slug.desktop"
command -v update-desktop-database >/dev/null && update-desktop-database "$APPS" 2>/dev/null || true

echo "installed $name -> $APPS/$slug.desktop"
notify-send -a "Web apps" -i "$icon" "$name installed" "find it in the launcher (SUPER+SPACE)" 2>/dev/null || true
