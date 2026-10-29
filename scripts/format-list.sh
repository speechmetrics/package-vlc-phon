#!/usr/bin/env bash
# Write a plug-in list file from "category<TAB>name" lines.
#
# Usage: format-list.sh <header-file> <tsv-file>
#
# Prints the header, then each category as a "# <category>" comment
# followed by its names, both sorted.
set -euo pipefail

cat "$1"
LC_ALL=C sort -t "$(printf '\t')" -k1,1 -k2,2 "$2" \
    | awk -F'\t' '$1 != prev { printf "\n# %s\n", $1; prev = $1 } { print $2 }'
