#!/usr/bin/env bash
# Tests for scripts/fetch.sh.
source "$(dirname "$0")/helpers.sh"
FETCH="$REPO_ROOT/scripts/fetch.sh"
export FETCH_RETRY_DELAY=0

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
src="$tmp/src"
mkdir -p "$src"

echo "payload" > "$src/good.zip"
(cd "$src" && shasum -a 256 good.zip > good.zip.sha256)

echo "payload" > "$src/bad.zip"
echo "0000000000000000000000000000000000000000000000000000000000000000  bad.zip" > "$src/bad.zip.sha256"

echo "payload" > "$src/nosum.zip"

# good download
out=$(bash "$FETCH" "file://$src/good.zip" "$tmp/d1")
assert_eq 0 $? "good download exit status"
assert_eq "$tmp/d1/good.zip" "$out" "prints downloaded path"
assert_file "$tmp/d1/good.zip"

# already present and valid: still succeeds
out=$(bash "$FETCH" "file://$src/good.zip" "$tmp/d1")
assert_eq "$tmp/d1/good.zip" "$out" "re-run reuses verified file"

# checksum mismatch
assert_fails bash "$FETCH" "file://$src/bad.zip" "$tmp/d2"
assert_no_file "$tmp/d2/bad.zip"
assert_no_file "$tmp/d2/bad.zip.sha256"

# missing checksum file
assert_fails bash "$FETCH" "file://$src/nosum.zip" "$tmp/d3"
assert_no_file "$tmp/d3/nosum.zip"

# a mirror that answers 404 once is retried
mkdir -p "$tmp/bin"
real_curl=$(command -v curl)
cat > "$tmp/bin/curl" <<STUB
#!/usr/bin/env bash
if [ ! -e "$tmp/flaked" ]; then touch "$tmp/flaked"; exit 22; fi
exec "$real_curl" "\$@"
STUB
chmod +x "$tmp/bin/curl"
out=$(PATH="$tmp/bin:$PATH" bash "$FETCH" "file://$src/good.zip" "$tmp/d5")
assert_eq "$tmp/d5/good.zip" "$out" "retries after a failed attempt"

# missing file
assert_fails bash "$FETCH" "file://$src/absent.zip" "$tmp/d4"
assert_no_file "$tmp/d4/absent.zip"

finish
