#!/bin/sh
# Copies the fixtures of tabletest-spec into the test targets and records the spec commit:
# the parse fixtures into TableTestParserTests, the run fixtures into TableTestTests.
# The spec checkout defaults to ../tabletest-spec; set TABLETEST_SPEC to use another one.
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
spec=${TABLETEST_SPEC:-$repo/../tabletest-spec}

if [ -n "$(git -C "$spec" status --porcelain -- fixtures)" ]; then
    echo "The spec fixtures have uncommitted changes; commit them first so SPEC_COMMIT is true" >&2
    exit 1
fi

copy() {
    kind=$1
    fixtures=$2
    if [ ! -d "$spec/fixtures/$kind" ]; then
        echo "No $kind fixtures in $spec/fixtures/$kind" >&2
        exit 1
    fi
    rm -rf "$fixtures/$kind"
    mkdir -p "$fixtures/$kind"
    cp "$spec/fixtures/$kind"/*.json "$fixtures/$kind/"
    git -C "$spec" rev-parse HEAD > "$fixtures/SPEC_COMMIT"
    echo "Copied $(ls "$fixtures/$kind" | wc -l | tr -d ' ') $kind fixture files from spec commit $(cat "$fixtures/SPEC_COMMIT")"
}

copy parse "$repo/Tests/TableTestParserTests/Fixtures"
copy run "$repo/Tests/TableTestTests/Fixtures"
