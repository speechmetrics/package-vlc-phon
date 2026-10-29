#!/usr/bin/env bash
# Runs every tests/test_*.sh and reports a summary.
set -u

cd "$(dirname "$0")"
passed=0
failed=0
for t in test_*.sh; do
    if bash "$t"; then
        echo "PASS $t"
        passed=$((passed + 1))
    else
        echo "FAIL $t"
        failed=$((failed + 1))
    fi
done
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
