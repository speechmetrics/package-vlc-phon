#!/usr/bin/env bash
# Download a file and its .sha256 companion, and verify the checksum.
#
# Usage: fetch.sh <url> <dest-dir> [<checksum-url>]
#
# <checksum-url> defaults to <url>.sha256. Pass a URL on VideoLAN's own
# server so a mirror serving the file cannot also serve its checksum.
#
# Prints the downloaded file's path. On any failure both files are removed
# and the script exits non-zero. A file already present that verifies is
# reused. Each download is tried up to three times, because VideoLAN's
# redirector sometimes sends a request to a mirror that lacks the file.
# Env: FETCH_RETRY_DELAY  seconds between attempts (default 10)
set -euo pipefail
source "$(dirname "$0")/lib.sh"

url="$1"
dest="$2"
checksum_url="${3:-$url.sha256}"
name=$(basename "$url")
mkdir -p "$dest"
file="$dest/$name"
sum="$file.sha256"

verify() {
    [ -f "$file" ] && [ -f "$sum" ] || return 1
    local expected actual
    expected=$(awk 'NR == 1 { print tolower($1) }' "$sum")
    actual=$(shasum -a 256 "$file" | awk '{ print $1 }')
    [ -n "$expected" ] && [ "$expected" = "$actual" ]
}

cleanup() {
    rm -f "$file" "$sum"
}
trap 'verify || cleanup' EXIT

attempt=0
until verify; do
    cleanup
    attempt=$((attempt + 1))
    [ "$attempt" -le 3 ] || die "download or checksum failed: $url"
    [ "$attempt" -eq 1 ] || sleep "${FETCH_RETRY_DELAY:-10}"
    curl -fsSL --retry 3 -o "$sum" "$checksum_url" && curl -fsSL --retry 3 -o "$file" "$url" || true
done

echo "$file"
