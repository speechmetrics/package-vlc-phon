#!/usr/bin/env bash
# Draft the plug-in keep/remove lists from a VLC release (macOS only).
#
# Usage: seed-lists.sh <vlc-version> <out-dir>
#
# Writes <out-dir>/{windows,macos}-{keep,remove}.txt and
# <out-dir>/macos-unmatched.txt. Windows lists come from the plug-in
# category folders. Each Mac plug-in takes the category of the Windows
# plug-in with the same base name; Mac-only plug-ins go to
# macos-unmatched.txt for hand placement. Non-universal Mac plug-ins are
# left out: package-macos.sh removes them by rule.
#
# Also refreshes licenses/{COPYING,AUTHORS}.txt from the Windows release,
# because the macOS disk image carries no licence files.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

KEEP_CATEGORIES="access demux codec packetizer audio_output audio_filter audio_mixer video_output video_chroma video_filter stream_filter misc text_renderer spu meta_engine logger d3d9 d3d11"
REMOVE_CATEGORIES="gui control lua services_discovery stream_out access_output mux visualization keystore video_splitter stream_extractor"

v="$1"
out="$2"
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$out"
work=$(mktemp -d)
mnt="$work/mnt"
trap 'hdiutil detach -quiet "$mnt" 2>/dev/null || true; rm -rf "$work"' EXIT

dl="${DOWNLOAD_DIR:-$here/../build/dl}"
win_zip=$("$here/fetch.sh" "https://get.videolan.org/vlc/$v/win64/vlc-$v-win64.zip" "$dl")
dmg=$("$here/fetch.sh" "https://get.videolan.org/vlc/$v/macosx/vlc-$v-universal.dmg" "$dl")

# category <TAB> plug-in base name, from the Windows release
unzip -Z1 "$win_zip" \
    | sed -n "s#^vlc-$v/plugins/\([^/]*\)/\([^/]*\)\.dll\$#\1	\2#p" \
    | sort -u > "$work/win.tsv"

unzip -p "$win_zip" "vlc-$v/COPYING.txt" > "$here/../licenses/COPYING.txt"
unzip -p "$win_zip" "vlc-$v/AUTHORS.txt" > "$here/../licenses/AUTHORS.txt"

classify() {
    case " $KEEP_CATEGORIES " in *" $1 "*) echo keep; return ;; esac
    case " $REMOVE_CATEGORIES " in *" $1 "*) echo remove; return ;; esac
    echo unknown
}

: > "$out/windows-keep.txt"
: > "$out/windows-remove.txt"
for c in $(cut -f1 "$work/win.tsv" | sort -u); do
    case $(classify "$c") in
        keep) echo "$c" >> "$out/windows-keep.txt" ;;
        remove) echo "$c" >> "$out/windows-remove.txt" ;;
        *) echo "unknown category: $c" >&2 ;;
    esac
done

hdiutil attach -nobrowse -readonly -mountpoint "$mnt" "$dmg" >/dev/null
: > "$out/macos-keep.txt"
: > "$out/macos-remove.txt"
: > "$out/macos-unmatched.txt"
for f in "$mnt"/VLC.app/Contents/MacOS/plugins/*.dylib; do
    name=$(basename "$f")
    archs=$(lipo -archs "$f")
    case "$archs" in *arm64*x86_64*|*x86_64*arm64*) ;; *) continue ;; esac
    c=$(awk -F'\t' -v n="${name%.dylib}" '$2 == n { print $1 }' "$work/win.tsv")
    if [ -z "$c" ]; then
        echo "$name" >> "$out/macos-unmatched.txt"
        continue
    fi
    case $(classify "$c") in
        keep) printf '%s\t%s\n' "$c" "$name" >> "$out/macos-keep.txt" ;;
        remove) printf '%s\t%s\n' "$c" "$name" >> "$out/macos-remove.txt" ;;
    esac
done
