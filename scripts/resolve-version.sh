#!/usr/bin/env bash
# Resolve the Maven version and the VLC version to package.
#
# Usage: resolve-version.sh [<tag>]
#
# With a tag v<vlc> or v<vlc>-<n>, the Maven version is the tag without the
# leading "v" and the VLC version is the part before "-<n>"; the VLC version
# must match the VLC_VERSION file. Without a tag both are the VLC_VERSION
# file's value. Prints MAVEN_VERSION=... and VLC_VERSION=... lines.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

version_file="${VLC_VERSION_FILE:-$(dirname "$0")/../VLC_VERSION}"
file_version=$(tr -d '[:space:]' < "$version_file")

tag="${1:-}"
if [ -z "$tag" ]; then
    maven_version="$file_version"
    vlc_version="$file_version"
else
    [[ "$tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)(-[0-9]+)?$ ]] || die "tag '$tag' is not v<x.y.z> or v<x.y.z>-<n>"
    vlc_version="${BASH_REMATCH[1]}"
    maven_version="${tag#v}"
    [ "$vlc_version" = "$file_version" ] || die "tag '$tag' is for VLC $vlc_version but VLC_VERSION is $file_version"
fi

echo "MAVEN_VERSION=$maven_version"
echo "VLC_VERSION=$vlc_version"
