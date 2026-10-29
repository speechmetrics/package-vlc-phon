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
assert_not_contains "$out" "FIXED $m/lib/libvlccore.dylib @rpath/libvlccore.dylib" "own install name not treated as a dependency"
deps=$(otool -L "$m/plugins/libfoo_plugin.dylib")
assert_contains "$deps" "@rpath/libvlccore.dylib" "plug-in dependency rewritten"
assert_not_contains "$deps" "$m/lib/libvlccore.dylib" "absolute path gone"
assert_eq "@rpath/libvlccore.dylib" "$(otool -D "$m/lib/libvlccore.dylib" | tail -1)" "core install name rewritten"
codesign -v "$m/plugins/libfoo_plugin.dylib" 2>/dev/null || fail "plug-in signature invalid after fix"
codesign -v "$m/lib/libvlccore.dylib" 2>/dev/null || fail "core signature invalid after fix"

# already clean: nothing to fix
out=$(bash "$VERIFY" "$m")
assert_not_contains "$out" "FIXED" "second run has nothing to fix"

# libvlc must load libvlccore from its own folder: an @rpath reference
# between the core libraries is rewritten to @loader_path
r="$tmp/rpath/MacOS"
mkdir -p "$r/lib" "$r/plugins"
clang -dynamiclib $universal -install_name @rpath/libvlccore.dylib -o "$r/lib/libvlccore.dylib" "$src/core.c"
clang -dynamiclib $universal -install_name @rpath/libvlc.dylib -o "$r/lib/libvlc.dylib" "$src/plugin.c" "$r/lib/libvlccore.dylib"
out=$(bash "$VERIFY" "$r")
assert_contains "$out" "FIXED $r/lib/libvlc.dylib @rpath/libvlccore.dylib -> @loader_path/libvlccore.dylib" "core reference fixed"
assert_contains "$(otool -L "$r/lib/libvlc.dylib")" "@loader_path/libvlccore.dylib" "libvlc loads libvlccore from its folder"
codesign -v "$r/lib/libvlc.dylib" 2>/dev/null || fail "libvlc signature invalid after fix"
cat > "$tmp/load.c" <<'C'
#include <dlfcn.h>
#include <stdio.h>
int main(int argc, char **argv) {
    if (!dlopen(argv[1], RTLD_NOW)) { fprintf(stderr, "%s\n", dlerror()); return 1; }
    puts("loads");
    return 0;
}
C
clang -o "$tmp/load" "$tmp/load.c"
assert_eq "loads" "$("$tmp/load" "$r/lib/libvlc.dylib" 2>&1)" "libvlc loads by full path without an rpath"

# a reference to a non-system library by absolute path fails verification
a="$tmp/abs/MacOS"
mkdir -p "$a/lib" "$a/plugins" "$tmp/elsewhere"
cp "$m/lib/libvlccore.dylib" "$a/lib/"
echo 'int helper(void) { return 2; }' > "$src/helper.c"
clang -dynamiclib $universal -install_name "$tmp/elsewhere/libhelper.dylib" -o "$tmp/elsewhere/libhelper.dylib" "$src/helper.c"
clang -dynamiclib $universal -o "$a/plugins/libabs_plugin.dylib" "$src/plugin.c" "$a/lib/libvlccore.dylib" "$tmp/elsewhere/libhelper.dylib"
out=$(bash "$VERIFY" "$a")
assert_eq 1 $? "absolute reference exit status"
assert_contains "$out" "ABSOLUTE PATH $a/plugins/libabs_plugin.dylib $tmp/elsewhere/libhelper.dylib" "absolute reference reported"

# an arm64-only plug-in fails verification
b="$tmp/bad/MacOS"
mkdir -p "$b/lib" "$b/plugins"
cp "$m/lib/libvlccore.dylib" "$b/lib/"
clang -dynamiclib -arch arm64 -o "$b/plugins/libarm_plugin.dylib" "$src/plugin.c" "$b/lib/libvlccore.dylib"
assert_fails bash "$VERIFY" "$b"

finish
