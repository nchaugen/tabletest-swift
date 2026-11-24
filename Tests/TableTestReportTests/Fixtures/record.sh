#!/bin/sh
# Records what tabletest-export reads from a result bundle, for RecordedResults.
# The examples' check-report-export.sh makes a bundle with the probe tables.
set -eu

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <results.xcresult> <new fixture directory>" >&2
    exit 2
fi
bundle=$1
fixture=$2
mkdir "$fixture"
mkdir "$fixture/details"

xcrun xcresulttool get test-results tests --path "$bundle" > "$fixture/tests.json"
xcrun xcresulttool export attachments --path "$bundle" --output-path "$fixture/attachments" \
    --filter 'tabletest-manifest*.json' > /dev/null

# The export asks for the details of each table's scenarios(_:) test.
python3 -I - "$fixture/tests.json" <<'PY' | while IFS= read -r id; do
import json
import sys

def test_ids(node):
    if node.get("nodeType") == "Test Case" and node.get("nodeIdentifier", "").endswith("/scenarios(_:)"):
        yield node["nodeIdentifierURL"]
    for child in node.get("children", []):
        yield from test_ids(child)

report = json.load(open(sys.argv[1]))
for root in report["testNodes"]:
    for test_id in test_ids(root):
        print(test_id)
PY
    name=$(printf '%s' "$id" | sed 's/[^A-Za-z0-9]/_/g')
    xcrun xcresulttool get test-results test-details --path "$bundle" --test-id "$id" > "$fixture/details/$name.json"
done

# Keep the machine's identity and the home folder out of the fixture.
python3 -I - "$fixture" <<'PY'
import re
import sys
from pathlib import Path

fixture = Path(sys.argv[1])
report = (fixture / "tests.json").read_text()
device_ids = set(re.findall(r'"deviceId" : "([^"]+)"', report))
for path in fixture.rglob("*.json"):
    text = path.read_text()
    for number, device_id in enumerate(sorted(device_ids), start=1):
        text = text.replace(device_id, f"00000000-{number:016d}")
    text = re.sub(r"/Users/[^/\"]+/[^\"]*?/(ExamplesTests/)", r"/path/to/\1", text)
    text = re.sub(r"/Users/[^/\"]+", "/path/to/home", text)
    path.write_text(text)
PY
