#!/usr/bin/env bash
# Clean + incremental Fennec Debug simulator build (port of Bitrise _firefox_benchmark).
set -eo pipefail
source "$(dirname "$0")/lib.sh"
cd "$GITHUB_WORKSPACE"
LOGS="$BENCH_OUT/logs"; mkdir -p "$LOGS"

timed_build() { # $1 = derived data, $2 = log
  local start end xc
  start=$(now)
  xcodebuild -project "$FIREFOX_PROJECT" -scheme "$FIREFOX_SCHEME" -configuration "$FIREFOX_CONFIGURATION" \
    -destination "$BUILD_DESTINATION" -derivedDataPath "$1" -clonedSourcePackagesDirPath "$SPM_DIR" \
    -disableAutomaticPackageResolution -skipMacroValidation -skipPackagePluginValidation \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= "${XCB_EXTRA[@]}" \
    build > "$2" 2>&1 || { tail -n 80 "$2" >&2; return 1; }
  end=$(now); xc=$(xc_seconds "$2")
  if [ -n "$xc" ]; then echo "$xc"; else python3 -c "print(round($end-$start,3))"; fi
}

echo "project,metric_key,machine_key,run,duration_sec" > "$BENCH_OUT/results.csv"
: > "$BENCH_OUT/clean.txt"; : > "$BENCH_OUT/incremental.txt"
for i in $(seq 1 $(( WARMUP_RUNS + BENCHMARK_RUNS ))); do
  run_label "$i"; DD="$RUNNER_TEMP/firefox-dd"; rm -rf "${DD:?}"  # same path every run, so path-dependent cache keys match
  echo "=== $LABEL: clean build ==="
  CLEAN=$(timed_build "$DD" "$LOGS/$LABEL-clean.log"); echo "clean: ${CLEAN}s"
  # Diagnostics for cache misses: files the build generated or changed (source tree and DerivedSources), with hashes.
  { echo "## git status"; git status --porcelain --untracked-files=all | head -200
    echo "## generated in source tree"; git status --porcelain --untracked-files=all | awk '{print $2}' | while read -r f; do [ -f "$f" ] && shasum "$f"; done | head -200
    echo "## DerivedSources"; find "$DD/Build/Intermediates.noindex" -path '*DerivedSources*' -type f \( -name '*.swift' -o -name '*.h' -o -name '*.m' \) -exec shasum {} + 2>/dev/null | sed "s#$DD#DD#" | sort -k2 | head -400
  } > "$LOGS/$LABEL-generated.txt" 2>&1 || true
  printf '\n// benchmark incremental change %s\n' "$LABEL" >> "$INCREMENTAL_FILE"
  INCR=$(timed_build "$DD" "$LOGS/$LABEL-incremental.log"); git checkout -- "$INCREMENTAL_FILE"; echo "incremental: ${INCR}s"
  echo "${BENCHMARK_PROJECT},clean_build,${MACHINE_KEY},${LABEL},${CLEAN}" >> "$BENCH_OUT/results.csv"
  echo "${BENCHMARK_PROJECT},incremental_build,${MACHINE_KEY},${LABEL},${INCR}" >> "$BENCH_OUT/results.csv"
  if [ "$MEASURED" = 1 ]; then echo "$CLEAN" >> "$BENCH_OUT/clean.txt"; echo "$INCR" >> "$BENCH_OUT/incremental.txt"; fi
  rm -rf "${DD:?}"
done

cat > "$BENCH_OUT/summary.json" <<JSON
{
$(summary_common),
  "benchmark_revision": "$(source_rev)",
  "clean_build": $(stats "$BENCH_OUT/clean.txt"),
  "incremental_build": $(stats "$BENCH_OUT/incremental.txt")
}
JSON
(cd "$BENCH_OUT" && rm -f clean.txt incremental.txt)
finish
