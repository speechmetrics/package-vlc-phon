#!/usr/bin/env bash
# Apply a keep list and a remove list to a VLC plug-in folder.
#
# Usage: trim-plugins.sh --mode flat|category <plugins-dir> <keep-list> <remove-list>
#
# flat:     list entries are file names directly inside <plugins-dir> (macOS)
# category: list entries are sub-folder names inside <plugins-dir> (Windows)
#
# Prints one report line per item: REMOVED, KEPT, UNCLASSIFIED (on neither
# list, kept) or WARNING missing (listed but not present).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

[ "${1:-}" = "--mode" ] || die "usage: trim-plugins.sh --mode flat|category <plugins-dir> <keep-list> <remove-list>"
mode="$2"
plugins_dir="$3"
keep_list="$4"
remove_list="$5"

case "$mode" in
    flat) find_type=f ;;
    category) find_type=d ;;
    *) die "unknown mode '$mode'" ;;
esac
[ -d "$plugins_dir" ] || die "no such folder: $plugins_dir"

keep=$(read_list "$keep_list")
remove=$(read_list "$remove_list")

# in_list <name> <newline-separated list>
in_list() {
    local entry
    while IFS= read -r entry; do
        [ "$entry" = "$1" ] && return 0
    done <<< "$2"
    return 1
}

while IFS= read -r name; do
    [ -n "$name" ] || continue
    if in_list "$name" "$remove"; then
        die "on both keep and remove lists: $name"
    fi
done <<< "$keep"

present=$(find "$plugins_dir" -mindepth 1 -maxdepth 1 -type "$find_type" -exec basename {} \; | LC_ALL=C sort)

while IFS= read -r name; do
    [ -n "$name" ] || continue
    if in_list "$name" "$remove"; then
        if [ "$mode" = category ]; then
            # Name every plug-in removed with its category.
            while IFS= read -r plugin; do
                [ -n "$plugin" ] && echo "REMOVED $name/$plugin"
            done < <(find "$plugins_dir/$name" -type f -exec basename {} \; | LC_ALL=C sort)
        fi
        rm -rf "${plugins_dir:?}/$name"
        echo "REMOVED $name"
    elif in_list "$name" "$keep"; then
        echo "KEPT $name"
    else
        echo "UNCLASSIFIED $name"
    fi
done <<< "$present"

while IFS= read -r name; do
    [ -n "$name" ] || continue
    in_list "$name" "$present" || echo "WARNING missing $name"
done <<< "$keep
$remove"
