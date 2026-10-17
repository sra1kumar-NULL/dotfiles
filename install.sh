#!/usr/bin/env bash
# Rebuild this desktop (Fedora 44 + mangowm light stack) on a fresh install.
#
#   git clone git@github.com:sra1kumar-NULL/dotfiles.git ~/dotfiles
#   cd ~/dotfiles && ./install.sh            # everything
#   ./install.sh dotfiles mangobar           # only some steps
#
# Steps (run in this order when none are given):
#   repos      RPM Fusion, Terra, Helium COPR, Chrome, VS Code, Sublime, Proton VPN, Claude   [sudo]
#   packages   dnf install packages/dnf.txt (+ NVIDIA driver if an NVIDIA GPU is present)   [sudo]
#   flatpak    Flathub + packages/flatpak.txt
#   assets     JetBrainsMono Nerd Font, Tela-circle icons, Bibata + WhiteSur cursors
#   dotfiles   copy home/ into $HOME (anything it replaces is backed up first)
#   mangobar   build the patched bar from mangobar/ into ~/.local/bin/mangobar
#   services   greetd login (tuigreet -> mango) + user units                                 [sudo]
#   vscode     install packages/vscode-extensions.txt
#
# Run as your normal user, NOT with sudo — it asks for sudo itself when needed.
set -euo pipefail

DOTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORIG_HOME="/home/sasuke"          # configs were captured with this path baked in
BACKUP="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

say()  { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m  ! %s\033[0m\n' "$*" >&2; }

[ "$(id -u)" -ne 0 ] || { echo "Run as your user, not root." >&2; exit 1; }

# ── repos ────────────────────────────────────────────────────────────────────
step_repos() {
    say "Enabling repositories"
    local rel; rel="$(rpm -E %fedora)"
    sudo dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${rel}.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${rel}.noarch.rpm" \
        dnf-plugins-core
    sudo dnf install -y --nogpgcheck --repofrompath "terra,https://repos.fyralabs.com/terra${rel}" terra-release
    sudo dnf copr enable -y imput/helium
    sudo install -m 0644 "$DOTS"/system/etc/yum.repos.d/*.repo /etc/yum.repos.d/
    sudo dnf makecache
}

# ── packages ─────────────────────────────────────────────────────────────────
step_packages() {
    say "Installing packages ($(grep -c . "$DOTS/packages/dnf.txt") from packages/dnf.txt)"
    local pkgs; mapfile -t pkgs < <(grep -vE '^\s*(#|$)' "$DOTS/packages/dnf.txt")
    if ! lspci 2>/dev/null | grep -qi nvidia; then
        warn "no NVIDIA GPU detected — skipping the NVIDIA driver packages"
        mapfile -t pkgs < <(printf '%s\n' "${pkgs[@]}" | grep -vE '^(akmod-nvidia|xorg-x11-drv-nvidia|libva-nvidia)')
    fi
    sudo dnf install -y --skip-unavailable "${pkgs[@]}"
}

# ── flatpak ──────────────────────────────────────────────────────────────────
step_flatpak() {
    say "Installing Flatpaks"
    flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    grep -vE '^\s*(#|$)' "$DOTS/packages/flatpak.txt" | xargs -r flatpak install --user -y --noninteractive flathub
}

# ── assets (fonts / icons / cursors — too big for the repo, fetched upstream) ─
step_assets() {
    say "Fetching fonts, icons and cursors"
    local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN

    local fonts="$HOME/.local/share/fonts/JetBrainsMono"
    if [ ! -d "$fonts" ]; then
        mkdir -p "$fonts"
        curl -fL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz | tar -xJ -C "$fonts"
        fc-cache -f >/dev/null
    fi

    if [ ! -d "$HOME/.icons/Tela-circle" ]; then
        git clone --depth 1 https://github.com/vinceliuice/Tela-circle-icon-theme "$tmp/tela"
        "$tmp/tela/install.sh" -d "$HOME/.icons"
    fi

    local icons="$HOME/.local/share/icons"; mkdir -p "$icons"
    if [ ! -d "$icons/Bibata-Modern-Ice" ]; then
        curl -fL https://github.com/ful1e5/Bibata_Cursor/releases/latest/download/Bibata-Modern-Ice.tar.xz | tar -xJ -C "$icons"
    fi
    if [ ! -d "$icons/WhiteSur-cursors" ]; then
        git clone --depth 1 https://github.com/vinceliuice/WhiteSur-cursors "$tmp/ws"
        mkdir -p "$icons/WhiteSur-cursors"; cp -r "$tmp/ws/dist/." "$icons/WhiteSur-cursors/"
    fi
}

# ── dotfiles ─────────────────────────────────────────────────────────────────
step_dotfiles() {
    say "Copying dotfiles into $HOME (backups -> $BACKUP)"
    local stage; stage="$(mktemp -d)"
    cp -a "$DOTS/home/." "$stage/"

    # mango does not expand ~ or $HOME, so configs carry absolute paths.
    if [ "$HOME" != "$ORIG_HOME" ]; then
        warn "rewriting $ORIG_HOME -> $HOME in configs"
        grep -rlI --null "$ORIG_HOME" "$stage" | xargs -0 -r sed -i "s|$ORIG_HOME|$HOME|g"
    fi

    rsync -a --backup --backup-dir="$BACKUP" "$stage/" "$HOME/"
    rm -rf "$stage"
    chmod +x "$HOME"/.config/mango/scripts/*.sh
    xdg-user-dirs-update 2>/dev/null || true
    mkdir -p "$HOME/Pictures/Screenshots"
}

# ── mangobar ─────────────────────────────────────────────────────────────────
step_mangobar() {
    say "Building mangobar (patched for mango 0.18 + tray)"
    local src="$HOME/.local/src/mangobar"
    mkdir -p "$src"
    rsync -a --delete --exclude target --exclude .git "$DOTS/mangobar/" "$src/"
    # rebuild-mangobar.sh treats a dir without .git as "clone upstream" — make it a checkout.
    [ -d "$src/.git" ] || git -C "$src" init -q
    (cd "$src" && cargo build --release)
    install -Dm0755 "$src/target/release/mangobar" "$HOME/.local/bin/mangobar"
}

# ── services ─────────────────────────────────────────────────────────────────
step_services() {
    say "Login manager + services"
    sudo install -Dm0644 "$DOTS/system/etc/greetd/config.toml" /etc/greetd/config.toml
    for dm in gdm sddm lightdm; do
        systemctl is-enabled "$dm" >/dev/null 2>&1 && sudo systemctl disable "$dm" || true
    done
    sudo systemctl enable greetd
    sudo systemctl set-default graphical.target

    systemctl --user daemon-reload
    systemctl --user enable battery-warn.timer xdg-desktop-portal.service || true
}

# ── vscode ───────────────────────────────────────────────────────────────────
step_vscode() {
    command -v code >/dev/null || { warn "VS Code not installed, skipping"; return; }
    say "VS Code extensions"
    grep -vE '^\s*(#|$)' "$DOTS/packages/vscode-extensions.txt" | xargs -r -n1 code --install-extension
}

ALL=(repos packages flatpak assets dotfiles mangobar services vscode)
STEPS=("$@"); [ ${#STEPS[@]} -gt 0 ] || STEPS=("${ALL[@]}")
for s in "${STEPS[@]}"; do
    declare -F "step_$s" >/dev/null || { echo "unknown step: $s (valid: ${ALL[*]})" >&2; exit 1; }
    "step_$s"
done

say "Done. Reboot, log in through tuigreet, and you're home."
echo "   Validate mango config any time:  mango -c ~/.config/mango/config.conf -p"
