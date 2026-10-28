#!/usr/bin/env bash
# Check, and where needed fix, the VLC binaries of a macOS package.
#
# Usage: verify-macos.sh <MacOS-dir>     (the folder holding lib/ and plugins/)
#
# Every Mach-O file under lib/ and plugins/ must contain arm64 and x86_64.
# Between lib/ files, references to libvlc or libvlccore must be
# @loader_path/<name>.dylib; from plug-ins, @rpath/<name>.dylib (unversioned);
# others are rewritten accordingly and the file is re-signed
# ad hoc so it stays loadable until install4j signs it. Any other reference
# outside /usr/lib and /System must not be an absolute path. Prints a FIXED
# line per change and exits non-zero if any file is not universal or has
# an absolute reference.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

dir="$1"
[ -d "$dir/lib" ] && [ -d "$dir/plugins" ] || die "$dir must contain lib/ and plugins/"

# Unversioned VLC library name for a reference, or nothing if the
# reference is not to libvlc/libvlccore.
vlc_name() {
    basename "$1" | sed -n -E 's/^(libvlc|libvlccore)(\.[0-9]+)?\.dylib$/\1.dylib/p'
}

bad=0
while IFS= read -r f; do
    kind=$(file -b "$f")
    [[ "$kind" == *Mach-O* ]] || continue

    archs=" $(lipo -archs "$f") "
    if [[ "$archs" != *" arm64 "* || "$archs" != *" x86_64 "* ]]; then
        echo "NOT UNIVERSAL $f ($(echo $archs))"
        bad=1
        continue
    fi

    changed=0
    id=$(otool -D "$f" | sed -n 2p)
    case "$f" in
        "$dir/lib/"*)
            want="@rpath/$(basename "$f")"
            if [ -n "$id" ] && [ "$id" != "$want" ]; then
                install_name_tool -id "$want" "$f" 2>/dev/null
                echo "FIXED $f id $id -> $want"
                id="$want"
                changed=1
            fi
            ;;
    esac

    while IFS= read -r dep; do
        [ -z "$dep" ] || [ "$dep" = "$id" ] && continue
        name=$(vlc_name "$dep")
        if [ -z "$name" ]; then
            case "$dep" in
                @*|/usr/lib/*|/System/*) ;;
                *) echo "ABSOLUTE PATH $f $dep"; bad=1 ;;
            esac
            continue
        fi
        case "$f" in
            "$dir/lib/"*)
                # The core libraries carry no rpath, and JNA loads libvlc by
                # full path: libvlc must find libvlccore beside itself.
                want="@loader_path/$name"
                [ "$dep" = "$want" ] && continue
                ;;
            *)
                # Plug-ins are loaded by libvlccore, which is then already
                # loaded under its @rpath install name.
                want="@rpath/$name"
                case "$dep" in
                    "@rpath/$name"|"@loader_path/../lib/$name") continue ;;
                esac
                ;;
        esac
        install_name_tool -change "$dep" "$want" "$f" 2>/dev/null
        echo "FIXED $f $dep -> $want"
        changed=1
    done < <(otool -L "$f" | awk '/^[[:space:]]/ { print $1 }' | sort -u)

    if [ "$changed" = 1 ]; then
        codesign --force -s - "$f" 2>/dev/null
    fi
done < <(find "$dir/lib" "$dir/plugins" -type f)

exit "$bad"
