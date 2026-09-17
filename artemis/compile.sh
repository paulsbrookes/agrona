#!/usr/bin/env bash
# Artemis compile step: sync the checkout into the persistent workspace and build
# everything test.sh and benchmark.sh consume: the agrona main classes (with the
# ByteBuddy UnsafeApi transformation), the test classes, and the JMH shadow jar.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

sync_workspace
ensure_gradle_home
cd "$WORKSPACE"
echo "artemis/compile: ${GRADLE_BUILD_TASKS[*]} in $WORKSPACE (JDK $JAVA_HOME)" >&2
./gradlew "${GRADLE_BUILD_TASKS[@]}" --offline --max-workers="$GRADLE_WORKERS" -q 1>&2
test -f "$WORKSPACE/agrona-benchmarks/build/libs/benchmarks.jar"
echo "artemis/compile: ok" >&2
