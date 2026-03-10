#!/usr/bin/env bash
set -euo pipefail

if [ -z "${DISPLAY:-}" ]; then
  export DISPLAY=:99
fi

# Some tooling (Chromium, crashpad, etc.) expects a writable XDG runtime dir.
# In this image the root FS may be read-only, so ensure it lives under /tmp.
if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
  export XDG_RUNTIME_DIR=/tmp/xdg-runtime
fi
if [ ! -d "$XDG_RUNTIME_DIR" ]; then
  if ! mkdir -p "$XDG_RUNTIME_DIR"; then
    echo "warning: failed to create XDG_RUNTIME_DIR at $XDG_RUNTIME_DIR" >&2
  fi
fi
if [ -d "$XDG_RUNTIME_DIR" ]; then
  if ! chmod 700 "$XDG_RUNTIME_DIR"; then
    echo "warning: failed to chmod XDG_RUNTIME_DIR at $XDG_RUNTIME_DIR" >&2
  fi
fi

if [ -z "${HOME:-}" ] || [ ! -w "${HOME:-/nonexistent}" ]; then
  export HOME=/tmp/pulse-home
fi
if ! mkdir -p "$HOME"; then
  echo "warning: failed to create HOME at $HOME" >&2
fi

if [ -z "${XDG_CONFIG_HOME:-}" ]; then
  export XDG_CONFIG_HOME="$HOME/.config"
fi
if [ -z "${XDG_CACHE_HOME:-}" ]; then
  export XDG_CACHE_HOME="$HOME/.cache"
fi
if [ -z "${PULSE_COOKIE:-}" ]; then
  export PULSE_COOKIE="$XDG_RUNTIME_DIR/pulse/cookie"
fi
if [ -z "${PULSE_CLIENTCONFIG:-}" ]; then
  export PULSE_CLIENTCONFIG="$XDG_RUNTIME_DIR/pulse/client.conf"
fi

for dir in "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$(dirname "$PULSE_COOKIE")"; do
  if ! mkdir -p "$dir"; then
    echo "warning: failed to create directory $dir" >&2
  fi
done

wait_for_pactl() {
  local attempts="${1:-20}"
  local sleep_seconds="${2:-0.1}"
  local try
  for try in $(seq 1 "$attempts"); do
    if pactl info >/dev/null 2>&1; then
      return 0
    fi
    sleep "$sleep_seconds"
  done
  return 1
}

start_pulseaudio() {
  local pulse_socket="$1"
  local pulse_runtime_dir

  pulse_runtime_dir="$(dirname "$pulse_socket")"

  # If a previous daemon died uncleanly, clear the stale socket/pid pair before restarting.
  rm -f "$pulse_socket" "$pulse_runtime_dir/pid"

  pulseaudio \
    --daemonize=yes \
    --disallow-exit=yes \
    --exit-idle-time=-1 \
    --log-level=error \
    --log-target=stderr \
    --use-pid-file=no \
    >/tmp/pulseaudio.log 2>&1
}

find_monitor_source() {
  local sink_name="$1"
  pactl list short sources \
    | awk -v sink="${sink_name}.monitor" '$2 == sink {print $2; exit}'
}

if [ "${CODEX_DISABLE_PULSEAUDIO:-}" != "1" ]; then
  if command -v pulseaudio >/dev/null 2>&1 && command -v pactl >/dev/null 2>&1; then
    pulse_socket="${PULSE_SOCKET:-$XDG_RUNTIME_DIR/pulse/native}"
    pulse_sink_name="${PULSE_SINK_NAME:-auto_null}"
    pulse_runtime_dir="$(dirname "$pulse_socket")"

    if [ ! -d "$pulse_runtime_dir" ]; then
      if ! mkdir -p "$pulse_runtime_dir"; then
        echo "warning: failed to create PulseAudio runtime dir at $pulse_runtime_dir" >&2
      fi
    fi
    if [ -d "$pulse_runtime_dir" ]; then
      if ! chmod 700 "$pulse_runtime_dir"; then
        echo "warning: failed to chmod PulseAudio runtime dir at $pulse_runtime_dir" >&2
      fi
    fi

    export PULSE_SERVER="unix:$pulse_socket"

    if ! wait_for_pactl 1 0; then
      if ! start_pulseaudio "$pulse_socket"; then
        echo "warning: PulseAudio failed to start (see /tmp/pulseaudio.log)" >&2
      fi
    fi

    if ! wait_for_pactl "${PULSE_WAIT_ATTEMPTS:-30}" "${PULSE_WAIT_INTERVAL_SECONDS:-0.1}"; then
      echo "warning: PulseAudio did not become reachable at $PULSE_SERVER" >&2
    else
      if ! pactl list short sinks | awk '{print $2}' | rg -x -q "$pulse_sink_name"; then
        if ! pactl load-module module-null-sink "sink_name=$pulse_sink_name" "sink_properties=device.description=$pulse_sink_name" >/dev/null; then
          echo "warning: failed to load PulseAudio null sink $pulse_sink_name" >&2
        fi
      fi

      if ! pactl set-default-sink "$pulse_sink_name" >/dev/null 2>&1; then
        echo "warning: failed to set default PulseAudio sink $pulse_sink_name" >&2
      fi

      if [ -z "${HARNESS_CAPTURE_AUDIO_FORMAT:-}" ]; then
        export HARNESS_CAPTURE_AUDIO_FORMAT=pulse
      fi

      if [ -z "${HARNESS_CAPTURE_AUDIO_INPUT:-}" ]; then
        pulse_monitor_source=""
        for _ in $(seq 1 "${PULSE_WAIT_ATTEMPTS:-30}"); do
          pulse_monitor_source="$(find_monitor_source "$pulse_sink_name")"
          if [ -n "$pulse_monitor_source" ]; then
            break
          fi
          sleep "${PULSE_WAIT_INTERVAL_SECONDS:-0.1}"
        done
        if [ -n "$pulse_monitor_source" ]; then
          export HARNESS_CAPTURE_AUDIO_INPUT="$pulse_monitor_source"
        else
          echo "warning: no PulseAudio monitor source found for $pulse_sink_name" >&2
        fi
      fi
    fi
  else
    echo "warning: pulseaudio/pactl not found; audio capture is disabled" >&2
  fi
fi

if [ "${CODEX_DISABLE_XVFB:-}" != "1" ]; then
  if command -v Xvfb >/dev/null 2>&1; then
    Xvfb "$DISPLAY" -screen 0 "${XVFB_SCREEN:-1920x1080x24}" -nolisten tcp -ac >/tmp/xvfb.log 2>&1 &
    xvfb_pid=$!
    sleep 0.2
    if ! kill -0 "$xvfb_pid" 2>/dev/null; then
      echo "warning: Xvfb failed to start on $DISPLAY (see /tmp/xvfb.log)" >&2
    fi
  else
    echo "warning: Xvfb not found; DISPLAY is set but no X server is running" >&2
  fi
fi

exec codex "$@"
