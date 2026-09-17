#!/usr/bin/env bash
# Shared helpers for the Artemis reviewer-study harness adapter (aeron-io/agrona 2.6.1).
# Sourced by compile.sh, test.sh and benchmark.sh. Never edits anything outside
# artemis/ or the persistent workspace.
set -euo pipefail

REPO_KEY=agrona
CHECKOUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_KEY CHECKOUT

# --- JDK 17 pin ---------------------------------------------------------------
# The Gradle build derives its toolchain from the running JVM (auto-detect and
# auto-download are disabled in gradle.properties), so the harness pins JAVA_HOME
# to a JDK 17 explicitly instead of relying on whatever `java` is on PATH.
pin_java_home() {
    local candidate
    if [ -n "${JAVA_HOME:-}" ] && "$JAVA_HOME/bin/java" -version 2>&1 | grep -q 'version "17\.'; then
        :
    else
        for candidate in /usr/lib/jvm/java-17-openjdk-amd64 /usr/lib/jvm/java-1.17.0-openjdk-amd64 \
                         /usr/lib/jvm/openjdk-17 /usr/lib/jvm/temurin-17-jdk-amd64 /usr/lib/jvm/zulu17; do
            if [ -x "$candidate/bin/java" ]; then
                JAVA_HOME="$candidate"
                break
            fi
        done
    fi
    if [ -z "${JAVA_HOME:-}" ] || ! "$JAVA_HOME/bin/java" -version 2>&1 | grep -q 'version "17\.'; then
        echo "artemis/lib: no JDK 17 found (set JAVA_HOME to a JDK 17)" >&2
        exit 1
    fi
    export JAVA_HOME
    export PATH="$JAVA_HOME/bin:$PATH"
}
pin_java_home

# --- Gradle home pin -----------------------------------------------------------
# The Gradle distribution (9.7.1, ~595 MB) and Maven dependencies (~307 MB) live in
# the study's deps cache, never in the sandbox default ~/.gradle. All normal runs use
# --offline against this cache. If the cache is missing or empty, ensure_gradle_home
# populates it ONCE with an online fetch (the only network access in the harness):
# a compile of the same task set compile.sh uses plus a single focused test run,
# which is what resolves the test runtime classpath (JUnit engine, Mockito agent).
DEPS_ROOT="${HARD_OSS_DEPS_ROOT:-/var/tmp/hard-oss-deps}/${REPO_KEY}"
export GRADLE_USER_HOME="${DEPS_ROOT}/gradle-home"

GRADLE_BUILD_TASKS=(:agrona:compileJava :agrona:byteBuddy :agrona:compileTestJava :agrona-benchmarks:shadowJar)
GRADLE_WORKERS=6

ensure_gradle_home() {
    if [ -d "$GRADLE_USER_HOME/caches/modules-2" ] && [ -d "$GRADLE_USER_HOME/wrapper/dists" ]; then
        return 0
    fi
    echo "artemis/lib: Gradle home $GRADLE_USER_HOME is empty; populating once with an online fetch" >&2
    mkdir -p "$GRADLE_USER_HOME"
    (
        cd "$WORKSPACE"
        ./gradlew "${GRADLE_BUILD_TASKS[@]}" --max-workers="$GRADLE_WORKERS" -q 1>&2
        ./gradlew :agrona:cleanTest :agrona:test --max-workers="$GRADLE_WORKERS" -q \
            --tests org.agrona.AsciiEncodingTest 1>&2
    )
}

# --- Persistent build workspace -----------------------------------------------
# Mirrors the checkout into WORKSPACE so every attempt pays incremental, not clean,
# build cost. Build outputs are excluded (and therefore preserved by --delete).
# Note: `buildSrc/src/main/java/org/agrona/build/` is a *source* package, so the
# excludes are anchored per module rather than a blanket `build/` pattern.
sync_workspace() {
    WORKSPACE="${HARD_OSS_WORKSPACE_ROOT:-/var/tmp/hard-oss-workspaces}/${REPO_KEY}"
    mkdir -p "$WORKSPACE"
    rsync -rlpgoD --checksum --delete \
        --exclude '/.git/' \
        --exclude '/.gradle/' \
        --exclude '/build/' \
        --exclude '/buildSrc/build/' \
        --exclude '/buildSrc/.gradle/' \
        --exclude '/agrona/build/' \
        --exclude '/agrona-agent/build/' \
        --exclude '/agrona-benchmarks/build/' \
        --exclude '/agrona-concurrency-tests/build/' \
        --exclude '/artemis_results.json' \
        --exclude '/jmh.json' \
        "$CHECKOUT/" "$WORKSPACE/"
    export WORKSPACE
}
