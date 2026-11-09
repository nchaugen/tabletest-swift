#!/bin/sh
# Copies the parse fixtures of tabletest-spec into the test target and records the spec commit.
# The spec checkout defaults to ../tabletest-spec; set TABLETEST_SPEC to use another one.
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
spec=${TABLETEST_SPEC:-$repo/../tabletest-spec}
fixtures=$repo/Tests/TableTestParserTests/Fixtures

if [ ! -d "$spec/fixtures/parse" ]; then
    echo "No parse fixtures in $spec/fixtures/parse" >&2
    exit 1
fi
if [ -n "$(git -C "$spec" status --porcelain -- fixtures)" ]; then
    echo "The spec fixtures have uncommitted changes; commit them first so SPEC_COMMIT is true" >&2
    exit 1
fi

rm -rf "$fixtures/parse"
mkdir -p "$fixtures/parse"
cp "$spec"/fixtures/parse/*.json "$fixtures/parse/"
git -C "$spec" rev-parse HEAD > "$fixtures/SPEC_COMMIT"
echo "Copied $(ls "$fixtures/parse" | wc -l | tr -d ' ') fixture files from spec commit $(cat "$fixtures/SPEC_COMMIT")"
