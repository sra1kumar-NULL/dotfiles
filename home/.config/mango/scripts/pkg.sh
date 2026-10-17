#!/usr/bin/env bash
# Package install / remove / system update in a floating terminal
# (omarchy-pkg-install / -remove / omarchy-update equivalents for dnf).
#
#   pkg.sh install   fzf over every available package, then sudo dnf install
#   pkg.sh remove    fzf over installed packages, then sudo dnf remove
#   pkg.sh update    sudo dnf upgrade --refresh, then flatpak update
#
# Launched from a keybind or menu it re-opens itself in a tui-float kitty, so
# the sudo password is typed into a real terminal (never a GUI prompt).
set -uo pipefail
SELF="$(readlink -f "$0")"
action="${1:-}"

case "$action" in
    install|remove|update) ;;
    *) echo "usage: pkg.sh install|remove|update" >&2; exit 2 ;;
esac

if [ ! -t 0 ] || [ ! -t 1 ]; then
    exec "$(dirname "$SELF")/tui.sh" "$SELF" "$action"
fi

pause() { printf '\n\033[2mpress enter to close\033[0m '; read -r _; }

need() {
    command -v "$1" >/dev/null || { echo "install $1 first"; pause; exit 1; }
}

case "$action" in
    install)
        need fzf
        echo "loading package list..."
        # -C uses the metadata cache (instant); fall back to a refresh if empty.
        list="$(dnf repoquery -C --available --qf '%{name}\n' 2>/dev/null | sort -u)"
        [ -n "$list" ] || list="$(dnf repoquery --available --qf '%{name}\n' 2>/dev/null | sort -u)"
        mapfile -t picks < <(printf '%s\n' "$list" |
            fzf --multi --height 100% --layout=reverse \
                --prompt 'install> ' --header 'TAB select several · ENTER install · ESC cancel' \
                --preview 'dnf info -C --available {1} 2>/dev/null | sed -n "/^Name/,\$p"' \
                --preview-window 'right,60%,wrap')
        [ ${#picks[@]} -gt 0 ] || exit 0
        sudo dnf install "${picks[@]}"
        pause
        ;;
    remove)
        need fzf
        mapfile -t picks < <(dnf repoquery -C --installed --qf '%{name}\n' 2>/dev/null | sort -u |
            fzf --multi --height 100% --layout=reverse \
                --prompt 'remove> ' --header 'TAB select several · ENTER remove · ESC cancel' \
                --preview 'dnf info -C --installed {1} 2>/dev/null | sed -n "/^Name/,\$p"' \
                --preview-window 'right,60%,wrap')
        [ ${#picks[@]} -gt 0 ] || exit 0
        # dnf shows the full transaction (including dependants) and asks first.
        sudo dnf remove "${picks[@]}"
        pause
        ;;
    update)
        printf '\033[1m== dnf ==\033[0m\n'
        sudo dnf upgrade --refresh
        if command -v flatpak >/dev/null; then
            printf '\n\033[1m== flatpak ==\033[0m\n'
            flatpak update
        fi
        pause
        ;;
esac
