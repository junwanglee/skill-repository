#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() {
  cat >&2 <<'USAGE'
用法：arthas-profiler.sh --java JAVA --arthas-boot JAR --pid PID --duration SEC --interval-ns NS --format md|html --output FILE --evidence-dir DIR

在目标 Linux 容器内运行一次有界 Arthas CPU profiler 采样。脚本会先启动采样，
再分开检查状态/样本并等待采样窗口，最后停止并导出；零样本时返回失败。
本脚本不代替 SKILL.md 中的目标选择、风险确认或 L2 授权。
USAGE
}
fail() { printf '错误：%s\n' "$1" >&2; exit 2; }

java= boot= pid= duration= interval= format= output= evidence_dir=
while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || { usage; exit 2; }
  option=$1 value=$2; shift 2
  case "$option" in
    --java) java=$value ;;
    --arthas-boot) boot=$value ;;
    --pid) pid=$value ;;
    --duration) duration=$value ;;
    --interval-ns) interval=$value ;;
    --format) format=$value ;;
    --output) output=$value ;;
    --evidence-dir) evidence_dir=$value ;;
    -h|--help) usage; exit 0 ;;
    *) fail "未知参数：$option" ;;
  esac
done

[ -x "$java" ] || fail 'Java 可执行文件不存在或不可执行。'
[ -r "$boot" ] || fail 'arthas-boot.jar 不存在或不可读。'
command -v timeout >/dev/null 2>&1 || fail '目标容器需要 timeout 命令；无法保证 Arthas 调用有界，已拒绝启动。'
[ -n "$output" ] && [ -n "$evidence_dir" ] || fail '必须指定 --output 和 --evidence-dir。'
case "$pid" in ''|*[!0-9]*) fail 'PID 必须是数字。' ;; esac
case "$duration" in ''|*[!0-9]*) fail '采样时长必须是整数秒。' ;; esac
[ "$duration" -ge 1 ] && [ "$duration" -le 300 ] || fail '采样时长必须为 1 至 300 秒。'
case "$interval" in 10000000|20000000|50000000) ;; *) fail '采样间隔仅支持 10000000、20000000 或 50000000 纳秒。' ;; esac
case "$format" in md|html) ;; *) fail '输出格式仅支持 md 或 html。' ;; esac
case "$output$evidence_dir" in *[!a-zA-Z0-9_./-]*) fail '输出路径包含不支持的字符。' ;; esac
[ -d "$evidence_dir" ] || fail '证据目录必须已存在；请先验证目标目录并创建任务目录。'
[ -w "$evidence_dir" ] || fail '证据目录不可写。'
parent=$(dirname "$output")
[ -d "$parent" ] && [ -w "$parent" ] || fail '输出文件父目录不存在或不可写。'
[ "$parent" = "$evidence_dir" ] || fail '输出文件必须直接写入本任务证据目录。'
[ ! -e "$output" ] || fail '输出文件已存在；拒绝覆盖。'

start_file=$evidence_dir/profiler-start.as
status_file=$evidence_dir/profiler-status.as
samples_file=$evidence_dir/profiler-samples.as
stop_file=$evidence_dir/profiler-stop.as
start_log=$evidence_dir/profiler-start.log
status_log=$evidence_dir/profiler-status.log
samples_log=$evidence_dir/profiler-samples.log
stop_log=$evidence_dir/profiler-stop.log
failed_file=$evidence_dir/profile.failed.md
started=0
finished=0

run_arthas() {
  local commands_file=$1 log_file=$2
  timeout --signal=TERM --kill-after=2 20 "$java" -jar "$boot" -f "$commands_file" "$pid" >"$log_file" 2>&1
}
write_command() {
  local path=$1 command=$2
  (umask 077; printf '%s\n' "$command" > "$path")
}
read_samples() {
  local log_file=$1
  awk '/^[[:space:]]*[0-9]+[[:space:]]*$/ {gsub(/[[:space:]]/, ""); value=$0} END {if (value != "") print value}' "$log_file"
}
save_failure() {
  local reason=$1 samples=${2:-unknown}
  {
    printf '# Profiler 采样失败证据\n\n'
    printf -- '- 失败原因：%s\n' "$reason"
    printf -- '- 目标 PID：%s\n' "$pid"
    printf -- '- 请求时长：%s 秒\n' "$duration"
    printf -- '- 采样间隔：%s ns\n' "$interval"
    printf -- '- 已观测样本数：%s\n' "$samples"
    printf -- '- 原始日志：%s\n' "$evidence_dir"
    printf '\n此文件仅为失败证据，不是有效 profiler 报告。\n'
  } > "$failed_file"
  chmod 600 "$failed_file"
}
cleanup_on_error() {
  local code=$?
  if [ "$started" -eq 1 ] && [ "$finished" -eq 0 ]; then
    write_command "$stop_file" 'profiler stop'
    "$java" -jar "$boot" -f "$stop_file" "$pid" >"$evidence_dir/profiler-cleanup.log" 2>&1 || true
  fi
  exit "$code"
}
trap cleanup_on_error EXIT

