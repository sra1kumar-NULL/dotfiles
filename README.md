# dotfiles — Fedora 44 · mangowm light stack

Minimal, omarchy-inspired Wayland desktop. One compositor, no heavy shell.

| Piece | Tool |
|---|---|
| Compositor | **mangowm** 0.18 (Terra) — `~/.config/mango` |
| Bar | **mangobar**, patched for mango 0.18 + system tray (`mangobar/`) |
| Login | greetd + tuigreet |
| Launcher / menus | fuzzel + JSON menus (`mango/menus/*.json`, `scripts/menu.sh`) |
| Notifications | mako · OSD: wob · Lock: gtklock (swaylock fallback) · Idle: swayidle |
| Theming | `scripts/theme-set.sh <name>` renders every app from one palette (everforest, tokyo-night, gruvbox, catppuccin, kanagawa, rose-pine, nord, or `wallpaper` via matugen) |
| Terminal / shell | kitty, bash + starship, fastfetch, eza, bat, fzf, zoxide |
| GTK | Orchis-Dark-Compact, Tela-circle icons, Bibata-Modern-Ice cursor |

## Fresh install (minutes)

1. Install Fedora 44 (Everything/minimal or Workstation), create user `sasuke`
   (any name works — paths are rewritten automatically).
2. Then:

```bash
sudo dnf install -y git
git clone https://github.com/sra1kumar-NULL/dotfiles.git ~/dotfiles
cd ~/dotfiles && ./install.sh
sudo reboot
```

Pick individual steps with `./install.sh <step>...`:
`repos packages flatpak assets dotfiles mangobar services vscode`.
Any existing file the `dotfiles` step overwrites is saved under `~/.dotfiles-backup/<timestamp>/`.

## Keeping the repo current

```bash
~/dotfiles/sync.sh            # copy live config into the repo, show the diff
~/dotfiles/sync.sh --commit   # ...and commit + push
```

## Layout

```
home/            mirrors $HOME (.config/*, .bashrc*, .themes, Pictures/Wallpapers)
mangobar/        patched mangobar source (built by install.sh)
packages/        dnf.txt, flatpak.txt, vscode-extensions.txt
system/etc/      greetd config + third-party .repo files
install.sh       bootstrap        sync.sh    live -> repo
```

## Notes

- Validate mango edits before relogging: `mango -c ~/.config/mango/config.conf -p`
  (it exits 0 even with errors — read the output). Hot reload: `SUPER+SHIFT+R`.
- Keybind cheat sheet: `SUPER+K`. Control centre: `SUPER+ALT+SPACE`.
- Monitor layout lives in `mango/conf/monitors.conf` (laptop eDP-1 + LG 4K on HDMI-A-1).
- Generated files (`~/.config/mako/config`, kitty `theme.conf`, fuzzel, gtklock…) are
  rewritten by `theme-set.sh` — edit the templates in that script, not the outputs.
- Not in the repo (fetched by `install.sh assets`): Nerd Fonts, icon and cursor themes.
  Google Sans Flex (GTK UI font) isn't packaged — install it manually or change
  `gtk-font-name` in `gtk-3.0/settings.ini`.
