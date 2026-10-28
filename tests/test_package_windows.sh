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

mkdir -p "$tmp/lists"
echo codec > "$tmp/lists/windows-keep.txt"
echo gui > "$tmp/lists/windows-remove.txt"

out=$(VLC_WIN_ZIP="$tmp/vlc-3.0.24-win64.zip" LISTS_DIR="$tmp/lists" \
    bash "$PACKAGE" 3.0.24-2 3.0.24 "$tmp/out")
assert_eq 0 $? "package exit status"

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

finish
