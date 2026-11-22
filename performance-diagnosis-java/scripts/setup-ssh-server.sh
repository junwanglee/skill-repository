#!/usr/bin/env bash
set -eu

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

command -v ssh >/dev/null 2>&1 || fail 'OpenSSH client is required.'

ssh_dir=${HOME:?HOME is not set}/.ssh
mkdir -p "$ssh_dir"
chmod 700 "$ssh_dir"

read -r -p 'SSH alias (for example, prod-app): ' alias
case "$alias" in
  ''|*[!a-zA-Z0-9_.-]*) fail 'Alias may contain only letters, digits, dot, underscore, and hyphen.' ;;
esac

read -r -p 'Server hostname or IP: ' hostname
case "$hostname" in
  ''|*[!a-zA-Z0-9_.:-]*) fail 'Hostname contains unsupported characters.' ;;
esac

read -r -p 'SSH username: ' username
case "$username" in
  ''|*[!a-zA-Z0-9_.-]*) fail 'Username may contain only letters, digits, dot, underscore, and hyphen.' ;;
esac

read -r -p 'SSH port [22]: ' port
port=${port:-22}
case "$port" in
  ''|*[!0-9]*) fail 'Port must be numeric.' ;;
esac
[ "$port" -ge 1 ] && [ "$port" -le 65535 ] || fail 'Port must be between 1 and 65535.'

config="$ssh_dir/config"
if [ -f "$config" ] && awk -v alias="$alias" '
  tolower($1) == "host" {
    for (i = 2; i <= NF; i++) if ($i == alias) found=1
  }
  END { exit(found ? 0 : 1) }
' "$config"; then
  fail "SSH alias '$alias' already exists in $config; choose another alias."
fi

printf '\nAuthentication setup:\n'
printf '  1) Password or keyboard-interactive login (SSH prompts locally; recommended for first connection)\n'
printf '  2) SSH public key login\n'
read -r -p 'Choose [1/2, default 1]: ' auth_mode
auth_mode=${auth_mode:-1}
case "$auth_mode" in
  1|2) ;;
  *) fail 'Choose 1 for password login or 2 for key login.' ;;
esac

identity_file=
public_key_path=
if [ "$auth_mode" = 2 ]; then
  command -v ssh-keygen >/dev/null 2>&1 || fail 'ssh-keygen is required for key login.'
  printf '\nAvailable public keys (private key contents are never read):\n'
  public_keys=()
  for candidate in "$ssh_dir"/*.pub; do
    [ -f "$candidate" ] || continue
    public_keys+=("$candidate")
    printf '  %s\n' "$candidate"
  done

  if [ "${#public_keys[@]}" -gt 0 ]; then
    read -r -p "Public key path to use [${public_keys[0]}] (or 'new'): " public_key_path
    public_key_path=${public_key_path:-${public_keys[0]}}
    [ "$public_key_path" != new ] || public_key_path=
  fi

  if [ -z "$public_key_path" ]; then
    identity_file="$ssh_dir/id_ed25519_performance_diagnosis"
    if [ -e "$identity_file" ] || [ -e "$identity_file.pub" ]; then
      fail "Key path already exists: $identity_file; rerun and select its public key, or move it yourself."
    fi
    printf '\nThe key generator will prompt locally for a passphrase. The private key remains on this computer.\n'
    ssh-keygen -t ed25519 -C "performance-diagnosis-$alias" -f "$identity_file"
    public_key_path="$identity_file.pub"
  else
    [ -f "$public_key_path" ] || fail "Public key not found: $public_key_path"
    case "$public_key_path" in
      *.pub) identity_file=${public_key_path%.pub} ;;
      *) fail 'Select a public key file ending in .pub; private keys are never accepted.' ;;
    esac
  fi
  [ -f "$public_key_path" ] || fail "Public key not found: $public_key_path"
  [ -f "$identity_file" ] || fail "Matching private key file not found (its contents will not be read): $identity_file"
fi

snippet="$ssh_dir/config.performance-diagnosis.$alias"
[ ! -e "$snippet" ] || fail "Refusing to overwrite existing file: $snippet"
umask 077
{
  cat <<EOF
Host $alias
    HostName $hostname
    User $username
    Port $port
EOF
  if [ "$auth_mode" = 1 ]; then
    cat <<'EOF'
    PreferredAuthentications keyboard-interactive,password,publickey
EOF
  else
    cat <<EOF
    IdentityFile $identity_file
    IdentitiesOnly yes
EOF
  fi
} > "$snippet"
chmod 600 "$snippet"

printf '\nGenerated a reviewable SSH config snippet: %s\n' "$snippet"
cat "$snippet"
printf '\nReview and manually append this snippet to %s. The existing config was not modified.\n' "$config"

if [ "$auth_mode" = 1 ]; then
  printf '\nPassword mode selected. The password is entered only at the local SSH prompt; this script does not read or save it.\n'
  read -r -p 'Try an interactive SSH login now? [y/N]: ' try_login
  case "$try_login" in
    y|Y|yes|YES)
      printf 'Connecting to %s@%s:%s. Verify the host fingerprint; SSH may prompt for the account password locally.\n' "$username" "$hostname" "$port"
      ssh -o ConnectTimeout=10 -p "$port" -l "$username" "$hostname" true || fail 'SSH login failed; check the message and retry after correcting the connection details.'
      ;;
    *) printf '%s\n' 'No network connection attempted. After merging the snippet, connect with ssh <alias>; the local SSH prompt can request the password.' ;;
  esac
else
  printf '\nPublic key to install on the server (share only this .pub file):\n'
  cat "$public_key_path"
  printf '\nInstall the public key through your approved server access process. The private key remains on this computer.\n'
  printf 'After key installation and config merge, verify with:\n  ssh -o BatchMode=yes -o ConnectTimeout=5 %s true\n' "$alias"
fi
printf 'Host Key checking remains enabled; verify the server fingerprint through your normal process.\n'
