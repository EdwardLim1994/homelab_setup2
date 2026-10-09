use super::*;
use crate::util::testutil::*;

#[test]
fn run_errors_when_kubectl_missing() {
    let _g = lock();
    let _p = EmptyPath::new();
    assert!(run().is_err());
}
