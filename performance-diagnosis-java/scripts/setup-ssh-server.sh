#!/usr/bin/env bash
set -eu

fail() { printf '错误：%s\n' "$1" >&2; exit 1; }
usage() {
  cat <<'EOF'
用法：setup-ssh-server.sh [--alias ALIAS --host HOST --user USER [--port PORT] [--auth password|key] [--public-key FILE.pub]]

有交互终端时会逐项询问缺少的信息。无 TTY 时必须传入 --alias，
--host 和 --user。密码不会作为命令参数传入；密码登录只能由本机
OpenSSH 在交互终端中提示输入。

示例：
  setup-ssh-server.sh --alias beta --host 10.0.0.8 --user deploy --port 22 --auth password
  setup-ssh-server.sh --alias beta --host 10.0.0.8 --user deploy --auth key --public-key ~/.ssh/id_ed25519.pub
EOF
}

command -v ssh >/dev/null 2>&1 || fail '需要安装 OpenSSH 客户端。'
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
      [ "$#" -ge 2 ] || fail "缺少参数值： $1"
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
    *) fail "未知选项：$1（使用 --help 查看帮助）。" ;;
  esac
done

if [ "$interactive" -eq 1 ]; then
  read -r -p '服务器别名：' alias
  read -r -p '服务器主机名或 IP：' hostname
  read -r -p 'SSH 用户名：' username
  read -r -p 'SSH 端口 [22]：' port
  port=${port:-22}
  printf '认证方式：[1] 密码（默认），[2] SSH 公钥：'
  read -r choice
  [ "${choice:-1}" != 2 ] || auth_mode=key
else
  if [ -z "$alias" ] || [ -z "$hostname" ] || [ -z "$username" ]; then
    usage >&2
    fail '当前环境没有交互终端。请传入 --alias、--host 和 --user；未修改任何配置。'
  fi
fi

case "$alias" in ''|*[!a-zA-Z0-9_.-]*) fail '别名无效；请使用英文字母、数字、点、下划线或连字符。' ;; esac
case "$hostname" in ''|*[!a-zA-Z0-9_.:-]*) fail '主机名或 IP 无效。' ;; esac
case "$username" in ''|*[!a-zA-Z0-9_.-]*) fail '用户名无效。' ;; esac
case "$port" in ''|*[!0-9]*) fail '端口必须为数字。' ;; esac
[ "$port" -ge 1 ] && [ "$port" -le 65535 ] || fail '端口必须在 1 至 65535 之间。'
case "$auth_mode" in password|key) ;; *) fail '--auth 只能为 password 或 key。' ;; esac

ssh_dir=${HOME:?HOME is not set}/.ssh
mkdir -p "$ssh_dir"
chmod 700 "$ssh_dir"
config="$ssh_dir/config"
if [ -f "$config" ] && awk -v alias="$alias" 'tolower($1)=="host" { for(i=2;i<=NF;i++) if($i==alias) found=1 } END { exit(found?0:1) }' "$config"; then
  fail "SSH 别名 '$alias' 已存在于 $config，请换一个别名。"
fi

