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

in_list() {
    printf '%s\n' "$2" | grep -Fxq -- "$1"
}

both=$(printf '%s\n' "$keep" | grep -Fx -f <(printf '%s\n' "$remove") || true)
[ -z "$both" ] || die "on both keep and remove lists: $(echo $both)"

present=$(find "$plugins_dir" -mindepth 1 -maxdepth 1 -type "$find_type" -exec basename {} \; | sort)

for name in $present; do
    if in_list "$name" "$remove"; then
        rm -rf "${plugins_dir:?}/$name"
        echo "REMOVED $name"
    elif in_list "$name" "$keep"; then
        echo "KEPT $name"
    else
        echo "UNCLASSIFIED $name"
    fi
done

for name in $keep $remove; do
    in_list "$name" "$present" || echo "WARNING missing $name"
done
