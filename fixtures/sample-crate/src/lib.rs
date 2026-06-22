//! Trivial fixture crate exercised by cicd-rust's self-test workflow.
//!
//! It exists only to give the `lint-and-test` and `check-release-readiness`
//! actions a real, green crate to run against.

/// Adds two numbers.
pub fn add(a: u64, b: u64) -> u64 {
    a + b
}

#[cfg(test)]
mod tests {
    use super::add;

    #[test]
    fn adds() {
        assert_eq!(add(2, 2), 4);
    }
}
