#!/usr/bin/env bash
# Artemis benchmark step: four `unsafeBuffer` JMH methods of the ASCII put/parse
# benchmarks, fixed parameter, single thread, one fork, pinned to one CPU when
# taskset exists. Writes artemis_results.json atomically to the checkout root.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$HERE/compile.sh"          # builds agrona-benchmarks/build/libs/benchmarks.jar (offline)
# shellcheck source=lib.sh
source "$HERE/lib.sh"
sync_workspace

rm -f "$CHECKOUT/artemis_results.json" "$WORKSPACE/artemis_results.json" "$WORKSPACE/jmh.json"

JAR="$WORKSPACE/agrona-benchmarks/build/libs/benchmarks.jar"
test -f "$JAR"

PIN=()
if command -v taskset >/dev/null 2>&1; then
    PIN=(taskset -c 10)
fi

cd "$WORKSPACE"
echo "artemis/benchmark: running JMH (${PIN[*]:-unpinned})" >&2
"${PIN[@]}" "$JAVA_HOME/bin/java" -jar "$JAR" \
    'org\.agrona\.concurrent\.MutableDirectBuffer(PutInt|PutLong|ParseInt|ParseLong)AsciiBenchmark\.unsafeBuffer$' \
    -p value=27085146 -f 1 -wi 3 -w 1 -i 5 -r 1 -t 1 \
    -jvmArgsAppend '--add-opens=java.base/jdk.internal.misc=ALL-UNNAMED' \
    -rf json -rff "$WORKSPACE/jmh.json" 1>&2

TMP="$CHECKOUT/.artemis_results.json.tmp"
python3 - "$WORKSPACE/jmh.json" "$TMP" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
want = {
    "put_int_ascii_ns_per_op":    "MutableDirectBufferPutIntAsciiBenchmark.unsafeBuffer",
    "put_long_ascii_ns_per_op":   "MutableDirectBufferPutLongAsciiBenchmark.unsafeBuffer",
    "parse_int_ascii_ns_per_op":  "MutableDirectBufferParseIntAsciiBenchmark.unsafeBuffer",
    "parse_long_ascii_ns_per_op": "MutableDirectBufferParseLongAsciiBenchmark.unsafeBuffer",
}
with open(src) as fh:
    runs = json.load(fh)
found = {}
for r in runs:
    name = r["benchmark"]
    for key, suffix in want.items():
        if name.endswith(suffix):
            if key in found:
                sys.exit(f"artemis/benchmark: duplicate result for {name}")
            if r.get("mode") != "avgt" or r["primaryMetric"].get("scoreUnit") != "ns/op":
                sys.exit(f"artemis/benchmark: unexpected mode/unit for {name}")
            if r.get("params", {}).get("value") != "27085146":
                sys.exit(f"artemis/benchmark: unexpected params for {name}: {r.get('params')}")
            score = float(r["primaryMetric"]["score"])
            if not (score > 0):
                sys.exit(f"artemis/benchmark: non-positive score for {name}")
            found[key] = score
missing = [k for k in want if k not in found]
if missing:
    sys.exit(f"artemis/benchmark: missing results: {missing}")
out = {"ascii_total_ns_per_op": sum(found.values())}
out.update({k: found[k] for k in want})
with open(dst, "w") as fh:
    json.dump(out, fh)
    fh.write("\n")
print("artemis/benchmark: " + json.dumps(out), file=sys.stderr)
PY
mv -f "$TMP" "$CHECKOUT/artemis_results.json"
echo "artemis/benchmark: wrote $CHECKOUT/artemis_results.json" >&2
