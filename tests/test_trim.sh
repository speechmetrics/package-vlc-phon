#!/usr/bin/env bash
# Tests for scripts/trim-plugins.sh.
source "$(dirname "$0")/helpers.sh"
TRIM="$REPO_ROOT/scripts/trim-plugins.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# flat mode
d="$tmp/flat"
mkdir -p "$d"
touch "$d/a.dylib" "$d/b.dylib" "$d/c.dylib" "$d/new.dylib"
printf 'a.dylib\n' > "$tmp/keep"
printf 'b.dylib\nc.dylib\ngone.dylib\n' > "$tmp/remove"
out=$(bash "$TRIM" --mode flat "$d" "$tmp/keep" "$tmp/remove")
assert_eq 0 $? "flat mode exit status"
assert_file "$d/a.dylib"
assert_file "$d/new.dylib"
assert_no_file "$d/b.dylib"
assert_no_file "$d/c.dylib"
assert_contains "$out" "REMOVED b.dylib" "flat report"
assert_contains "$out" "KEPT a.dylib" "flat report"
assert_contains "$out" "UNCLASSIFIED new.dylib" "flat report"
assert_contains "$out" "WARNING missing gone.dylib" "flat report"

# category mode
d="$tmp/cat"
for c in codec gui lua newcat; do mkdir -p "$d/$c"; touch "$d/$c/x.dll"; done
printf 'codec\n' > "$tmp/keep"
printf 'gui\nlua\n' > "$tmp/remove"
out=$(bash "$TRIM" --mode category "$d" "$tmp/keep" "$tmp/remove")
assert_file "$d/codec/x.dll"
assert_file "$d/newcat/x.dll"
assert_no_file "$d/gui"
assert_no_file "$d/lua"
assert_contains "$out" "UNCLASSIFIED newcat" "category report"
assert_contains "$out" "REMOVED gui" "category report"

# comments and blank lines are ignored
d="$tmp/comments"
mkdir -p "$d/codec" "$d/gui"
printf '# header\n\n  codec  # trailing\n' > "$tmp/keep"
printf '# remove these\ngui\n' > "$tmp/remove"
out=$(bash "$TRIM" --mode category "$d" "$tmp/keep" "$tmp/remove")
assert_file "$d/codec"
assert_no_file "$d/gui"
assert_not_contains "$out" "WARNING" "comments not read as entries"
assert_not_contains "$out" "UNCLASSIFIED" "comments not read as entries"

# a name on both lists is an error
d="$tmp/both"
mkdir -p "$d/codec"
printf 'codec\n' > "$tmp/keep"
printf 'codec\n' > "$tmp/remove"
assert_fails bash "$TRIM" --mode category "$d" "$tmp/keep" "$tmp/remove"
assert_file "$d/codec"

finish
