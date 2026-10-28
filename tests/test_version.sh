#!/usr/bin/env bash
# Tests for scripts/resolve-version.sh.
source "$(dirname "$0")/helpers.sh"
RESOLVE="$REPO_ROOT/scripts/resolve-version.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo 3.0.24 > "$tmp/VLC_VERSION"
export VLC_VERSION_FILE="$tmp/VLC_VERSION"

out=$(bash "$RESOLVE" v3.0.24)
assert_eq "MAVEN_VERSION=3.0.24
VLC_VERSION=3.0.24" "$out" "plain tag"

out=$(bash "$RESOLVE" v3.0.24-2)
assert_eq "MAVEN_VERSION=3.0.24-2
VLC_VERSION=3.0.24" "$out" "rebuild tag"

out=$(bash "$RESOLVE")
assert_eq "MAVEN_VERSION=3.0.24
VLC_VERSION=3.0.24" "$out" "no tag uses VLC_VERSION file"

assert_fails bash "$RESOLVE" v3.0.25
assert_fails bash "$RESOLVE" 3.0.24
assert_fails bash "$RESOLVE" vfoo
assert_fails bash "$RESOLVE" v3.0.24-0
assert_fails bash "$RESOLVE" v3.0.24-02

finish
