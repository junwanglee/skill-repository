#!/usr/bin/env bash
set -eu

if ! command -v ssh >/dev/null 2>&1; then
  printf '%s\n' 'SSH 客户端：未安装'
  exit 1
fi
printf 'SSH 客户端：%s\n' "$(command -v ssh)"

ssh_dir=${HOME:?HOME is not set}/.ssh
if [ ! -d "$ssh_dir" ]; then
  printf 'SSH 目录：不存在（%s）\n' "$ssh_dir"
  exit 0
fi
printf 'SSH 目录：存在（%s）\n' "$ssh_dir"
[ ! -f "$ssh_dir/config" ] || printf '%s\n' 'SSH 配置：存在'
[ ! -S "${SSH_AUTH_SOCK:-/nonexistent}" ] || printf '%s\n' 'SSH Agent 套接字：存在'

for key in id_ed25519 id_rsa; do
  if [ -f "$ssh_dir/$key" ]; then
    printf '私钥文件：存在（%s；未读取内容）\n' "$ssh_dir/$key"
  fi
done
for key in id_ed25519.pub id_rsa.pub; do
  if [ -f "$ssh_dir/$key" ]; then
    printf '公钥文件：存在（%s）\n' "$ssh_dir/$key"
  fi
done
printf '%s\n' '密钥文件存在不代表可以连接；服务器列表只读取本地配置，只有选定服务器后才测试连接。'
