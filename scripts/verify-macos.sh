#!/usr/bin/env bash
# Check, and where needed fix, the VLC binaries of a macOS package.
#
# Usage: verify-macos.sh <MacOS-dir>     (the folder holding lib/ and plugins/)
#
# Every Mach-O file under lib/ and plugins/ must contain arm64 and x86_64.
# References to libvlc or libvlccore must be @rpath/<name>.dylib or
# @loader_path/<name>.dylib with the unversioned name the package ships;
# others are rewritten to @rpath/<name>.dylib and the file is re-signed
# ad hoc so it stays loadable until install4j signs it. Prints a FIXED
# line per change and exits non-zero if any file is not universal.
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
    file -b "$f" | grep -q 'Mach-O' || continue

    archs=$(lipo -archs "$f")
    case " $archs " in
        *" arm64 "*) ;;
        *) echo "NOT UNIVERSAL $f ($archs)"; bad=1; continue ;;
    esac
    case " $archs " in
        *" x86_64 "*) ;;
        *) echo "NOT UNIVERSAL $f ($archs)"; bad=1; continue ;;
    esac

    changed=0
    id=$(otool -D "$f" | tail -n +2 | head -1)
    case "$f" in
        "$dir/lib/"*)
            want="@rpath/$(basename "$f")"
            if [ -n "$id" ] && [ "$id" != "$want" ]; then
                install_name_tool -id "$want" "$f" 2>/dev/null
                echo "FIXED $f id $id -> $want"
                changed=1
            fi
            ;;
    esac

    deps=$(otool -L "$f" | grep -E '^[[:space:]]' | awk '{print $1}' | sort -u)
    for dep in $deps; do
        [ "$dep" = "$id" ] && continue
        name=$(vlc_name "$dep")
        [ -n "$name" ] || continue
        case "$dep" in
            "@rpath/$name"|"@loader_path/$name") continue ;;
        esac
        install_name_tool -change "$dep" "@rpath/$name" "$f" 2>/dev/null
        echo "FIXED $f $dep -> @rpath/$name"
        changed=1
    done

    if [ "$changed" = 1 ]; then
        codesign --force -s - "$f" 2>/dev/null
    fi
done < <(find "$dir/lib" "$dir/plugins" -type f)

exit "$bad"
