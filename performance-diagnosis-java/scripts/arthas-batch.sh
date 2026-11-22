#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: arthas-batch.sh --java JAVA [--arthas-boot JAR] --pid PID --timeout SECONDS --commands 'dashboard -n 1;thread -n 10'

Runs only the documented L1 command allowlist. This wrapper does not execute trace/watch/profiler.
  Omit --arthas-boot to download/use the pinned local 4.3.5 cache automatically.
USAGE
}
fail() { printf 'Error: %s\n' "$1" >&2; exit 2; }
java= boot= pid= timeout_seconds= commands=
while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || { usage; exit 2; }
  option=$1 value=$2; shift 2
  case "$option" in
    --java) java=$value ;;
    --arthas-boot) boot=$value ;;
    --pid) pid=$value ;;
    --timeout) timeout_seconds=$value ;;
    --commands) commands=$value ;;
    *) fail "Unknown option: $option" ;;
  esac
done
if [ -z "$boot" ]; then
  script_dir=$(cd "$(dirname "$0")" && pwd)
  "$script_dir/prepare-arthas.sh"
  boot=${HOME:?HOME is not set}/.performance-diagnosis/arthas/versions/4.3.5/arthas-boot.jar
fi
[ -x "$java" ] || fail 'Java executable is missing or not executable.'
[ -r "$boot" ] || fail 'arthas-boot.jar is missing or unreadable.'
case "$pid" in ''|*[!0-9]*) fail 'PID must be numeric.' ;; esac
case "$timeout_seconds" in ''|*[!0-9]*) fail 'Timeout must be numeric.' ;; esac
[ "$timeout_seconds" -ge 1 ] && [ "$timeout_seconds" -le 30 ] || fail 'Timeout must be between 1 and 30 seconds.'
[ -n "$commands" ] || fail 'At least one command is required.'
case "$commands" in *[!a-zA-Z0-9_.,[:space:]-\;]*) fail 'Command string contains unsupported characters.' ;; esac
IFS=';' read -r -a command_list <<< "$commands"
for command in "${command_list[@]}"; do
  case "$command" in
    dashboard\ -n\ [1-9]|thread\ -n\ [1-9]|thread\ -n\ [1-9][0-9]|jvm|memory|version) ;;
    *) fail "Command is not in the bounded L1 allowlist: $command" ;;
  esac
done
state_root=${HOME:?HOME is not set}/.performance-diagnosis
home=$state_root/tasks
mkdir -p "$home"; chmod 700 "$state_root" "$home"
script=$(mktemp "$home/arthas-commands.XXXXXX.as")
trap 'rm -f "$script"' EXIT
printf '%s\n' "${command_list[@]}" > "$script"
if command -v timeout >/dev/null 2>&1; then
  timeout --signal=TERM --kill-after=2 "$timeout_seconds" "$java" -jar "$boot" -f "$script" "$pid"
elif command -v gtimeout >/dev/null 2>&1; then
  gtimeout --signal=TERM --kill-after=2 "$timeout_seconds" "$java" -jar "$boot" -f "$script" "$pid"
else
  fail 'A timeout utility (timeout or gtimeout) is required; refusing to launch an unbounded Arthas command.'
fi
