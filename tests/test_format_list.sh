#!/usr/bin/env bash
# Tests for scripts/format-list.sh.
source "$(dirname "$0")/helpers.sh"
FORMAT="$REPO_ROOT/scripts/format-list.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf 'video_output\tb.dylib\ncodec\tz.dylib\ncodec\ta.dylib\n' > "$tmp/in.tsv"
printf '# header line\n' > "$tmp/header"

out=$(bash "$FORMAT" "$tmp/header" "$tmp/in.tsv")
expected='# header line

# codec
a.dylib
z.dylib

# video_output
b.dylib'
assert_eq "$expected" "$out" "grouped by category, sorted"

# the result reads back as bare names
source "$REPO_ROOT/scripts/lib.sh"
printf '%s\n' "$out" > "$tmp/list.txt"
assert_eq "a.dylib z.dylib b.dylib" "$(read_list "$tmp/list.txt" | tr '\n' ' ' | sed 's/ $//')" "reads back as names"

finish
