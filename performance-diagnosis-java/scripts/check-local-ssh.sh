#!/usr/bin/env bash
set -eu

if ! command -v ssh >/dev/null 2>&1; then
  printf '%s\n' 'ssh client: missing'
  exit 1
fi
printf 'ssh client: %s\n' "$(command -v ssh)"

ssh_dir=${HOME:?HOME is not set}/.ssh
if [ ! -d "$ssh_dir" ]; then
  printf 'SSH directory: missing (%s)\n' "$ssh_dir"
  exit 0
fi
printf 'SSH directory: present (%s)\n' "$ssh_dir"
[ ! -f "$ssh_dir/config" ] || printf '%s\n' 'SSH config: present'
[ ! -S "${SSH_AUTH_SOCK:-/nonexistent}" ] || printf '%s\n' 'SSH agent socket: present'

for key in id_ed25519 id_rsa; do
  if [ -f "$ssh_dir/$key" ]; then
    printf 'Private key file: present (%s; contents not read)\n' "$ssh_dir/$key"
  fi
done
for key in id_ed25519.pub id_rsa.pub; do
  if [ -f "$ssh_dir/$key" ]; then
    printf 'Public key file: present (%s)\n' "$ssh_dir/$key"
  fi
done
printf '%s\n' 'Key presence does not establish passwordless connectivity; test a selected alias with BatchMode.'
