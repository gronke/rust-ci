//! Self-test probe for the Docker actions' env passthrough.
//!
//! The self-test workflow forwards (or deliberately withholds) `CICD_PROBE` via
//! the `env-include` / `env-exclude` inputs and states the expectation through
//! the literal `env` input as `CICD_EXPECT`. This test turns that into a hard
//! assertion that runs inside the container. For a normal `cargo test` run
//! neither variable is set, so it is inert.

#[test]
fn env_passthrough_matches_expectation() {
    match std::env::var("CICD_EXPECT").as_deref() {
        Ok("present") => assert_eq!(
            std::env::var("CICD_PROBE").as_deref(),
            Ok("forwarded"),
            "CICD_EXPECT=present but CICD_PROBE did not arrive — env-include is broken",
        ),
        Ok("absent") => assert!(
            std::env::var("CICD_PROBE").is_err(),
            "CICD_EXPECT=absent but CICD_PROBE leaked into the container",
        ),
        // Not a passthrough probe run (normal `cargo test`): nothing to assert.
        _ => {}
    }
}
