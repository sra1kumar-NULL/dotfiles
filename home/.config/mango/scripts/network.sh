#!/usr/bin/env bash
# Wi-Fi / network menu for the mango light stack.
#
# fuzzel rather than a tray icon: the light stack has no tray, and fuzzel is
# already themed from the same matugen palette as everything else.
set -uo pipefail

menu() { fuzzel --dmenu --prompt "$1  " --lines "${2:-12}" --width "${3:-48}"; }
note() { notify-send -a "Network" "$1" "${2:-}" 2>/dev/null || true; }

radio="$(nmcli -t radio wifi 2>/dev/null)"
active="$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null |
    awk -F: '$2 != "lo" && $2 != "" { print $1; exit }')"

# The SSID actually associated right now. The scan list's own ACTIVE column goes
# stale against the cache (it reported "no" for a live connection), so the
# connected row is marked by matching this instead.
wifi_now="$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null |
    awk -F: '$2 == "802-11-wireless" { print $1; exit }')"

# One scan line per SSID, strongest first. Neither IN-USE nor ACTIVE can be
# trusted here: in terse mode nmcli leaves IN-USE blank on every row, and ACTIVE
# reported "no" for a network that was demonstrably connected, so the connected
# row is matched against the live connection name instead.
networks() {
    # Glyphs are built in bash and passed in as awk variables rather than
    # written inline: it keeps nerd-font codepoints out of a string that sed and
    # awk both want to escape-process differently.
    local lock connected
    lock="$(printf '\uf023')"
    connected="$(printf '\uf058')"

    nmcli -t -f SSID,SIGNAL,SECURITY device wifi list --rescan no 2>/dev/null |
        awk -F: -v lock="$lock" -v connected="$connected" -v current="$wifi_now" '
            $1 == "" { next }
            seen[$1]++ { next }
            {
                sig = $2 + 0;
                bars = sig >= 75 ? "▆▆▆▆" : \
                       sig >= 50 ? "▆▆▆░" : \
                       sig >= 25 ? "▆▆░░" : "▆░░░";
                secure = ($3 == "" || $3 == "--") ? " " : lock;
                mark = ($1 == current && current != "") ? connected : " ";
                printf "%s %s %s  %s\n", mark, bars, secure, $1;
            }'
}

ssid_of() { printf '%s' "${1#*  }"; }

connect() {
    local ssid="$1" pw
    note "Connecting" "$ssid"

    if nmcli device wifi connect "$ssid" >/dev/null 2>&1; then
        note "Connected" "$ssid"
        return 0
    fi

    # No saved secret: ask once, then retry. --password keeps it off the screen.
    pw="$(printf '' | fuzzel --dmenu --password --prompt "password for $ssid  " --lines 0 --width 40)"
    [ -n "$pw" ] || { note "Cancelled" "$ssid"; return 1; }

    if nmcli device wifi connect "$ssid" password "$pw" >/dev/null 2>&1; then
        note "Connected" "$ssid"
    else
        note "Failed" "Could not connect to $ssid"
        return 1
    fi
}

main() {
    local header choice ssid
    if [ "$radio" = "enabled" ]; then
        header=$'  Turn Wi-Fi off\n  Rescan\n  Disconnect\n  Advanced settings'
    else
        header=$'  Turn Wi-Fi on\n  Advanced settings'
    fi

    choice="$(
        {
            printf '%s\n' "$header"
            [ "$radio" = "enabled" ] && networks
        } | menu "net${active:+ · $active}"
    )"
    [ -n "$choice" ] || exit 0

    case "$choice" in
        *"Turn Wi-Fi off")    nmcli radio wifi off; note "Wi-Fi" "Off" ;;
        *"Turn Wi-Fi on")     nmcli radio wifi on; note "Wi-Fi" "On" ;;
        *"Rescan")            nmcli device wifi rescan >/dev/null 2>&1; sleep 2; exec "$0" ;;
        *"Disconnect")
            [ -n "$active" ] && nmcli connection down "$active" >/dev/null 2>&1
            note "Disconnected" "$active"
            ;;
        *"Advanced settings") setsid nm-connection-editor >/dev/null 2>&1 & ;;
        *)
            ssid="$(ssid_of "$choice")"
            [ -n "$ssid" ] && connect "$ssid"
            ;;
    esac
}

main
