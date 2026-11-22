#!/usr/bin/env bash
set -euo pipefail

readonly VERSION=4.3.5
readonly URL=https://arthas.aliyun.com/arthas-boot.jar
readonly CACHE_ROOT=${HOME:?HOME is not set}/.performance-diagnosis/arthas/versions
readonly CACHE_DIR=$CACHE_ROOT/$VERSION
readonly JAR=$CACHE_DIR/arthas-boot.jar
readonly DIGEST=$CACHE_DIR/arthas-boot.jar.sha256

fail() { printf 'Error: %s\n' "$1" >&2; exit 1; }
command -v unzip >/dev/null 2>&1 || fail 'unzip is required to inspect the Arthas launcher manifest.'
if command -v shasum >/dev/null 2>&1; then hash_cmd=shasum
elif command -v sha256sum >/dev/null 2>&1; then hash_cmd=sha256sum
else fail 'shasum or sha256sum is required.'
fi

mkdir -p "$CACHE_DIR"
chmod 700 "$HOME/.performance-diagnosis" "$HOME/.performance-diagnosis/arthas" "$CACHE_ROOT" "$CACHE_DIR"

verify_version() {
  local manifest version_line
  manifest=$(unzip -p "$1" META-INF/MANIFEST.MF 2>/dev/null) || fail 'Downloaded file is not a readable JAR.'
  version_line=$(printf '%s\n' "$manifest" | tr -d '\r' | awk -F': ' 'tolower($1)=="implementation-version" || tolower($1)=="specification-version" {print $2; exit}')
  case "$version_line" in "$VERSION"|"$VERSION"-*) ;; *) fail "Expected Arthas $VERSION, JAR manifest reports '${version_line:-unknown}'. Refusing to cache it." ;; esac
}
sha256() {
  if [ "$hash_cmd" = shasum ]; then shasum -a 256 "$1" | awk '{print $1}'
  else sha256sum "$1" | awk '{print $1}'
  fi
}

if [ -f "$JAR" ]; then
  [ -s "$DIGEST" ] || fail "Cached JAR has no trusted-on-first-download local digest: $DIGEST. Remove/restore cache only after reviewing its origin."
  expected=$(awk 'NF && $1 !~ /^#/ {print $1; exit}' "$DIGEST")
  actual=$(sha256 "$JAR")
  [ -n "$expected" ] && [ "$actual" = "$expected" ] || fail 'Cached Arthas SHA-256 mismatch; refusing to use it.'
  verify_version "$JAR"
  printf 'Arthas %s ready from cache: %s\nSHA-256: %s\n' "$VERSION" "$JAR" "$actual"
  exit 0
fi

[ ! -e "$DIGEST" ] || fail "Digest record exists but cached JAR is missing: $DIGEST"
command -v curl >/dev/null 2>&1 || fail 'curl is required for first download.'
tmp=$(mktemp "$CACHE_DIR/.arthas-boot.XXXXXX")
trap 'rm -f "$tmp"' EXIT
printf 'Downloading official Arthas launcher to local cache...\n'
curl --fail --location --silent --show-error --retry 2 --connect-timeout 10 --max-time 120 --output "$tmp" "$URL" || fail 'Arthas download failed; no cache was created.'
verify_version "$tmp"
actual=$(sha256 "$tmp")
chmod 600 "$tmp"
mv "$tmp" "$JAR"
printf '%s  %s\n' "$actual" "$(basename "$JAR")" > "$DIGEST"
chmod 600 "$DIGEST"
printf 'Downloaded and cached Arthas %s: %s\nSHA-256: %s\n' "$VERSION" "$JAR" "$actual"
printf '%s\n' 'The initial digest records the first TLS download; it is a local corruption check, not an independent publisher signature.'
