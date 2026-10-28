#!/usr/bin/env bash
# Tests for scripts/package-macos.sh (macOS only).
source "$(dirname "$0")/helpers.sh"
PACKAGE="$REPO_ROOT/scripts/package-macos.sh"

if [ "$(uname)" != Darwin ]; then
    echo "  skipped: needs macOS"
    exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
src="$tmp/src"
mkdir -p "$src"
echo 'int vlc_core(void) { return 1; }' > "$src/core.c"
echo 'int vlc_core(void); int other(void) { return vlc_core(); }' > "$src/other.c"
universal="-arch arm64 -arch x86_64"

# fixture VLC.app laid out like the VideoLAN disk image
m="$tmp/VLC.app/Contents/MacOS"
mkdir -p "$m/lib" "$m/plugins"
clang -dynamiclib $universal -install_name @rpath/libvlccore.dylib -o "$m/lib/libvlccore.9.dylib" "$src/core.c"
ln -s libvlccore.9.dylib "$m/lib/libvlccore.dylib"
clang -dynamiclib $universal -install_name @rpath/libvlc.dylib -o "$m/lib/libvlc.5.dylib" "$src/other.c" "$m/lib/libvlccore.9.dylib"
ln -s libvlc.5.dylib "$m/lib/libvlc.dylib"
for p in keep remove; do
    clang -dynamiclib $universal -o "$m/plugins/lib${p}_plugin.dylib" "$src/other.c" "$m/lib/libvlccore.9.dylib"
done
clang -dynamiclib -arch x86_64 -o "$m/plugins/libintel_plugin.dylib" "$src/other.c" "$m/lib/libvlccore.9.dylib"
echo jar > "$m/plugins/libbluray-j2se-1.4.1.jar"
echo cache > "$m/plugins/plugins.dat"

mkdir -p "$tmp/lists"
echo libkeep_plugin.dylib > "$tmp/lists/macos-keep.txt"
echo libremove_plugin.dylib > "$tmp/lists/macos-remove.txt"

out=$(VLC_MAC_APP="$tmp/VLC.app" LISTS_DIR="$tmp/lists" bash "$PACKAGE" 3.0.24 3.0.24 "$tmp/out" 2> "$tmp/stderr")
assert_eq 0 $? "package exit status"
assert_contains "$(cat "$tmp/stderr")" "REMOVED libremove_plugin.dylib" "trim report shown in the log"

zip="$tmp/out/vlc-macos-3.0.24.zip"
assert_file "$zip"
p=VLC.app/Contents/MacOS
files=$(unzip -Z1 "$zip" | grep -v '/$' | LC_ALL=C sort | tr '\n' ' ')
assert_eq "$p/AUTHORS.txt $p/COPYING.txt $p/README.txt $p/lib/libvlc.dylib $p/lib/libvlccore.dylib $p/plugins/libkeep_plugin.dylib " \
    "$files" "zip contents"
assert_eq "" "$(zipinfo "$zip" | grep '^l' || true)" "no symlinks in zip"
assert_not_contains "$(unzip -Z1 "$zip")" "__MACOSX" "no __MACOSX entries"
assert_not_contains "$(unzip -Z1 "$zip")" "/._" "no AppleDouble entries"

report=$(cat "$tmp/out/vlc-macos-3.0.24.trim.txt")
assert_contains "$report" "REMOVED libremove_plugin.dylib" "trim report"
assert_contains "$report" "REMOVED libintel_plugin.dylib (not universal)" "non-universal removal reported"

assert_contains "$(unzip -p "$zip" $p/README.txt)" "https://code.videolan.org/videolan/vlc/-/tree/3.0.24" "README links source"

# a failed build (non-universal core library) leaves no zip or report,
# and the reason is shown in the log
clang -dynamiclib -arch arm64 -install_name @rpath/libvlccore.dylib -o "$m/lib/libvlccore.9.dylib" "$src/core.c"
mkdir -p "$tmp/out-fail"
touch "$tmp/out-fail/vlc-macos-3.0.24.zip" "$tmp/out-fail/vlc-macos-3.0.24.trim.txt"
err=$(VLC_MAC_APP="$tmp/VLC.app" LISTS_DIR="$tmp/lists" bash "$PACKAGE" 3.0.24 3.0.24 "$tmp/out-fail" 2>&1)
assert_fails test -z "$err"
assert_contains "$err" "NOT UNIVERSAL" "failure reason shown in the log"
assert_no_file "$tmp/out-fail/vlc-macos-3.0.24.zip"
assert_no_file "$tmp/out-fail/vlc-macos-3.0.24.trim.txt"

finish
