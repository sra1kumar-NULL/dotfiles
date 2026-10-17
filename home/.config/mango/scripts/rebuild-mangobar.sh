#!/usr/bin/env bash
# Build and install mangobar from the riced checkout at ~/.local/src/mangobar.
#
# Colours are NOT compiled in any more. The bar reads ~/.config/mango/mangobar.css
# at startup and re-reads it on SIGUSR1 (`pkill -USR1 -x mangobar`). That file
# holds `@define-color` lines for: bg fg accent muted urgent occupied surface
# border. A theme change therefore needs no cargo build at all.
#
#   src/theme.rs     runtime CSS loader + structural stylesheet (uses @bg etc.)
#   src/palette.rs   hand-kept FALLBACK colours (everforest), used for any name
#                    missing from mangobar.css or when the file does not exist
#   src/settings.rs  hand-riced: height, font, padding, tag size
#   src/main.rs      hand-riced: top anchor, indicators, tag CSS classes
#   src/*.rs.orig    pristine upstream copies, for diffing after an update
#
#   rebuild-mangobar.sh                      # always rebuild + restart bars
#   rebuild-mangobar.sh --if-palette-changed # kept for old callers: never
#                                            # builds; just tells running bars
#                                            # to reload mangobar.css
set -uo pipefail

SRC="$HOME/.local/src/mangobar"
REPO="https://github.com/Gur0v/mangobar.git"
PALETTE="$HOME/.config/mango/palette.sh"
CSS="$HOME/.config/mango/mangobar.css"
BIN="$HOME/.local/bin/mangobar"

# Seed mangobar.css from palette.sh so the bar has a runtime theme before the
# theming scripts ever write one. Never overwrites an existing file.
seed_css() {
    [ -e "$CSS" ] && return 0
    [ -r "$PALETTE" ] || return 0
    # shellcheck source=/dev/null
    ( . "$PALETTE"
      rgb() { printf '%d, %d, %d' $((16#${1:1:2})) $((16#${1:3:2})) $((16#${1:5:2})); }
      cat > "$CSS" <<CSS
/* mangobar runtime colours — reloaded on SIGUSR1 (pkill -USR1 -x mangobar).
   Seeded from palette.sh by rebuild-mangobar.sh; theme scripts may overwrite. */
@define-color bg ${SURFACE};
@define-color fg ${ON_SURFACE};
@define-color accent ${PRIMARY};
@define-color muted rgba($(rgb "$ON_SURFACE_VARIANT"), 0.55);
@define-color urgent ${ERROR};
@define-color occupied ${SURFACE_CONTAINER};
@define-color surface ${SURFACE_CONTAINER};
@define-color border ${OUTLINE_VARIANT};
CSS
    ) && echo "seeded $CSS"
}

seed_css

if [ "${1:-}" = "--if-palette-changed" ] && [ -x "$BIN" ]; then
    pkill -USR1 -x mangobar 2>/dev/null
    exit 0
fi

command -v cargo >/dev/null || { echo "cargo not installed" >&2; exit 1; }

if [ ! -d "$SRC/.git" ]; then
    mkdir -p "$(dirname "$SRC")"
    git clone --depth 1 "$REPO" "$SRC" || { echo "clone failed" >&2; exit 1; }
fi

cd "$SRC" || exit 1

[ -f src/theme.rs ] || {
    echo "warning: $SRC has no src/theme.rs — looks like a fresh upstream clone;" >&2
    echo "         this build will be stock upstream with no runtime theming." >&2
}

cargo build --release || { echo "build failed" >&2; exit 1; }

mkdir -p "$(dirname "$BIN")"
install -m 0755 target/release/mangobar "$BIN"
echo "installed $BIN"

# Restart running bars so a new binary takes effect. bar.sh, not a bare
# relaunch: there is one instance per monitor and each needs its --output.
if pgrep -x mangobar >/dev/null; then
    "$HOME/.config/mango/scripts/bar.sh" restart
fi