identity_file=
if [ "$auth_mode" = key ]; then
  command -v ssh-keygen >/dev/null 2>&1 || fail '密钥登录需要 ssh-keygen。'
  if [ -z "$public_key_path" ] && [ "$interactive" -eq 1 ]; then
    printf '本机可用公钥：\n'
    for candidate in "$ssh_dir"/*.pub; do [ ! -f "$candidate" ] || printf '  %s\n' "$candidate"; done
    read -r -p '公钥文件路径（.pub），或输入 new 生成新密钥：' public_key_path
  fi
  if [ -z "$public_key_path" ] || [ "$public_key_path" = new ]; then
    [ "$interactive" -eq 1 ] || fail '无交互终端时，密钥配置必须提供 --public-key FILE.pub。'
    identity_file="$ssh_dir/id_ed25519_performance_diagnosis_$alias"
    [ ! -e "$identity_file" ] && [ ! -e "$identity_file.pub" ] || fail "密钥路径已存在：$identity_file"
    ssh-keygen -t ed25519 -C "performance-diagnosis-$alias" -f "$identity_file"
    public_key_path="$identity_file.pub"
  else
    case "$public_key_path" in *.pub) identity_file=${public_key_path%.pub} ;; *) fail '公钥路径必须以 .pub 结尾。' ;; esac
  fi
  [ -f "$public_key_path" ] && [ -f "$identity_file" ] || fail '必须同时存在匹配的公钥和私钥文件。'
fi

if [ -L "$config" ]; then
  fail "拒绝替换符号链接形式的 SSH 配置：$config"
fi
if [ -e "$config" ] && [ ! -f "$config" ]; then
  fail "SSH 配置不是普通文件：$config"
fi
if [ -f "$config" ] && awk 'tolower($1)=="host" { for(i=2;i<=NF;i++) if($i=="*") found=1 } END { exit(found?0:1) }' "$config"; then
  fail "$config 中已有 Host * 块。请将新 Host 块放在它之前，并用 ssh -G $alias 检查有效配置。"
fi
umask 077
entry_tmp=$(mktemp "$ssh_dir/ssh-host-entry.XXXXXX")
{
  printf 'Host %s\n    HostName %s\n    User %s\n    Port %s\n' "$alias" "$hostname" "$username" "$port"
  if [ "$auth_mode" = password ]; then
    printf '    PreferredAuthentications keyboard-interactive,password,publickey\n'
    printf '    ControlMaster auto\n    ControlPath ~/.ssh/cm-%%C\n    ControlPersist 1h\n'
  else
    printf '    IdentityFile %s\n    IdentitiesOnly yes\n' "$identity_file"
  fi
} > "$entry_tmp"
chmod 600 "$entry_tmp"
printf '即将写入以下 SSH Host 配置：\n'
cat "$entry_tmp"
legacy_snippet="$ssh_dir/config.performance-diagnosis.$alias"
if [ -e "$legacy_snippet" ]; then
  printf '保留旧版配置片段不变：%s\n' "$legacy_snippet"
fi
config_tmp=$(mktemp "$ssh_dir/config.tmp.XXXXXX")
trap 'rm -f "$config_tmp" "$entry_tmp"' EXIT
if [ -f "$config" ]; then cat "$config" > "$config_tmp"; fi
if [ -s "$config_tmp" ]; then printf '\n' >> "$config_tmp"; fi
cat "$entry_tmp" >> "$config_tmp"
chmod 600 "$config_tmp"
mv "$config_tmp" "$config"
trap - EXIT
rm -f "$entry_tmp"
printf '已将 Host %s 写入 %s，并保留原有配置。\n' "$alias" "$config"
effective=$(ssh -G -F "$config" "$alias" 2>/dev/null || true)
if [ -z "$effective" ] || ! printf '%s\n' "$effective" | awk -v host="$hostname" -v user="$username" -v port="$port" '
  $1=="hostname" && $2==host {h=1}
  $1=="user" && $2==user {u=1}
  $1=="port" && $2==port {p=1}
  END {exit(h && u && p ? 0 : 1)}'; then
  fail "生效的 SSH 参数与输入不一致。连接前请检查 ssh -G $alias 的输出并修正 $config。"
fi
if [ "$auth_mode" = password ]; then
  printf '脚本不会读取密码。在本机终端可运行以下命令，由 OpenSSH 提示输入密码：\n  ssh %s true\n' "$alias"
  if [ "$interactive" -eq 1 ]; then
    read -r -p '现在测试 SSH 登录吗？[y/N]：' try_login
    case "$try_login" in y|Y|yes|YES) ssh -o ConnectTimeout=10 "$alias" true ;; esac
  else
    printf '%s\n' '当前环境没有交互终端，未尝试连接。请在本机终端运行上面的命令并输入密码。'
  fi
else
  printf '请按组织流程将以下公钥安装到服务器（仅公钥内容）：\n'
  cat "$public_key_path"
  printf '安装公钥后，使用以下命令验证： ssh -o BatchMode=yes %s true\n' "$alias"
fi
printf '%s\n' 'SSH Host Key 校验保持开启；请按组织流程核对服务器指纹。'
