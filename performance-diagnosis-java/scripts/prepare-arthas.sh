#!/usr/bin/env bash
set -euo pipefail

readonly VERSION=4.3.5
readonly URL=https://arthas.aliyun.com/arthas-boot.jar
readonly CACHE_ROOT=${HOME:?HOME is not set}/.performance-diagnosis/arthas/versions
readonly CACHE_DIR=$CACHE_ROOT/$VERSION
readonly JAR=$CACHE_DIR/arthas-boot.jar
readonly DIGEST=$CACHE_DIR/arthas-boot.jar.sha256

fail() { printf '错误：%s\n' "$1" >&2; exit 1; }
command -v unzip >/dev/null 2>&1 || fail '检查 Arthas 启动包版本需要 unzip。'
if command -v shasum >/dev/null 2>&1; then hash_cmd=shasum
elif command -v sha256sum >/dev/null 2>&1; then hash_cmd=sha256sum
else fail '需要 shasum 或 sha256sum。'
fi

mkdir -p "$CACHE_DIR"
chmod 700 "$HOME/.performance-diagnosis" "$HOME/.performance-diagnosis/arthas" "$CACHE_ROOT" "$CACHE_DIR"

verify_version() {
  local manifest version_line
  manifest=$(unzip -p "$1" META-INF/MANIFEST.MF 2>/dev/null) || fail '下载文件不是可读取的 JAR。'
  version_line=$(printf '%s\n' "$manifest" | tr -d '\r' | awk -F': ' 'tolower($1)=="implementation-version" || tolower($1)=="specification-version" {print $2; exit}')
  case "$version_line" in "$VERSION"|"$VERSION"-*) ;; *) fail "预期 Arthas $VERSION，但 JAR manifest 显示 '${version_line:-unknown}'. 拒绝缓存。" ;; esac
}
sha256() {
  if [ "$hash_cmd" = shasum ]; then shasum -a 256 "$1" | awk '{print $1}'
  else sha256sum "$1" | awk '{print $1}'
  fi
}

if [ -f "$JAR" ]; then
  [ -s "$DIGEST" ] || fail "缓存 JAR 缺少首次下载时生成的本地摘要： $DIGEST. 确认来源后再删除或恢复缓存。"
  expected=$(awk 'NF && $1 !~ /^#/ {print $1; exit}' "$DIGEST")
  actual=$(sha256 "$JAR")
  [ -n "$expected" ] && [ "$actual" = "$expected" ] || fail '缓存 Arthas 的 SHA-256 不匹配，拒绝使用。'
  verify_version "$JAR"
  printf '已从缓存准备 Arthas %s：%s\nSHA-256: %s\n' "$VERSION" "$JAR" "$actual"
  exit 0
fi

[ ! -e "$DIGEST" ] || fail "摘要记录存在，但缓存 JAR 缺失： $DIGEST"
command -v curl >/dev/null 2>&1 || fail '首次下载需要 curl。'
tmp=$(mktemp "$CACHE_DIR/.arthas-boot.XXXXXX")
trap 'rm -f "$tmp"' EXIT
printf '正在从官方源下载 Arthas 启动包到本地缓存……\n'
curl --fail --location --silent --show-error --retry 2 --connect-timeout 10 --max-time 120 --output "$tmp" "$URL" || fail 'Arthas 下载失败，未创建缓存。'
verify_version "$tmp"
actual=$(sha256 "$tmp")
chmod 600 "$tmp"
mv "$tmp" "$JAR"
printf '%s  %s\n' "$actual" "$(basename "$JAR")" > "$DIGEST"
chmod 600 "$DIGEST"
printf '已下载并缓存 Arthas %s：%s\nSHA-256: %s\n' "$VERSION" "$JAR" "$actual"
printf '%s\n' '首次摘要基于 TLS 下载文件生成，用于检查本地缓存是否变化，不是独立的发布者签名。'
