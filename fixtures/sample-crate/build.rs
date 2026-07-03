// Selftest hook: when FIXTURE_REQUIRE_GIT is set, assert the crate's git metadata is
// reachable from the build script — this guards the msrv action's disposable-copy
// git materialization (a real consumer's build.rs may run `git describe` or read the
// commit hash). Without the variable the script is a no-op, so every other selftest
// leg (sealed builds, Windows, packaging) is unaffected.
fn main() {
    println!("cargo:rerun-if-env-changed=FIXTURE_REQUIRE_GIT");
    if std::env::var_os("FIXTURE_REQUIRE_GIT").is_some() {
        let ok = std::process::Command::new("git")
            .args(["rev-parse", "HEAD"])
            .output()
            .map(|o| o.status.success())
            .unwrap_or(false);
        assert!(
            ok,
            "FIXTURE_REQUIRE_GIT is set but `git rev-parse HEAD` failed in the build script"
        );
    }
}
