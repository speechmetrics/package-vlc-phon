#!/usr/bin/env bash
# Download a file and its .sha256 companion, and verify the checksum.
#
# Usage: fetch.sh <url> <dest-dir>
#
# Prints the downloaded file's path. On any failure both files are removed
# and the script exits non-zero. A file already present that verifies is
# reused.
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

if ! verify; then
    cleanup
    if ! curl -fsSL --retry 3 -o "$sum" "$url.sha256" \
        || ! curl -fsSL --retry 3 -o "$file" "$url" \
        || ! verify; then
        cleanup
        die "download or checksum failed: $url"
    fi
fi

echo "$file"
