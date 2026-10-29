#!/usr/bin/env bash
# Build the trimmed universal macOS VLC package (macOS only).
#
# Usage: package-macos.sh <maven-version> <vlc-version> <out-dir>
#
# Produces <out-dir>/vlc-macos-<maven-version>.zip (layout
# VLC.app/Contents/MacOS/{lib,plugins}) and <out-dir>/vlc-macos-<maven-version>.trim.txt.
# The trim and verify report is also written to stderr.
# Env: VLC_MAC_APP   use this VLC.app instead of downloading the disk image
#      LISTS_DIR     folder holding macos-{keep,remove}.txt
#      LICENSES_DIR  folder holding COPYING.txt and AUTHORS.txt
set -euo pipefail
source "$(dirname "$0")/lib.sh"

maven_version="$1"
vlc_version="$2"
out="$3"
here="$(cd "$(dirname "$0")" && pwd)"
lists="${LISTS_DIR:-$here/../lists}"
licenses="${LICENSES_DIR:-$here/../licenses}"
name="vlc-macos-$maven_version"
mkdir -p "$out"
rm -f "$out/$name.zip" "$out/$name.trim.txt"

work=$(mktemp -d)
mnt="$work/mnt"
trap 'hdiutil detach -quiet "$mnt" 2>/dev/null || true; rm -rf "$work"' EXIT

app="${VLC_MAC_APP:-}"
if [ -z "$app" ]; then
    dmg=$(fetch_vlc "$vlc_version" "macosx/vlc-$vlc_version-universal.dmg" "${DOWNLOAD_DIR:-$work/dl}")
    mkdir -p "$mnt"
    hdiutil attach -nobrowse -readonly -mountpoint "$mnt" "$dmg" >/dev/null
    app="$mnt/VLC.app"
fi
src="$app/Contents/MacOS"
[ -d "$src/lib" ] && [ -d "$src/plugins" ] || die "$src lacks lib/ or plugins/"

stage="$work/stage/VLC.app/Contents/MacOS"
mkdir -p "$stage/lib" "$stage/plugins"
# Copy the libraries under their unversioned names as real files.
for lib in libvlc.dylib libvlccore.dylib; do
    cp -L "$src/lib/$lib" "$stage/lib/$lib"
done
cp "$src/plugins/"*.dylib "$stage/plugins/"

report="$work/$name.trim.txt"
: > "$report"
for f in "$stage/plugins/"*.dylib; do
    archs=" $(lipo -archs "$f") "
    if [[ "$archs" != *" arm64 "* || "$archs" != *" x86_64 "* ]]; then
        rm -f "$f"
        echo "REMOVED $(basename "$f") (not universal)" | tee -a "$report" >&2
    fi
done
"$here/trim-plugins.sh" --mode flat "$stage/plugins" \
    "$lists/macos-keep.txt" "$lists/macos-remove.txt" | tee -a "$report" >&2
"$here/verify-macos.sh" "$stage" | tee -a "$report" >&2

cp "$licenses/COPYING.txt" "$licenses/AUTHORS.txt" "$stage/"
sed "s/@VLC_VERSION@/$vlc_version/g" "$here/../templates/README.txt" > "$stage/README.txt"

out_abs="$(cd "$out" && pwd)"
(cd "$work/stage" && zip -qrX "$work/$name.zip" VLC.app)
mv "$work/$name.zip" "$report" "$out_abs/"

echo "$out_abs/$name.zip"
