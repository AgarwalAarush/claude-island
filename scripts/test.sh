#!/bin/bash
# Standalone Swift test runner for Claude Island.
#
# Each test file under Tests/*Tests.swift is compiled together with the
# production source files it covers (and TestSupport.swift) into a temp
# binary, then executed. Exits non-zero on first failure.
#
# Usage:
#   ./scripts/test.sh                 # run all tests
#   ./scripts/test.sh NotchGeometry   # run only matching test files
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TESTS_DIR="$PROJECT_DIR/Tests"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

# Map each test file to the production source files it needs to compile against.
# Add a new entry whenever you add a new test file.
declare -a TEST_SOURCES
TEST_SOURCES=(
    "NotchGeometryTests.swift|ClaudeIsland/Core/NotchGeometry.swift"
    "NotchTunablesTests.swift|ClaudeIsland/Core/NotchTunables.swift"
    "ConversationTextFilterTests.swift|ClaudeIsland/Services/Session/ConversationTextFilter.swift"
)

FILTER="${1:-}"
ANY_RAN=0
FAIL_COUNT=0

for entry in "${TEST_SOURCES[@]}"; do
    test_file="${entry%%|*}"
    deps="${entry#*|}"
    test_name="${test_file%Tests.swift}"

    if [ -n "$FILTER" ] && [[ "$test_name" != *"$FILTER"* ]]; then
        continue
    fi

    if [ ! -f "$TESTS_DIR/$test_file" ]; then
        echo "skipping (missing): $test_file"
        continue
    fi

    ANY_RAN=1
    binary="$BUILD_DIR/${test_name}_runner"

    # Build the swiftc argument list: TestSupport + the test file + each dep
    args=(
        "$TESTS_DIR/TestSupport.swift"
        "$TESTS_DIR/$test_file"
    )
    IFS='|' read -ra dep_list <<< "$deps"
    for dep in "${dep_list[@]}"; do
        args+=("$PROJECT_DIR/$dep")
    done

    echo "── building $test_name ──"
    if ! swiftc -o "$binary" "${args[@]}"; then
        echo "build failed for $test_name" >&2
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    echo "── running  $test_name ──"
    if ! "$binary"; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    echo
done

if [ "$ANY_RAN" -eq 0 ]; then
    echo "no tests matched filter: $FILTER" >&2
    exit 1
fi

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo "$FAIL_COUNT test file(s) failed" >&2
    exit 1
fi

echo "all tests passed"
