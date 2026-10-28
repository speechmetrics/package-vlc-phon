#!/usr/bin/env bash
# Publish one package zip to GitHub Packages unless that version exists.
#
# Usage: publish.sh <artifact-id> <version> <zip>
# Env:   GITHUB_ACTOR, GITHUB_TOKEN (needs packages: write)
#
# Re-running after a partly failed publish skips what is already there.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

artifact="$1"
version="$2"
zip="$3"
repo_url="https://maven.pkg.github.com/speechmetrics/package-vlc-phon"
pom_url="$repo_url/org/videolan/$artifact/$version/$artifact-$version.pom"

: "${GITHUB_ACTOR:?}" "${GITHUB_TOKEN:?}"
[ -f "$zip" ] || die "no such file: $zip"

code=$(curl -s -o /dev/null -w '%{http_code}' -u "$GITHUB_ACTOR:$GITHUB_TOKEN" "$pom_url")
case "$code" in
    200)
        echo "SKIP $artifact $version already published"
        exit 0
        ;;
    404) ;;
    *) die "unexpected HTTP $code checking $pom_url" ;;
esac

settings=$(mktemp)
trap 'rm -f "$settings"' EXIT
cat > "$settings" <<XML
<settings>
  <servers>
    <server>
      <id>github</id>
      <username>$GITHUB_ACTOR</username>
      <password>$GITHUB_TOKEN</password>
    </server>
  </servers>
</settings>
XML

mvn -B -q -s "$settings" deploy:deploy-file \
    -DgroupId=org.videolan \
    -DartifactId="$artifact" \
    -Dversion="$version" \
    -Dpackaging=zip \
    -Dfile="$zip" \
    -DrepositoryId=github \
    -Durl="$repo_url"

echo "PUBLISHED $artifact $version"
