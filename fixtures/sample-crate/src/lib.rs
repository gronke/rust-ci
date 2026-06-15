//! Trivial fixture crate exercised by cicd-rust's self-test workflow.
//!
//! It exists only to give the actions a real, green crate to run against — and,
//! via its one dependency, to prove that a sealed `--network none` build can
//! compile a fetched dependency entirely offline.

/// Adds two numbers.
pub fn add(a: u64, b: u64) -> u64 {
    a + b
}

/// Returns zero as a C int. Exists only so the fixture actually *uses* its
/// `libc` dependency, forcing it to be fetched and compiled.
pub fn c_zero() -> libc::c_int {
    0
}

#[cfg(test)]
mod tests {
    use super::{add, c_zero};

    #[test]
    fn adds() {
        assert_eq!(add(2, 2), 4);
    }

    #[test]
    fn c_zero_is_zero() {
        assert_eq!(c_zero(), 0);
    }
}
