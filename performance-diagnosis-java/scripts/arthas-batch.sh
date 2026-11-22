#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: arthas-batch.sh --java JAVA [--arthas-boot JAR] --pid PID --timeout SECONDS --commands 'dashboard -n 1;thread -n 10'

仅执行文档列出的 L1 命令白名单；此脚本不执行 trace/watch/profiler。
  省略 --arthas-boot 时，会自动下载或使用本地固定版本 4.3.5 缓存。
USAGE
}
fail() { printf '错误：%s\n' "$1" >&2; exit 2; }
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
    *) fail "未知参数：$option" ;;
  esac
done
if [ -z "$boot" ]; then
  script_dir=$(cd "$(dirname "$0")" && pwd)
  "$script_dir/prepare-arthas.sh"
  boot=${HOME:?HOME is not set}/.performance-diagnosis/arthas/versions/4.3.5/arthas-boot.jar
fi
[ -x "$java" ] || fail 'Java 可执行文件不存在或不可执行。'
[ -r "$boot" ] || fail 'arthas-boot.jar 不存在或不可读。'
case "$pid" in ''|*[!0-9]*) fail 'PID 必须是数字。' ;; esac
case "$timeout_seconds" in ''|*[!0-9]*) fail '超时时间必须是数字。' ;; esac
[ "$timeout_seconds" -ge 1 ] && [ "$timeout_seconds" -le 30 ] || fail '超时时间必须为 1 至 30 秒。'
[ -n "$commands" ] || fail '至少需要一条命令。'
case "$commands" in *[!a-zA-Z0-9_.,[:space:]-\;]*) fail '命令包含不支持的字符。' ;; esac
IFS=';' read -r -a command_list <<< "$commands"
for command in "${command_list[@]}"; do
  case "$command" in
    dashboard\ -n\ [1-9]|thread\ -n\ [1-9]|thread\ -n\ [1-9][0-9]|jvm|memory|version) ;;
    *) fail "命令不在有界 L1 白名单中：$command" ;;
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
  fail '需要 timeout 或 gtimeout；为避免 Arthas 命令无限运行，已拒绝启动。'
fi
