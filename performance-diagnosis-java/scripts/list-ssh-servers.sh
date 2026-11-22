#!/usr/bin/env bash
set -eu

command -v ssh >/dev/null 2>&1 || { printf '%s\n' 'ssh client: missing' >&2; exit 1; }
config=${HOME:?HOME is not set}/.ssh/config
if [ ! -r "$config" ]; then
  printf 'SSH config is missing or unreadable: %s\n' "$config"
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
  printf 'No literal SSH Host aliases found in %s. Wildcard-only Host blocks are not selectable targets.\n' "$config"
  exit 0
fi

printf 'ALIAS\tHOST\tUSER\tPORT\tSTATUS\n'
printf '%s\n' "$aliases" | while IFS= read -r alias; do
  case "$alias" in ''|*[!a-zA-Z0-9_.-]*) continue ;; esac
  resolved=$(ssh -G -F "$config" "$alias" 2>/dev/null || true)
  [ -n "$resolved" ] || {
    printf '%s\t?\t?\t?\tconfig-error\n' "$alias"
    continue
  }
  details=$(printf '%s\n' "$resolved" | awk '
    $1 == "hostname" { host=$2 }
    $1 == "user" { user=$2 }
    $1 == "port" { port=$2 }
    END { printf "%s\t%s\t%s", host, user, port }
  ')
  if ssh -F "$config" -o BatchMode=yes -o ConnectTimeout=5 "$alias" true >/dev/null 2>&1; then
    status=passwordless-connectable
  else
    status=interactive-auth-required-or-unavailable
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$alias" "$details" "$status"
done
