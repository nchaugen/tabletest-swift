#!/bin/sh
# Checks the tabletest-format command plugin end to end, in a package that depends on this
# repo: --check fails on a misaligned table, the write formats it, and --check then passes.
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
package=$(mktemp -d "${TMPDIR:-/tmp}/tabletest-plugin-check.XXXXXX")
trap 'rm -rf "$package"' EXIT

mkdir -p "$package/Tests/DemoTests"
cat > "$package/Package.swift" <<SWIFT
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Demo",
    dependencies: [.package(path: "$repo")],
    targets: [.testTarget(name: "DemoTests", dependencies: [.product(name: "TableTest", package: "tabletest-swift")])]
)
SWIFT
cat > "$package/Tests/DemoTests/YearTests.swift" <<'SWIFT'
import TableTest

struct YearTests {
    @TableTest("""
        Year | Leap?
        2004 | true
        1900 |   false
        """)
    func knowsALeapYear(year: Int, leap: Bool) {}
}
SWIFT

run() {
    swift package --package-path "$package" --allow-writing-to-package-directory tabletest-format "$@"
}

echo "== --check on a misaligned table: expect a failure that names the file"
if output=$(run --check 2>&1); then
    echo "FAIL: --check passed on a misaligned table" >&2
    exit 1
fi
echo "$output" | grep -q "YearTests.swift" || { echo "FAIL: --check did not name the file" >&2; echo "$output" >&2; exit 1; }

echo "== format: expect the table aligned"
run
grep -q "1900 | false" "$package/Tests/DemoTests/YearTests.swift" || { echo "FAIL: the table is not aligned" >&2; exit 1; }

echo "== --check after formatting: expect a pass"
run --check

echo "OK: the plugin checks and formats a package"
