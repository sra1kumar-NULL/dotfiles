#!/usr/bin/env bash
# Screen recording with desktop audio (wf-recorder).
#
#   record.sh region     start recording a dragged region  (stops if recording)
#   record.sh output     start recording the focused monitor (stops if recording)
#   record.sh stop       stop the current recording
#   record.sh status     exit 0 while recording
#
# Contract with mangobar's recording indicator: while a recording runs, its
# wf-recorder pid is in $XDG_RUNTIME_DIR/mango-recording.pid; the file is
# removed as soon as recording ends (stopped here, or wf-recorder died).
#
# Audio is the default sink's monitor, i.e. what you hear. Set
# RECORD_AUDIO=0 to record silently.
set -uo pipefail

RUN="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
PIDF="${RECORD_PIDFILE:-$RUN/mango-recording.pid}"
DIR="${RECORD_DIR:-$HOME/Videos/Recordings}"
mode="${1:-region}"

running() {
    local pid
    pid="$(cat "$PIDF" 2>/dev/null)" || return 1
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

stop() {
    local pid
    pid="$(cat "$PIDF" 2>/dev/null)"
    [ -n "$pid" ] && kill -INT "$pid" 2>/dev/null
    # wf-recorder finalises the file on SIGINT; give it time to flush.
    for _ in $(seq 50); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done
    kill -0 "$pid" 2>/dev/null && kill -TERM "$pid" 2>/dev/null
    rm -f "$PIDF"
}

case "$mode" in
    status) running; exit $? ;;
    stop)
        running && stop || rm -f "$PIDF"
        exit 0
        ;;
    region|output) ;;
    *) echo "usage: record.sh [region|output|stop|status]" >&2; exit 2 ;;
esac

# Same key starts and stops (omarchy's ALT+PRINT behaviour).
if running; then
    stop
    exit 0
fi
rm -f "$PIDF"

command -v wf-recorder >/dev/null || { notify-send -a Recording "install wf-recorder" 2>/dev/null; exit 1; }

args=()
if [ "$mode" = region ]; then
    command -v slurp >/dev/null || { notify-send -a Recording "install slurp" 2>/dev/null; exit 1; }
    geom="$(slurp -d)" || exit 0
    args+=(-g "$geom")
else
    mon="$(mmsg get all-monitors 2>/dev/null | jq -r '.monitors[] | select(.active) | .name' | head -1)"
    [ -n "$mon" ] && args+=(-o "$mon")
fi

if [ "${RECORD_AUDIO:-1}" = 1 ] && command -v pactl >/dev/null; then
    sink="$(pactl get-default-sink 2>/dev/null)"
    [ -n "$sink" ] && args+=("--audio=$sink.monitor")
fi

# H.264 + AAC plays everywhere (chat apps, phones); veryfast keeps CPU low.
# wf-recorder's own default is VP9, which is several times heavier to encode.
args+=(-c libx264 -p preset=veryfast -p crf=23 -C aac)

mkdir -p "$DIR"
file="$DIR/rec-$(date +%Y%m%d-%H%M%S).mp4"

# The supervisor owns the pid file: it writes wf-recorder's pid, waits for it,
# then removes the file and announces the result -- so the file also goes away
# if wf-recorder exits on its own (output unplugged, encoder error).
# set -m gives the background job its own process group and, unlike a plain
# non-interactive `&`, does not make it ignore SIGINT.
setsid bash -c '
    set -m
    pidf=$1 file=$2; shift 2
    wf-recorder "$@" -f "$file" >/dev/null 2>&1 </dev/null &
    pid=$!
    echo "$pid" >"$pidf"
    wait "$pid"
    rm -f "$pidf"
    if [ -s "$file" ]; then
        notify-send -a Recording -i media-record "Recording saved" "${file/#$HOME/\~}"
    else
        rm -f "$file"
        notify-send -a Recording -u critical "Recording failed" "wf-recorder exited without writing"
    fi
' _ "$PIDF" "$file" "${args[@]}" >/dev/null 2>&1 &

# Wait briefly for the pid file so a caller (or the bar) sees the state at once.
for _ in $(seq 20); do [ -s "$PIDF" ] && break; sleep 0.05; done
notify-send -a Recording -i media-record "Recording started" \
    "$mode$([ "${#args[@]}" -gt 0 ] && printf '%s' "${args[*]}" | grep -q audio && echo ' + desktop audio')  ·  same key stops" 2>/dev/null
exit 0
