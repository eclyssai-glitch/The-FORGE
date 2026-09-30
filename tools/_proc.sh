#!/usr/bin/env bash
# Process supervision for the automation scripts (smoke_test.sh, capture_evidence.sh).
# Source it; do not execute it.
#
# The game runs in its own session (setsid), so godot, xvfb-run and Xvfb share one
# session id and can all be killed together — nothing is left orphaned, even when the
# engine hangs on exit (seen under Xvfb + lavapipe after the last frame).
#
#   proc_start LOG cmd...            start cmd in a new session; output -> LOG (and echoed live)
#   proc_supervise TIMEOUT GRACE FN  wait for it; FN (optional) = "work is done" predicate.
#                                    Once FN succeeds the process gets GRACE s to exit by itself.
#   After proc_supervise: PROC_STATUS (exit status, 124 on timeout), PROC_OUTCOME
#   (exited | forced | timeout). The whole session is always killed at the end.

# Audio driver flags for the game: on Linux without a sound card (/dev/snd, e.g. CI or a
# container) the Dummy driver is requested up front instead of letting ALSA/Pulse fail first
# (the AudioDirector and the mix run the same; nothing is heard). AUDIO_DRIVER=<name> forces one.
GODOT_AUDIO_FLAGS=()
if [ -n "${AUDIO_DRIVER:-}" ]; then
  GODOT_AUDIO_FLAGS=(--audio-driver "$AUDIO_DRIVER")
elif [ "$(uname -s)" = "Linux" ] && [ ! -e /dev/snd ]; then
  GODOT_AUDIO_FLAGS=(--audio-driver Dummy)
fi

PROC_PID=""
PROC_TAIL=""
PROC_STATUS=0
PROC_OUTCOME=""

proc__alive() {
  local pid="$1" stat
  kill -0 "$pid" 2>/dev/null || return 1
  stat="$(ps -o stat= -p "$pid" 2>/dev/null || true)"
  [ -n "$stat" ] && [ "${stat#Z}" = "$stat" ]
}

## Kills every process of the session started by proc_start (TERM, then KILL).
proc_kill_session() {
  [ -n "$PROC_PID" ] || return 0
  local sid="$PROC_PID" i
  pkill -TERM -s "$sid" 2>/dev/null || true
  for i in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -s "$sid" >/dev/null 2>&1 || break
    sleep 0.3
  done
  pkill -KILL -s "$sid" 2>/dev/null || true
  if [ -n "$PROC_TAIL" ]; then kill "$PROC_TAIL" 2>/dev/null || true; wait "$PROC_TAIL" 2>/dev/null || true; PROC_TAIL=""; fi
}

proc_start() {
  local log="$1"; shift
  : > "$log"
  # Background children of a non-interactive shell are never group leaders, so setsid
  # does not fork: $! is both the pid and the session id.
  setsid "$@" >"$log" 2>&1 < /dev/null &
  PROC_PID=$!
  # Callers add their own cleanup through PROC_ON_EXIT (a command string).
  trap 'proc_kill_session; eval "${PROC_ON_EXIT:-:}"' EXIT
  trap 'exit 130' INT TERM
  tail -n +1 -f --pid="$PROC_PID" "$log" 2>/dev/null &
  PROC_TAIL=$!
}

proc_supervise() {
  local timeout_s="$1" grace_s="$2" done_fn="${3:-}"
  local start now done_at=""
  start="$(date +%s)"
  PROC_OUTCOME="exited"
  while proc__alive "$PROC_PID"; do
    now="$(date +%s)"
    if [ $((now - start)) -ge "$timeout_s" ]; then PROC_OUTCOME="timeout"; break; fi
    if [ -n "$done_fn" ] && [ -z "$done_at" ] && "$done_fn"; then done_at="$now"; fi
    if [ -n "$done_at" ] && [ $((now - done_at)) -ge "$grace_s" ]; then PROC_OUTCOME="forced"; break; fi
    sleep 1
  done
  if [ "$PROC_OUTCOME" = "exited" ]; then
    set +e; wait "$PROC_PID"; PROC_STATUS=$?; set -e
  else
    proc_kill_session
    set +e; wait "$PROC_PID" 2>/dev/null; set -e
    PROC_STATUS=$([ "$PROC_OUTCOME" = "timeout" ] && echo 124 || echo 137)
  fi
  # Leftovers (e.g. Xvfb) are killed even after a clean exit.
  proc_kill_session
  sleep 0.2
}
