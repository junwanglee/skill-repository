#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  arthas-task.sh init --task-id ID --host ALIAS --container-id ID --pid PID
  arthas-task.sh status --task-id ID
  arthas-task.sh finish --task-id ID --result completed|failed|stopped

本地任务台账用于记录操作者或 Agent 发起的远程有界命令。
USAGE
}
fail() { printf '错误：%s\n' "$1" >&2; exit 2; }
[ "$#" -ge 1 ] || { usage; exit 2; }
action=$1; shift
task_id= host= container_id= pid= result=
while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || { usage; exit 2; }
  key=$1 value=$2; shift 2
  case "$key" in
    --task-id) task_id=$value ;;
    --host) host=$value ;;
    --container-id) container_id=$value ;;
    --pid) pid=$value ;;
    --result) result=$value ;;
    *) fail "Unknown option: $key" ;;
  esac
done
case "$task_id" in ''|*[!a-zA-Z0-9_.-]*) fail '任务 ID 无效。' ;; esac
state_root=${HOME:?HOME is not set}/.performance-diagnosis/tasks
mkdir -p "$state_root"
chmod 700 "$HOME/.performance-diagnosis" "$state_root"
state_file=$state_root/$task_id.state
case "$action" in
  init)
    [ -n "$host" ] && [ -n "$container_id" ] && [ -n "$pid" ] || fail 'init 必须提供 --host、--container-id 和 --pid。'
    case "$pid" in *[!0-9]*|'') fail 'PID 必须是数字。' ;; esac
    [ ! -e "$state_file" ] || fail "任务已存在：$task_id；请先检查任务状态再继续。"
    now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    (umask 077; printf 'task_id=%s\nhost=%s\ncontainer_id=%s\npid=%s\nstatus=prepared\nstarted_at=%s\nupdated_at=%s\n' "$task_id" "$host" "$container_id" "$pid" "$now" "$now" > "$state_file")
    printf '已创建任务记录：%s\n' "$state_file"
    ;;
  status)
    [ -f "$state_file" ] || fail "找不到本地任务记录：$task_id"
    cat "$state_file"
    grep -q '^status=completed$\|^status=failed$\|^status=stopped$' "$state_file" && exit 0
    printf '\n此任务尚未完成。继续前请核实远程进程和 Arthas 状态。\n'
    ;;
  finish)
    [ -f "$state_file" ] || fail "找不到本地任务记录：$task_id"
    case "$result" in completed|failed|stopped) ;; *) fail '--result 必须为 completed、failed 或 stopped。' ;; esac
    tmp=$state_file.tmp.$$
    awk -F= -v now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" -v result="$result" 'BEGIN{done=0} /^status=/ {print "status=" result; done=1; next} /^updated_at=/ {print "updated_at=" now; next} /^finished_at=/ {next} {print} END{if(!done) print "status=" result; print "finished_at=" now}' "$state_file" > "$tmp"
    chmod 600 "$tmp"; mv "$tmp" "$state_file"
    printf '任务已标记为 %s。请在诊断报告中记录远程停止/退出证据。\n' "$result"
    ;;
  *) usage; exit 2 ;;
esac
