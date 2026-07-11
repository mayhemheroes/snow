#!/usr/bin/env bash
#
# snow/mayhem/build.sh — build snow's cargo-fuzz targets as sanitized libFuzzer
# binaries (OSS-Fuzz Rust path: cargo-fuzz + ASan via RUSTFLAGS).
#
# Runs inside the commit image as `mayhem` in /mayhem. The Rust toolchain +
# cargo registry live at $CARGO_HOME=/opt/toolchains/rust/cargo (pinned by the
# Dockerfile ENV — absolute, $HOME-independent).
#
# AIR-GAPPED CONTRACT (SPEC §6.5): the PATCH tier re-runs THIS script OFFLINE.
#   The FIRST build (in CI, online) populates the cargo registry under $CARGO_HOME.
#   The PATCH re-run resolves crates from that cache (CARGO_NET_OFFLINE=true is
#   exported by the rlenv runtime). Do NOT hard-code --offline here.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SRC:=/mayhem}"
: "${MAYHEM_JOBS:=$(nproc)}"
export MAYHEM_JOBS
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

cd "$SRC"

# DWARF < 4 debug info (SPEC §6.2 item 10): cargo-fuzz links librustc-nightly_rt.asan.a (DWARF5)
# via --whole-archive, placing it at .debug_info offset 0. -Zdwarf-version=3 alone does NOT win
# because the ASan runtime CU lands first. The cc-wrapper injects a DWARF3 anchor.o as the very
# first linker input, pushing the ASan runtime CU back, so readelf sees DWARF3 at offset 0.
: "${RUST_DEBUG_FLAGS:=-Cdebuginfo=2 -Zdwarf-version=3 -Clinker=/opt/mayhem-dwarf3-anchor/cc-wrapper.sh}"

# Fuzz crate lives under mayhem/fuzz (additive — upstream only has honggfuzz hfuzz/).
FUZZ_DIR="mayhem/fuzz"
TRIPLE="x86_64-unknown-linux-gnu"

# Discover targets from the fuzz_targets/ dir automatically.
FUZZ_TARGETS=()
for f in "$FUZZ_DIR"/fuzz_targets/*.rs; do
  FUZZ_TARGETS+=("$(basename "${f%.*}")")
done
[ "${#FUZZ_TARGETS[@]}" -gt 0 ] || { echo "ERROR: no fuzz targets under $FUZZ_DIR/fuzz_targets/" >&2; exit 1; }

# cargo-fuzz drives libFuzzer+ASan for Rust.
# --cfg fuzzing matches libfuzzer-sys; force-frame-pointers aids ASan stack traces.
# RUST_DEBUG_FLAGS forces DWARF-3 on the first CU (via cc-wrapper + anchor.o).
# SANITIZER_FLAGS is intentionally NOT passed to rustc (it's a clang flag); parity
# with the base image ENV is maintained by declaring ARG SANITIZER_FLAGS in the Dockerfile.
export RUSTFLAGS="${RUSTFLAGS:-} --cfg fuzzing -Zsanitizer=address -Cforce-frame-pointers ${RUST_DEBUG_FLAGS}"

echo "=== cargo fuzz build (nightly, ASan via RUSTFLAGS) ==="
echo "RUSTFLAGS=$RUSTFLAGS"
echo "targets: ${FUZZ_TARGETS[*]}"

for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  cargo fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions "$t"
  bin="$SRC/$FUZZ_DIR/target/$TRIPLE/release/$t"
  [ -x "$bin" ] || { echo "ERROR: expected fuzz binary not found at $bin" >&2; exit 1; }
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

# Build the test suite (normal flags, no sanitizers) so mayhem/test.sh only runs it.
echo "=== cargo test --no-run (normal flags, for test.sh) ==="
RUSTFLAGS="" cargo test --no-run --jobs "$MAYHEM_JOBS" 2>&1 || true

echo "build.sh complete:"
ls -la /mayhem/handshake_reader /mayhem/handshake_writer /mayhem/params /mayhem/transport 2>&1 || true
