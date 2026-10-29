#!/usr/bin/env bash
# Shared helpers for the packaging scripts.

die() {
    echo "error: $*" >&2
    exit 1
}

# Print the entries of a list file: one per line, with comments (#),
# surrounding whitespace and blank lines removed.
read_list() {
    sed -e 's/#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1" | grep -v '^$' || true
}

# Download a VLC release file through VideoLAN's mirror redirector and
# verify it against the checksum on VideoLAN's own server. Prints the path.
# Usage: fetch_vlc <vlc-version> <path-under-version> <dest-dir>
fetch_vlc() {
    "$(dirname "${BASH_SOURCE[0]}")/fetch.sh" \
        "https://get.videolan.org/vlc/$1/$2" "$3" \
        "https://download.videolan.org/pub/videolan/vlc/$1/$2.sha256"
}
