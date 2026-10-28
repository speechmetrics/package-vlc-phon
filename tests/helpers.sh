#!/usr/bin/env bash
# Assertion helpers shared by tests/test_*.sh.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

fail() {
    echo "  FAIL: $*" >&2
    FAILURES=$((FAILURES + 1))
}

assert_eq() {
    local expected="$1" actual="$2" msg="$3"
    [ "$expected" = "$actual" ] || fail "$msg (expected '$expected', got '$actual')"
}

assert_contains() {
    local haystack="$1" needle="$2" msg="$3"
    case "$haystack" in
        *"$needle"*) ;;
        *) fail "$msg (missing '$needle')" ;;
    esac
}

assert_not_contains() {
    local haystack="$1" needle="$2" msg="$3"
    case "$haystack" in
        *"$needle"*) fail "$msg (unexpected '$needle')" ;;
    esac
}

assert_file() {
    [ -e "$1" ] || fail "expected file $1"
}

assert_no_file() {
    [ ! -e "$1" ] || fail "unexpected file $1"
}

assert_fails() {
    if "$@" >/dev/null 2>&1; then
        fail "expected failure: $*"
    fi
}

finish() {
    [ "$FAILURES" -eq 0 ]
}
