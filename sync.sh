#!/usr/bin/env bash
# Pull the LIVE config from this machine back into the repo, then show what changed.
#   ./sync.sh            # copy + git status
#   ./sync.sh --commit   # copy + commit + push
set -euo pipefail
DOTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
H="$DOTS/home"
EX=(--exclude='*.pre-*' --exclude='*.dms-backup' --exclude='*.bak' --exclude='*.orig' --exclude='*.log'
    --exclude='dms/translated' --exclude='dms/windowrules.conf' --exclude='dms/layout.conf')

cd "$HOME"
cp -a .bashrc .bashrc_custom .bash_profile .gitconfig .gtkrc-2.0 "$H/"
for p in mango matugen kitty fuzzel mako gtklock swaylock btop cava fastfetch yazi mpv environment.d \
         fontconfig Thunar lxqt bashrc gtk-3.0 gtk-4.0 starship.toml mimeapps.list gtkrc gtkrc-2.0 \
         xdg-terminals.list chrome-flags.conf code-flags.conf user-dirs.dirs user-dirs.locale; do
    [ -e ".config/$p" ] && rsync -a --delete "${EX[@]}" ".config/$p" "$H/.config/"
done
cp -a .config/systemd/user/battery-warn.{service,timer} .config/systemd/user/xdg-desktop-portal.service "$H/.config/systemd/user/"
cp -a .config/Code/User/settings.json "$H/.config/Code/User/"
[ -f .config/Code/User/keybindings.json ] && cp -a .config/Code/User/keybindings.json "$H/.config/Code/User/"
rsync -a --delete .config/Code/User/snippets "$H/.config/Code/User/"
rsync -a --delete .config/sublime-text/Packages/User "$H/.config/sublime-text/Packages/"
rsync -a --delete Pictures/Wallpapers "$H/Pictures/"
cp -a .local/state/mango-wallpaper .local/state/mango-thememode "$H/.local/state/" 2>/dev/null || true
rsync -a --delete --exclude target --exclude .git --exclude '*.orig' --exclude PREVIEW.png \
    .local/src/mangobar/ "$DOTS/mangobar/"
cp /etc/greetd/config.toml "$DOTS/system/etc/greetd/"
command -v code >/dev/null && code --list-extensions > "$DOTS/packages/vscode-extensions.txt"
flatpak list --app --columns=application > "$DOTS/packages/flatpak.txt"

# Absolute symlinks would point at this machine; keep them relative to $HOME.
ln -sfn ../../Pictures/Wallpapers/"$(basename "$(readlink -f .config/mango/lockscreen)")" "$H/.config/mango/lockscreen"
for f in assets gtk-dark.css gtk.css; do
    ln -sfn "../../.themes/Orchis-Dark-Compact/gtk-4.0/$f" "$H/.config/gtk-4.0/$f"
done

cd "$DOTS"
git status --short
if [ "${1:-}" = "--commit" ] && [ -n "$(git status --porcelain)" ]; then
    git add -A && git commit -m "sync: $(date '+%F %H:%M')" && git push
fi
