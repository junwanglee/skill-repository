#!/usr/bin/env bash
set -eu

command -v ssh >/dev/null 2>&1 || { printf '%s\n' 'ssh client: missing' >&2; exit 1; }
config=${HOME:?HOME is not set}/.ssh/config
if [ ! -r "$config" ]; then
  printf 'SSH 配置不存在或不可读：%s\n' "$config"
  exit 0
fi

aliases=$(awk '
  tolower($1) == "host" {
    for (i=2; i<=NF; i++) {
      name=$i
      if (name !~ /[?*!]/ && name != "none" && !seen[name]++) print name
    }
  }
' "$config")

if [ -z "$aliases" ]; then
  printf '在 %s 中没有找到可选择的 SSH Host 别名。仅包含通配符的 Host 块不是目标。\n' "$config"
  exit 0
fi

printf '别名\t主机\t用户\t端口\t状态\n'
printf '%s\n' "$aliases" | while IFS= read -r alias; do
  case "$alias" in ''|*[!a-zA-Z0-9_.-]*) continue ;; esac
  resolved=$(ssh -G -F "$config" "$alias" 2>/dev/null || true)
  [ -n "$resolved" ] || {
    printf '%s\t?\t?\t?\t配置错误\n' "$alias"
    continue
  }
  details=$(printf '%s\n' "$resolved" | awk '
    $1 == "hostname" { host=$2 }
    $1 == "user" { user=$2 }
    $1 == "port" { port=$2 }
    END { printf "%s\t%s\t%s", host, user, port }
  ')
  status=未测试
  printf '%s\t%s\t%s\t%s\t%s\n' "$alias" "$details" "$status"
done
