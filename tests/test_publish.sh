#!/usr/bin/env bash
# Tests for scripts/publish.sh, with curl and mvn replaced by stubs.
source "$(dirname "$0")/helpers.sh"
PUBLISH="$REPO_ROOT/scripts/publish.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

# curl stub: a HEAD-style status probe (-w) prints $STUB_HTTP_CODE and exits
# $STUB_CURL_EXIT; a download (-o <file>) writes "published zip" to <file>.
cat > "$tmp/bin/curl" <<'STUB'
#!/usr/bin/env bash
echo "$@" >> "$STUB_LOG.curl"
out=""; probe=0; prev=""
for a in "$@"; do
    [ "$prev" = "-o" ] && out="$a"
    [ "$a" = "-w" ] && probe=1
    prev="$a"
done
if [ "$probe" = 1 ]; then
    printf '%s' "$STUB_HTTP_CODE"
    exit "${STUB_CURL_EXIT:-0}"
fi
echo "published zip" > "$out"
STUB
# mvn stub records its arguments and the settings file it was given
cat > "$tmp/bin/mvn" <<'STUB'
#!/usr/bin/env bash
echo "$@" >> "$STUB_LOG.mvn"
prev=""
for a in "$@"; do [ "$prev" = "-s" ] && cp "$a" "$STUB_LOG.settings"; prev="$a"; done
exit 0
STUB
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH" GITHUB_ACTOR=bot GITHUB_TOKEN=secret STUB_LOG="$tmp/log"
repo=https://maven.pkg.github.com/speechmetrics/package-vlc-phon

# version already published (the registry redirects to its file store):
# skip the deploy and replace the local zip with the published one
for code in 200 302; do
    rm -f "$tmp/log."*
    echo "rebuilt zip" > "$tmp/pkg.zip"
    out=$(STUB_HTTP_CODE=$code bash "$PUBLISH" vlc-macos 3.0.24 "$tmp/pkg.zip")
    assert_eq 0 $? "skip exit status ($code)"
    assert_eq "SKIP vlc-macos 3.0.24 already published" "$out" "skip message ($code)"
    assert_no_file "$tmp/log.mvn"
    assert_contains "$(cat "$tmp/log.curl")" "$repo/ca/phon/vlc/vlc-macos/3.0.24/vlc-macos-3.0.24.pom" "checks the POM URL"
    assert_contains "$(cat "$tmp/log.curl")" "$repo/ca/phon/vlc/vlc-macos/3.0.24/vlc-macos-3.0.24.zip" "downloads the published zip"
    assert_eq "published zip" "$(cat "$tmp/pkg.zip")" "local zip is the published one ($code)"
done

# not yet published: deploy
rm -f "$tmp/log."*
echo zip > "$tmp/pkg.zip"
STUB_HTTP_CODE=404 bash "$PUBLISH" vlc-windows-x64 3.0.24-2 "$tmp/pkg.zip" >/dev/null
assert_eq 0 $? "deploy exit status"
args=$(cat "$tmp/log.mvn")
assert_contains "$args" "deploy:deploy-file" "runs deploy-file"
assert_contains "$args" "-DgroupId=ca.phon.vlc" "groupId"
assert_contains "$args" "-DartifactId=vlc-windows-x64" "artifactId"
assert_contains "$args" "-Dversion=3.0.24-2" "version"
assert_contains "$args" "-Dpackaging=zip" "packaging"
assert_contains "$args" "-Dfile=$tmp/pkg.zip" "file"
assert_contains "$args" "-DrepositoryId=github" "repositoryId"
assert_contains "$args" "-Durl=$repo" "url"
assert_contains "$(cat "$tmp/log.settings")" "<password>secret</password>" "settings carry token"
assert_eq zip "$(cat "$tmp/pkg.zip")" "deploy leaves the local zip alone"

# any other answer from the registry is an error
assert_fails env STUB_HTTP_CODE=401 bash "$PUBLISH" vlc-macos 3.0.24 "$tmp/pkg.zip"

# a network failure names the problem
err=$(STUB_HTTP_CODE=000 STUB_CURL_EXIT=6 bash "$PUBLISH" vlc-macos 3.0.24 "$tmp/pkg.zip" 2>&1)
assert_contains "$err" "could not reach" "network failure message"

finish
