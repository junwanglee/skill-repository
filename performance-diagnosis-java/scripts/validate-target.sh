#!/usr/bin/env bash
set -eu

usage() {
  printf '%s\n' 'Usage: validate-target.sh --host-alias ALIAS --container-id ID --pid PID' >&2
}

host_alias=
container_id=
pid=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --host-alias) [ "$#" -ge 2 ] || { usage; exit 2; }; host_alias=$2; shift 2 ;;
    --container-id) [ "$#" -ge 2 ] || { usage; exit 2; }; container_id=$2; shift 2 ;;
    --pid) [ "$#" -ge 2 ] || { usage; exit 2; }; pid=$2; shift 2 ;;
    *) usage; exit 2 ;;
  esac
done

case "$host_alias" in ''|*[!a-zA-Z0-9_.-]*) printf '%s\n' 'Invalid SSH alias.' >&2; exit 2 ;; esac
case "$container_id" in ''|*[!a-fA-F0-9]*) printf '%s\n' 'Container ID must be hexadecimal.' >&2; exit 2 ;; esac
case "$pid" in ''|*[!0-9]*|0) printf '%s\n' 'PID must be a positive integer.' >&2; exit 2 ;; esac

printf 'Validated target identifiers (not connected): host=%s container=%s pid=%s\n' "$host_alias" "$container_id" "$pid"
printf '%s\n' 'This checks syntax only; operator confirmation and remote identity verification are still required.'
