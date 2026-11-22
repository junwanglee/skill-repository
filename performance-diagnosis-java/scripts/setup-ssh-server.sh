#!/usr/bin/env bash
set -eu

fail() { printf 'Error: %s\n' "$1" >&2; exit 1; }
usage() {
  cat <<'EOF'
Usage: setup-ssh-server.sh [--alias ALIAS --host HOST --user USER [--port PORT] [--auth password|key] [--public-key FILE.pub]]

With a terminal, missing values are prompted. Without a TTY, pass --alias,
--host, and --user. Passwords are never accepted as arguments. A password
login can only be prompted by OpenSSH in a local interactive terminal.

Examples:
  setup-ssh-server.sh --alias beta --host 10.0.0.8 --user deploy --port 22 --auth password
  setup-ssh-server.sh --alias beta --host 10.0.0.8 --user deploy --auth key --public-key ~/.ssh/id_ed25519.pub
EOF
}

command -v ssh >/dev/null 2>&1 || fail 'OpenSSH client is required.'
interactive=0
[ "$#" -eq 0 ] && [ -t 0 ] && interactive=1
alias=
hostname=
username=
port=22
auth_mode=password
public_key_path=

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --alias|--host|--user|--port|--auth|--public-key)
      [ "$#" -ge 2 ] || fail "Missing value for $1"
      option=$1; value=$2; shift 2
      case "$option" in
        --alias) alias=$value ;;
        --host) hostname=$value ;;
        --user) username=$value ;;
        --port) port=$value ;;
        --auth) auth_mode=$value ;;
        --public-key) public_key_path=$value ;;
      esac
      ;;
    *) fail "Unknown option: $1 (use --help)." ;;
  esac
done

if [ "$interactive" -eq 1 ]; then
  read -r -p 'SSH alias: ' alias
  read -r -p 'Server hostname or IP: ' hostname
  read -r -p 'SSH username: ' username
  read -r -p 'SSH port [22]: ' port
  port=${port:-22}
  printf 'Authentication: [1] password (default), [2] public key: '
  read -r choice
  [ "${choice:-1}" != 2 ] || auth_mode=key
else
  if [ -z "$alias" ] || [ -z "$hostname" ] || [ -z "$username" ]; then
    usage >&2
    fail 'No TTY detected. Pass --alias, --host, and --user; nothing was configured.'
  fi
fi

case "$alias" in ''|*[!a-zA-Z0-9_.-]*) fail 'Invalid alias; use letters, digits, dot, underscore, or hyphen.' ;; esac
case "$hostname" in ''|*[!a-zA-Z0-9_.:-]*) fail 'Invalid hostname or IP.' ;; esac
case "$username" in ''|*[!a-zA-Z0-9_.-]*) fail 'Invalid username.' ;; esac
case "$port" in ''|*[!0-9]*) fail 'Port must be numeric.' ;; esac
[ "$port" -ge 1 ] && [ "$port" -le 65535 ] || fail 'Port must be between 1 and 65535.'
case "$auth_mode" in password|key) ;; *) fail '--auth must be password or key.' ;; esac

ssh_dir=${HOME:?HOME is not set}/.ssh
mkdir -p "$ssh_dir"
chmod 700 "$ssh_dir"
config="$ssh_dir/config"
if [ -f "$config" ] && awk -v alias="$alias" 'tolower($1)=="host" { for(i=2;i<=NF;i++) if($i==alias) found=1 } END { exit(found?0:1) }' "$config"; then
  fail "SSH alias '$alias' already exists in $config; choose another alias."
fi

identity_file=
if [ "$auth_mode" = key ]; then
  command -v ssh-keygen >/dev/null 2>&1 || fail 'ssh-keygen is required for key login.'
  if [ -z "$public_key_path" ] && [ "$interactive" -eq 1 ]; then
    printf 'Available public keys:\n'
    for candidate in "$ssh_dir"/*.pub; do [ ! -f "$candidate" ] || printf '  %s\n' "$candidate"; done
    read -r -p 'Public key path (.pub), or new: ' public_key_path
  fi
  if [ -z "$public_key_path" ] || [ "$public_key_path" = new ]; then
    [ "$interactive" -eq 1 ] || fail 'Non-interactive key setup requires --public-key FILE.pub.'
    identity_file="$ssh_dir/id_ed25519_performance_diagnosis_$alias"
    [ ! -e "$identity_file" ] && [ ! -e "$identity_file.pub" ] || fail "Key path exists: $identity_file"
    ssh-keygen -t ed25519 -C "performance-diagnosis-$alias" -f "$identity_file"
    public_key_path="$identity_file.pub"
  else
    case "$public_key_path" in *.pub) identity_file=${public_key_path%.pub} ;; *) fail 'Public key path must end in .pub.' ;; esac
  fi
  [ -f "$public_key_path" ] && [ -f "$identity_file" ] || fail 'Matching public and private key files are required.'
fi

snippet="$ssh_dir/config.performance-diagnosis.$alias"
[ ! -e "$snippet" ] || fail "Refusing to overwrite existing file: $snippet"
umask 077
{
  printf 'Host %s\n    HostName %s\n    User %s\n    Port %s\n' "$alias" "$hostname" "$username" "$port"
  if [ "$auth_mode" = password ]; then
    printf '    PreferredAuthentications keyboard-interactive,password,publickey\n'
  else
    printf '    IdentityFile %s\n    IdentitiesOnly yes\n' "$identity_file"
  fi
} > "$snippet"
chmod 600 "$snippet"

printf 'Created reviewable SSH config snippet: %s\n' "$snippet"
cat "$snippet"
printf 'Review and append it to %s; the existing config was not changed.\n' "$config"
if [ "$auth_mode" = password ]; then
  printf 'Password is never read by this script. In a local terminal, SSH can prompt for it with:\n  ssh -F %s %s true\n' "$snippet" "$alias"
  if [ "$interactive" -eq 1 ]; then
    read -r -p 'Try the SSH login now? [y/N]: ' try_login
    case "$try_login" in y|Y|yes|YES) ssh -F "$snippet" -o ConnectTimeout=10 "$alias" true ;; esac
  else
    printf '%s\n' 'No TTY detected; no connection attempted. Run the command above in a terminal to enter the password.'
  fi
else
  printf 'Public key to install on the server (public data only):\n'
  cat "$public_key_path"
  printf 'After installing the key and merging the config, verify with: ssh -F %s -o BatchMode=yes %s true\n' "$snippet" "$alias"
fi
printf '%s\n' 'Host Key checking remains enabled; verify the server fingerprint.'
