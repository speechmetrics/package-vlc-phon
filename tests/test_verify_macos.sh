#!/usr/bin/env bash
# Tests for scripts/verify-macos.sh (macOS only).
source "$(dirname "$0")/helpers.sh"
VERIFY="$REPO_ROOT/scripts/verify-macos.sh"

if [ "$(uname)" != Darwin ]; then
    echo "  skipped: needs macOS"
    exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
src="$tmp/src"
mkdir -p "$src"
echo 'int vlc_core(void) { return 1; }' > "$src/core.c"
echo 'int vlc_core(void); int plugin(void) { return vlc_core(); }' > "$src/plugin.c"

universal="-arch arm64 -arch x86_64"

# MacOS/{lib,plugins}: core with an absolute install name, plug-in linked to it
m="$tmp/good/MacOS"
mkdir -p "$m/lib" "$m/plugins"
clang -dynamiclib $universal -install_name "$m/lib/libvlccore.dylib" \
    -o "$m/lib/libvlccore.dylib" "$src/core.c"
clang -dynamiclib $universal -o "$m/plugins/libfoo_plugin.dylib" "$src/plugin.c" "$m/lib/libvlccore.dylib"

out=$(bash "$VERIFY" "$m")
assert_eq 0 $? "verify exit status"
assert_contains "$out" "FIXED" "reports fixes"
deps=$(otool -L "$m/plugins/libfoo_plugin.dylib")
assert_contains "$deps" "@rpath/libvlccore.dylib" "plug-in dependency rewritten"
assert_not_contains "$deps" "$m/lib/libvlccore.dylib" "absolute path gone"
assert_eq "@rpath/libvlccore.dylib" "$(otool -D "$m/lib/libvlccore.dylib" | tail -1)" "core install name rewritten"
codesign -v "$m/plugins/libfoo_plugin.dylib" 2>/dev/null || fail "plug-in signature invalid after fix"
codesign -v "$m/lib/libvlccore.dylib" 2>/dev/null || fail "core signature invalid after fix"

# already clean: nothing to fix
out=$(bash "$VERIFY" "$m")
assert_not_contains "$out" "FIXED" "second run has nothing to fix"

# an arm64-only plug-in fails verification
b="$tmp/bad/MacOS"
mkdir -p "$b/lib" "$b/plugins"
cp "$m/lib/libvlccore.dylib" "$b/lib/"
clang -dynamiclib -arch arm64 -o "$b/plugins/libarm_plugin.dylib" "$src/plugin.c" "$b/lib/libvlccore.dylib"
assert_fails bash "$VERIFY" "$b"

finish