printf '阶段 1/4：启动 CPU profiler（%s 秒，间隔 %s ns）。\n' "$duration" "$interval"
write_command "$start_file" "profiler start -e cpu -i $interval"
if ! run_arthas "$start_file" "$start_log"; then
  save_failure 'Arthas 启动命令失败。'
  printf '采集失败：Arthas 启动命令失败，日志保存在 %s。\n' "$evidence_dir" >&2
  exit 1
fi
started=1

printf '阶段 2/4：确认 profiler 状态并等待采样窗口。\n'
start_epoch=$(date +%s)
deadline=$((start_epoch + duration))
while :; do
  write_command "$status_file" 'profiler status'
  if ! run_arthas "$status_file" "$status_log"; then
    save_failure '无法确认 profiler 状态。' 
    printf '采集失败：无法确认 profiler 状态；停止尝试并保留证据。\n' >&2
    exit 1
  fi
  if ! grep -Eiq 'profiling is running|正在采样' "$status_log"; then
    save_failure 'Profiler 未进入可确认的运行状态。'
    printf '采集失败：未确认 profiler 正在运行；已保留证据。\n' >&2
    exit 1
  fi
  write_command "$samples_file" 'profiler getSamples'
  if ! run_arthas "$samples_file" "$samples_log"; then
    save_failure '无法读取 profiler 样本数。'
    printf '采集失败：无法读取 profiler 样本数；停止尝试并保留证据。\n' >&2
    exit 1
  fi
  now=$(date +%s)
  [ "$now" -ge "$deadline" ] && break
  sleep 2
done

samples=$(read_samples "$samples_log")
case "$samples" in ''|*[!0-9]*) samples=unknown ;; esac
if [ "$samples" = unknown ] || [ "$samples" -le 0 ]; then
  save_failure '采样窗口结束后样本数为零或无法解析。' "$samples"
  write_command "$stop_file" 'profiler stop'
  "$java" -jar "$boot" -f "$stop_file" "$pid" >"$stop_log" 2>&1 || true
  finished=1
  printf '采集失败：样本数为 %s；未生成有效 profile 报告。证据保存在 %s。\n' "$samples" "$evidence_dir" >&2
  exit 1
fi

printf '阶段 3/4：停止采样并导出 %s。样本数：%s。\n' "$format" "$samples"
write_command "$stop_file" "profiler stop --format $format --file $output"
if ! run_arthas "$stop_file" "$stop_log"; then
  save_failure 'Profiler 停止或导出命令失败。' "$samples"
  printf '采集失败：停止/导出失败，日志保存在 %s。\n' "$evidence_dir" >&2
  exit 1
fi
finished=1

if [ ! -s "$output" ]; then
  save_failure '导出命令结束，但产物不存在或为空。' "$samples"
  printf '采集失败：输出文件不存在或为空。\n' >&2
  exit 1
fi
chmod 600 "$output"
if [ "$format" = md ] && ! grep -Eq '^\|[[:space:]]*[0-9]+[[:space:]]*\|' "$output"; then
  save_failure 'Markdown 产物未发现有效热点表格。' "$samples"
  printf '采集失败：Markdown 文件没有有效热点表格。\n' >&2
  exit 1
fi
if [ "$format" = html ] && ! grep -Eiq 'flame|profile|cpool|frames' "$output"; then
  save_failure 'HTML 产物不包含可识别的 profiler 内容。' "$samples"
  printf '采集失败：HTML 文件内容校验失败。\n' >&2
  exit 1
fi

printf '阶段 4/4：确认采样结束及产物有效。\n'
write_command "$status_file" 'profiler status'
if ! run_arthas "$status_file" "$status_log"; then
  save_failure '导出后无法确认 profiler 已停止。' "$samples"
  printf '采集失败：无法确认 profiler 停止状态。\n' >&2
  exit 1
fi
if grep -Eiq 'profiling is running|正在采样' "$status_log"; then
  save_failure '导出后 profiler 仍处于运行状态。' "$samples"
  printf '采集失败：导出后 profiler 仍在运行。\n' >&2
  exit 1
fi

trap - EXIT
{
  printf 'pid=%s\n' "$pid"
  printf 'requested_duration_seconds=%s\n' "$duration"
  printf 'sampling_interval_ns=%s\n' "$interval"
  printf 'observed_samples=%s\n' "$samples"
  printf 'artifact=%s\n' "$output"
} > "$evidence_dir/profile-result.txt"
chmod 600 "$evidence_dir/profile-result.txt"
printf '采集成功：样本数 %s；输出文件 %s。\n' "$samples" "$output"
