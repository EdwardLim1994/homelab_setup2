use super::*;
use crate::util::testutil::lock;

#[test]
fn run_passes() {
    let _g = lock();
    assert_eq!(run().unwrap(), 0);
}

#[test]
fn expect_matches_and_mismatches() {
    let _g = lock();
    std::env::set_var("HL_T_EXPECT", "v");
    assert!(expect("HL_T_EXPECT", "v").is_ok());
    let e = expect("HL_T_EXPECT", "other").unwrap_err().to_string();
    assert!(e.contains("want [other] got [v]"), "{e}");
    std::env::remove_var("HL_T_EXPECT");
    assert!(expect("HL_T_EXPECT", "v").is_err());
    assert!(expect("HL_T_EXPECT", "").is_ok());
}
