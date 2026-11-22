#!/usr/bin/env bash
set -eu

if ! command -v ssh >/dev/null 2>&1; then
  printf '%s\n' 'ssh client: missing' >&2
  exit 1
fi

config=${HOME:?HOME is not set}/.ssh/config
if [ ! -r "$config" ]; then
  printf 'SSH config is not readable: %s\n' "$config" >&2
  exit 1
fi

ssh -G -F "$config" '*' 2>/dev/null \
  | awk '
      /^host / { host=$2; next }
      /^hostname / { hostname=$2 }
      /^user / { user=$2 }
      /^port / { port=$2 }
      /^$/ {
        if (host != "" && host !~ /[?*!]/ && host != "none")
          printf "%s\t%s\t%s\t%s\n", host, hostname, user, port
        host=hostname=user=port=""
      }
      END {
        if (host != "" && host !~ /[?*!]/ && host != "none")
          printf "%s\t%s\t%s\t%s\n", host, hostname, user, port
      }
    ' | while IFS="$(printf '\t')" read -r alias hostname user port; do
      [ -n "$alias" ] || continue
      if ssh -F "$config" -o BatchMode=yes -o ConnectTimeout=5 "$alias" 'printf SSH_OK' >/dev/null 2>&1; then
        status='passwordless-connectable'
      else
        status='unavailable-or-interactive-auth-required'
      fi
      printf '%s\t%s\t%s\t%s\t%s\n' "$alias" "$hostname" "$user" "$port" "$status"
    done
