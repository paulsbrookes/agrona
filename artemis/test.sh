#!/usr/bin/env bash
# Artemis correctness gate: the focused five-class deterministic suite identified in
# screening (617 tests). Always recompiles first so the classes match the synced source.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$HERE/compile.sh"
# shellcheck source=lib.sh
source "$HERE/lib.sh"
sync_workspace
cd "$WORKSPACE"

echo "artemis/test: running focused gate" >&2
./gradlew :agrona:cleanTest :agrona:test --offline --max-workers="$GRADLE_WORKERS" -q \
    --tests org.agrona.AsciiEncodingTest \
    --tests org.agrona.concurrent.UnsafeBufferTest \
    --tests org.agrona.ExpandableArrayBufferTest \
    --tests org.agrona.ExpandableDirectByteBufferTest \
    --tests org.agrona.BufferStringOperationsTest 1>&2

# Summarise from the JUnit XML and fail if the gate ran nothing or recorded failures.
python3 - "$WORKSPACE/agrona/build/test-results/test" 1>&2 <<'PY'
import glob, sys, xml.etree.ElementTree as ET
d = sys.argv[1]
tests = fails = errs = skipped = 0
for f in glob.glob(d + "/TEST-*.xml"):
    r = ET.parse(f).getroot()
    tests += int(r.get("tests", 0)); fails += int(r.get("failures", 0))
    errs += int(r.get("errors", 0)); skipped += int(r.get("skipped", 0))
print(f"artemis/test: {tests} tests, {fails} failures, {errs} errors, {skipped} skipped")
if tests == 0 or fails or errs:
    sys.exit(1)
PY
echo "artemis/test: ok" >&2
