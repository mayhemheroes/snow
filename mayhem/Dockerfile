# syntax=docker/dockerfile:1.7
#
# snow — commit-image Dockerfile (Rust / cargo-fuzz).
# Builds ON TOP of the org base (ghcr.io/mayhemheroes/base), adding a pinned
# Rust nightly + cargo-fuzz under /opt/toolchains/rust, then runs mayhem/build.sh.
#
# snow is a pure-Rust Noise Protocol Framework implementation. The four fuzz
# targets (handshake_reader, handshake_writer, params, transport) cover the
# core message parsing / crypto surfaces.
#
# Build (from the repo root, on the `mayhem` branch):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile \
#       --build-arg COMMIT=$(git rev-parse HEAD) \
#       -t snow-commit:test .

FROM ghcr.io/mayhemheroes/base:20260621

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG — an empty ENV value breaks clang.
ARG SOURCE_DATE_EPOCH
# Declared for parity; Rust build uses RUSTFLAGS, not $SANITIZER_FLAGS.
ARG SANITIZER_FLAGS
ARG MAYHEM_JOBS=

# Pin the nightly toolchain: snow edition 2024 / rust-version 1.85 needs 2025+ nightly.
ARG RUST_TOOLCHAIN=nightly-2025-09-05
ARG CARGO_FUZZ_VERSION=0.12.0

# Shared Rust install: CARGO_HOME/RUSTUP_HOME under /opt/toolchains/rust (SPEC §6.2 item 8 —
# $HOME-independent so PATCH re-run finds the same cache regardless of identity).
ENV RUSTUP_HOME=/opt/toolchains/rust/rustup \
    CARGO_HOME=/opt/toolchains/rust/cargo \
    PATH=/opt/toolchains/rust/cargo/bin:${PATH}

USER root
RUN set -eux; \
    mkdir -p "$RUSTUP_HOME" "$CARGO_HOME"; \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --no-modify-path --profile minimal \
                --default-toolchain "${RUST_TOOLCHAIN}"; \
    rustup component add rust-src --toolchain "${RUST_TOOLCHAIN}"; \
    cargo install cargo-fuzz --version "${CARGO_FUZZ_VERSION}" --locked; \
    # Allow the non-root `mayhem` user to read the toolchain and r/w the registry cache.
    chmod -R a+rX /opt/toolchains/rust; \
    chmod -R a+rwX "$CARGO_HOME/registry" "$CARGO_HOME/git" 2>/dev/null || true; \
    mkdir -p "$CARGO_HOME/registry" "$CARGO_HOME/git" && chmod -R a+rwX "$CARGO_HOME/registry" "$CARGO_HOME/git"; \
    rustc --version; cargo --version; cargo fuzz --version; \
    # DWARF3 anchor: cargo-fuzz links librustc-nightly_rt.asan.a (DWARF5) via --whole-archive
    # so it lands at offset 0 in .debug_info, defeating -Zdwarf-version=3 alone. Compile a tiny
    # empty anchor.c with -gdwarf-3 and inject it via a cc-wrapper so its DWARF3 CU sits at offset
    # 0 (the first CU determines the version that verify-repo's readelf -m1 check reads). (§6.2 item 10)
    mkdir -p /opt/mayhem-dwarf3-anchor; \
    printf 'void mayhem_dwarf3_anchor(void){}\n' > /tmp/anchor.c; \
    clang -g -gdwarf-3 -c /tmp/anchor.c -o /opt/mayhem-dwarf3-anchor/anchor.o; \
    printf '#!/bin/sh\nexec cc /opt/mayhem-dwarf3-anchor/anchor.o "$@"\n' \
      > /opt/mayhem-dwarf3-anchor/cc-wrapper.sh; \
    chmod +x /opt/mayhem-dwarf3-anchor/cc-wrapper.sh; \
    rm /tmp/anchor.c

# Source enters from the build CONTEXT (CI checkout, full .git history) → /mayhem.
USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

# Populate the cargo registry (online, first build) and build the fuzz targets.
RUN bash mayhem/build.sh

# Run the project's own test suite at build time; a failing suite fails the build.
RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
