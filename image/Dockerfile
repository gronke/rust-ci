# Lean Rust CI image for the cicd-rust composite actions.
#
# The official rust image ships the minimal rustup profile (no clippy/rustfmt),
# so we add them here; we also add jq for the release-readiness script. The full
# rust image already provides curl + git. Pinning the base (rather than the
# runner's preinstalled toolchain) is the reproducibility win.
FROM rust:1

RUN rustup component add clippy rustfmt \
    && apt-get update \
    && apt-get install -y --no-install-recommends jq \
    && rm -rf /var/lib/apt/lists/* \
    && rustc --version && cargo clippy --version && cargo fmt --version && jq --version
