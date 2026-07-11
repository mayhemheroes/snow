#!/usr/bin/env bash
#
# snow/mayhem/test.sh — RUN snow's own unit-test suite and emit a CTRF summary.
# exit 0 iff all tests pass.
#
# PATCH-grade oracle: snow's tests assert correct Noise protocol message exchange,
# key derivation, and error handling — a no-op / exit(0) patch fails here because
# the handshake tests perform full round-trip encryption/decryption checks with
# known-answer values.
#
# This script only RUNS the pre-built suite; it does NOT compile (build.sh does that).
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo not available — cannot run test suite" >&2
  emit_ctrf "cargo-test" 0 1 0; exit 2
fi

echo "=== running snow cargo test suite (normal flags — Noise protocol round-trip asserts) ==="
# RUSTFLAGS cleared so tests run without sanitizer overheads from the fuzz build.
# snow tests: handshake round-trips, vector tests, error cases — all assert specific outcomes.
out="$(RUSTFLAGS="" cargo test --lib --no-fail-fast --jobs "$MAYHEM_JOBS" 2>&1)"; rc=$?
echo "$out"

# libtest format: "test result: ok. N passed; N failed; N ignored; ..."
PASSED=0; FAILED=0; IGNORED=0
while read -r p f i; do
  PASSED=$(( PASSED + p )); FAILED=$(( FAILED + f )); IGNORED=$(( IGNORED + i ))
done < <(printf '%s\n' "$out" \
  | sed -n 's/^test result:.* \([0-9][0-9]*\) passed; \([0-9][0-9]*\) failed; \([0-9][0-9]*\) ignored.*/\1 \2 \3/p')

if [ "$(( PASSED + FAILED + IGNORED ))" -eq 0 ]; then
  echo "could not parse test result lines; using cargo exit code $rc" >&2
  [ "$rc" -eq 0 ] && { emit_ctrf "cargo-test" 1 0 0; exit 0; }
  emit_ctrf "cargo-test" 0 1 0; exit 1
fi

emit_ctrf "cargo-test" "$PASSED" "$FAILED" "$IGNORED"
