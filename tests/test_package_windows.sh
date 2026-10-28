#!/usr/bin/env bash
# Tests for scripts/package-windows.sh.
source "$(dirname "$0")/helpers.sh"
PACKAGE="$REPO_ROOT/scripts/package-windows.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# fixture release zip
r="$tmp/src/vlc-3.0.24"
mkdir -p "$r/plugins/codec" "$r/plugins/gui" "$r/msi"
for f in libvlc.dll libvlccore.dll axvlc.dll npvlc.dll vlc.exe COPYING.txt AUTHORS.txt NEWS.txt msi/LICENSE.rtf \
         plugins/plugins.dat plugins/codec/x.dll plugins/gui/y.dll; do
    echo "$f" > "$r/$f"
done
(cd "$tmp/src" && zip -qr "$tmp/vlc-3.0.24-win64.zip" vlc-3.0.24)

mkdir -p "$tmp/lists" "$tmp/licenses"
echo codec > "$tmp/lists/windows-keep.txt"
echo gui > "$tmp/lists/windows-remove.txt"
cp "$r/COPYING.txt" "$r/AUTHORS.txt" "$tmp/licenses/"
export VLC_WIN_ZIP="$tmp/vlc-3.0.24-win64.zip" LICENSES_DIR="$tmp/licenses"

out=$(LISTS_DIR="$tmp/lists" bash "$PACKAGE" 3.0.24-2 3.0.24 "$tmp/out" 2> "$tmp/stderr")
assert_eq 0 $? "package exit status"
assert_contains "$(cat "$tmp/stderr")" "REMOVED gui" "trim report shown in the log"

zip="$tmp/out/vlc-windows-x64-3.0.24-2.zip"
assert_file "$zip"
assert_file "$tmp/out/vlc-windows-x64-3.0.24-2.trim.txt"

files=$(unzip -Z1 "$zip" | grep -v '/$' | LC_ALL=C sort | tr '\n' ' ')
assert_eq "VLC/AUTHORS.txt VLC/COPYING.txt VLC/README.txt VLC/libvlc.dll VLC/libvlccore.dll VLC/plugins/codec/x.dll " \
    "$files" "zip contents"

readme=$(unzip -p "$zip" VLC/README.txt)
assert_contains "$readme" "3.0.24" "README names VLC version"
assert_contains "$readme" "https://code.videolan.org/videolan/vlc/-/tree/3.0.24" "README links source"

assert_contains "$(cat "$tmp/out/vlc-windows-x64-3.0.24-2.trim.txt")" "REMOVED gui" "trim report"

# licence files in the repository must match the release
echo "changed" > "$tmp/licenses/AUTHORS.txt"
assert_fails env LISTS_DIR="$tmp/lists" bash "$PACKAGE" 3.0.24 3.0.24 "$tmp/out-lic"
cp "$r/AUTHORS.txt" "$tmp/licenses/"

# a failed build leaves no zip or report behind, not even an older one
mkdir -p "$tmp/out-fail" "$tmp/badlists"
touch "$tmp/out-fail/vlc-windows-x64-3.0.24.zip" "$tmp/out-fail/vlc-windows-x64-3.0.24.trim.txt"
echo codec > "$tmp/badlists/windows-keep.txt"
echo codec > "$tmp/badlists/windows-remove.txt"
assert_fails env LISTS_DIR="$tmp/badlists" bash "$PACKAGE" 3.0.24 3.0.24 "$tmp/out-fail"
assert_no_file "$tmp/out-fail/vlc-windows-x64-3.0.24.zip"
assert_no_file "$tmp/out-fail/vlc-windows-x64-3.0.24.trim.txt"

finish
