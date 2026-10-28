#!/usr/bin/env bash
# Download a file and its .sha256 companion, and verify the checksum.
#
# Usage: fetch.sh <url> <dest-dir>
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
name=$(basename "$url")
mkdir -p "$dest"
file="$dest/$name"
sum="$file.sha256"

verify() {
    [ -f "$file" ] && [ -f "$sum" ] && (cd "$dest" && shasum -a 256 -c "$name.sha256" >/dev/null 2>&1)
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
    curl -fsSL --retry 3 -o "$sum" "$url.sha256" && curl -fsSL --retry 3 -o "$file" "$url" || true
done

echo "$file"
