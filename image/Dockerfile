# Rust toolchain image for the rust-ci composite actions: adds clippy, rustfmt, jq.
ARG RUST_VERSION=latest
FROM rust:${RUST_VERSION}

RUN rustup component add clippy rustfmt \
    && apt-get update \
    && apt-get install -y --no-install-recommends jq \
    && rm -rf /var/lib/apt/lists/* \
    && rustc --version && cargo clippy --version && cargo fmt --version && jq --version
