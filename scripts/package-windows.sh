#!/usr/bin/env bash
# Build the trimmed Windows VLC package.
#
# Usage: package-windows.sh <maven-version> <vlc-version> <out-dir>
#
# Produces <out-dir>/vlc-windows-x64-<maven-version>.zip (layout VLC/...)
# and <out-dir>/vlc-windows-x64-<maven-version>.trim.txt.
# The trim report is also written to stderr. Fails if licenses/ differs
# from the release's licence files (re-run seed-lists.sh after a bump).
# Env: VLC_WIN_ZIP   use this release zip instead of downloading it
#      LISTS_DIR     folder holding windows-{keep,remove}.txt
#      LICENSES_DIR  folder holding COPYING.txt and AUTHORS.txt
set -euo pipefail
source "$(dirname "$0")/lib.sh"

maven_version="$1"
vlc_version="$2"
out="$3"
here="$(cd "$(dirname "$0")" && pwd)"
lists="${LISTS_DIR:-$here/../lists}"
licenses="${LICENSES_DIR:-$here/../licenses}"
name="vlc-windows-x64-$maven_version"
mkdir -p "$out"
rm -f "$out/$name.zip" "$out/$name.trim.txt"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

release_zip="${VLC_WIN_ZIP:-}"
if [ -z "$release_zip" ]; then
    release_zip=$(fetch_vlc "$vlc_version" "win64/vlc-$vlc_version-win64.zip" "${DOWNLOAD_DIR:-$work/dl}")
fi

unzip -q "$release_zip" -d "$work/src"
src="$work/src/vlc-$vlc_version"
[ -d "$src" ] || die "release zip has no vlc-$vlc_version/ folder"

stage="$work/stage/VLC"
mkdir -p "$stage"
for f in libvlc.dll libvlccore.dll COPYING.txt AUTHORS.txt; do
    [ -f "$src/$f" ] || die "release zip lacks $f"
    cp "$src/$f" "$stage/"
done
for f in COPYING.txt AUTHORS.txt; do
    cmp -s "$src/$f" "$licenses/$f" \
        || die "$licenses/$f differs from VLC $vlc_version's; re-run scripts/seed-lists.sh"
done
cp -R "$src/plugins" "$stage/plugins"
rm -f "$stage/plugins/plugins.dat"
sed "s/@VLC_VERSION@/$vlc_version/g" "$here/../templates/README.txt" > "$stage/README.txt"

report="$work/$name.trim.txt"
"$here/trim-plugins.sh" --mode category "$stage/plugins" \
    "$lists/windows-keep.txt" "$lists/windows-remove.txt" | tee "$report" >&2

out_abs="$(cd "$out" && pwd)"
(cd "$work/stage" && zip -qrX "$work/$name.zip" VLC)
mv "$work/$name.zip" "$report" "$out_abs/"

echo "$out_abs/$name.zip"
