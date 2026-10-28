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
