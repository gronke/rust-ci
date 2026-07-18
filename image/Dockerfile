# Rust toolchain image for the rust-ci composite actions: adds clippy, rustfmt, jq.
ARG RUST_VERSION=latest
FROM rust:${RUST_VERSION}

RUN rustup component add clippy rustfmt \
    && apt-get update \
    && apt-get install -y --no-install-recommends jq \
    && rm -rf /var/lib/apt/lists/* \
    && rustc --version && cargo clippy --version && cargo fmt --version && jq --version

# Optional cross-compilation targets (space-separated), e.g. wasm32-unknown-unknown,
# so the sealed Docker actions can cross-check against them.
ARG RUST_TARGETS=""
RUN if [ -n "$RUST_TARGETS" ]; then rustup target add $RUST_TARGETS && rustup target list --installed; fi
