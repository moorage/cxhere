#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/cx-runtime-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

child_pid_file="$tmpdir/child.pid"

set +e
cx_run_with_timeout 1 perl -e '
  use strict;
  use warnings;

  my $pid_file = shift @ARGV;
  $SIG{TERM} = sub {};

  my $pid = fork();
  die "fork failed: $!" unless defined $pid;

  if ($pid == 0) {
    $SIG{TERM} = sub {};
    open my $fh, ">", $pid_file or die "open: $!";
    print {$fh} "$$\n";
    close $fh;
    sleep 30;
    exit 0;
  }

  sleep 30;
' "$child_pid_file"
status=$?
set -e

if [ "$status" -ne 124 ]; then
  echo "expected cx_run_with_timeout to return 124, got $status" >&2
  exit 1
fi

if [ ! -s "$child_pid_file" ]; then
  echo "expected child pid file to be written" >&2
  exit 1
fi

child_pid="$(tr -d '\n' < "$child_pid_file")"
if kill -0 "$child_pid" 2>/dev/null; then
  echo "expected timed out process group to be terminated; child pid $child_pid is still running" >&2
  exit 1
fi

echo "cx_run_with_timeout kills timed out process groups"

launchctl_calls_file="$tmpdir/launchctl.calls"
container_list_file="$tmpdir/container.list"
printf 'stuck-id\n' > "$container_list_file"

launchctl() {
  printf '%s\n' "$*" >> "$launchctl_calls_file"
  : > "$container_list_file"
}

container() {
  if [ "${1:-}" = "list" ] && [ "${2:-}" = "--quiet" ]; then
    cat "$container_list_file"
    return 0
  fi
  echo "unexpected container invocation: $*" >&2
  return 1
}

if ! cx_force_kill_container_runtime_job "stuck-id"; then
  echo "expected launchctl fallback to report success" >&2
  exit 1
fi

expected_service_ref="kill SIGKILL gui/$(id -u)/com.apple.container.container-runtime-linux.stuck-id"
if ! rg -F -x "$expected_service_ref" "$launchctl_calls_file" >/dev/null; then
  echo "expected launchctl fallback to target $expected_service_ref" >&2
  exit 1
fi

echo "cx_force_kill_container_runtime_job kills the launchd service for a stuck container"
