#!/usr/bin/env bash
# Validation gate for LF-AIWorkflow.
#   1. VALIDATE: Debug unit tests, UI tests excluded (TD-013: UI runner cannot enable automation from an agent shell).
#   2. Release perf gate: the 10 MB wall-clock test, compiled only outside DEBUG (TD-011, TD-125).
# Exits non-zero if a step fails, or if the perf test is not exactly one passing test in the xcresult.
# xcodebuild exits 0 when a -only-testing filter matches nothing, so the xcresult summary is the source of truth.
# Each gate has its own derivedDataPath; a failed gate deletes its path so the next run starts clean.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="LF-AIWorkflow"
DESTINATION="platform=macOS"
PERF_TEST_ID="LF-AIWorkflowTests/TokenEstimateTests/tenMegabytesRunsFast()"
GATE_ROOT="${HOME}/Library/Developer/LF-gate-validate"
LOG_DIR="${GATE_ROOT}/logs"
PERF_RESULT="${LOG_DIR}/perf-release.xcresult"

# Runs one xcodebuild test gate. Arguments: name, derivedDataPath, log file, extra xcodebuild arguments.
# Complexity: O(build + test) time, O(1) space
run_gate() {
    local name="$1" derived="$2" log="$3"
    shift 3
    echo "==> ${name} (log: ${log})"
    if xcodebuild test -scheme "${SCHEME}" -destination "${DESTINATION}" \
        -derivedDataPath "${derived}" "$@" >"${log}" 2>&1; then
        echo "<== ${name}: passed"
        return 0
    fi
    echo "<== ${name}: FAILED. Errors and failing tests:"
    grep -E "error:|failed|✘" "${log}" | tail -40 || true
    rm -rf "${derived}"
    return 1
}

# Succeeds only if the xcresult summary shows exactly one test, passed, with no failures or skips.
# Complexity: O(1) time, O(summary) space
perf_test_passed() {
    local result="$1"
    [[ -d "${result}" ]] || return 1
    xcrun xcresulttool get test-results summary --path "${result}" 2>/dev/null | python3 -I -c '
import json, sys
s = json.load(sys.stdin)
ok = s.get("totalTestCount") == 1 and s.get("passedTests") == 1 \
    and s.get("failedTests") == 0 and s.get("skippedTests") == 0
sys.exit(0 if ok else 1)
'
}

main() {
    mkdir -p "${LOG_DIR}"
    cd "${ROOT}"

    run_gate "VALIDATE (Debug)" "${GATE_ROOT}/debug" "${LOG_DIR}/validate-debug.log" \
        -skip-testing:LF-AIWorkflowUITests

    # Release differs from Debug in three build settings. Overrides are for this gate only; the shipping config is unchanged:
    #   ENABLE_TESTABILITY: only the project Debug block sets it, so @testable import fails in Release.
    #   ENABLE_HARDENED_RUNTIME: library validation rejects the injected test bundle (Team ID mismatch).
    #     The perf test is pure compute, so the runtime flag does not change what it measures.
    rm -rf "${PERF_RESULT}"
    run_gate "Release perf test" "${GATE_ROOT}/release" "${LOG_DIR}/perf-release.log" \
        -configuration Release -only-testing:"${PERF_TEST_ID}" -resultBundlePath "${PERF_RESULT}" \
        ENABLE_TESTABILITY=YES ENABLE_HARDENED_RUNTIME=NO || exit 1

    if ! perf_test_passed "${PERF_RESULT}"; then
        echo "FAILED: tenMegabytesRunsFast did not pass exactly once (failed, skipped or not run). Result: ${PERF_RESULT}"
        exit 1
    fi
    echo "OK: VALIDATE and tenMegabytesRunsFast (Release) passed"
}

main "$@"
