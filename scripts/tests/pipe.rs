use super::*;
use crate::util::testutil::sh;

fn filter(pat: &str) -> (&'static str, Vec<String>) {
    if cfg!(windows) {
        ("findstr", vec![pat.into()])
    } else {
        ("grep", vec![pat.into()])
    }
}

#[test]
fn single_stage_returns_its_status() {
    assert!(pipe_chain(vec![sh("exit 0")]).unwrap().success());
    assert_eq!(pipe_chain(vec![sh("exit 3")]).unwrap().code(), Some(3));
}

#[test]
fn stdout_feeds_next_stage_and_last_status_wins() {
    assert!(pipe_chain(vec![sh("echo hi"), filter("hi")]).unwrap().success());
    assert!(!pipe_chain(vec![sh("echo hi"), filter("zzz")]).unwrap().success());
}

#[test]
fn missing_binary_is_an_error() {
    assert!(pipe_chain(vec![("homelab-no-such-binary", vec![])]).is_err());
}
