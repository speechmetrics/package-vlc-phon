#!/usr/bin/env bash
# Tests for scripts/publish.sh, with curl and mvn replaced by stubs.
source "$(dirname "$0")/helpers.sh"
PUBLISH="$REPO_ROOT/scripts/publish.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
echo zip > "$tmp/pkg.zip"

# curl stub prints $STUB_HTTP_CODE and records its arguments
cat > "$tmp/bin/curl" <<'STUB'
#!/usr/bin/env bash
echo "$@" >> "$STUB_LOG.curl"
printf '%s' "$STUB_HTTP_CODE"
STUB
# mvn stub records its arguments and the settings file it was given
cat > "$tmp/bin/mvn" <<'STUB'
#!/usr/bin/env bash
echo "$@" >> "$STUB_LOG.mvn"
for a in "$@"; do prev_s=${s:-}; s="$a"; [ "$prev_s" = "-s" ] && cp "$a" "$STUB_LOG.settings"; done
exit 0
STUB
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH" GITHUB_ACTOR=bot GITHUB_TOKEN=secret STUB_LOG="$tmp/log"

# version already published: skip without deploying
out=$(STUB_HTTP_CODE=200 bash "$PUBLISH" vlc-macos 3.0.24 "$tmp/pkg.zip")
assert_eq 0 $? "skip exit status"
assert_eq "SKIP vlc-macos 3.0.24 already published" "$out" "skip message"
assert_no_file "$tmp/log.mvn"
assert_contains "$(cat "$tmp/log.curl")" \
    "https://maven.pkg.github.com/speechmetrics/package-vlc-phon/org/videolan/vlc-macos/3.0.24/vlc-macos-3.0.24.pom" \
    "checks the POM URL"

# not yet published: deploy
rm -f "$tmp/log."*
STUB_HTTP_CODE=404 bash "$PUBLISH" vlc-windows-x64 3.0.24-2 "$tmp/pkg.zip" >/dev/null
assert_eq 0 $? "deploy exit status"
args=$(cat "$tmp/log.mvn")
assert_contains "$args" "deploy:deploy-file" "runs deploy-file"
assert_contains "$args" "-DgroupId=org.videolan" "groupId"
assert_contains "$args" "-DartifactId=vlc-windows-x64" "artifactId"
assert_contains "$args" "-Dversion=3.0.24-2" "version"
assert_contains "$args" "-Dpackaging=zip" "packaging"
assert_contains "$args" "-Dfile=$tmp/pkg.zip" "file"
assert_contains "$args" "-DrepositoryId=github" "repositoryId"
assert_contains "$args" "-Durl=https://maven.pkg.github.com/speechmetrics/package-vlc-phon" "url"
assert_contains "$(cat "$tmp/log.settings")" "<password>secret</password>" "settings carry token"

# any other answer from the registry is an error
assert_fails env STUB_HTTP_CODE=401 bash "$PUBLISH" vlc-macos 3.0.24 "$tmp/pkg.zip"

finish
