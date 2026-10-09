use super::*;
use crate::util::testutil::*;

// run_cmd(Some("phases")) re-execs current_exe() -- not safe under cargo test.

#[test]
fn env_or_prefers_env_then_default() {
    let _g = lock();
    std::env::remove_var("HL_T_ENVOR");
    assert_eq!(env_or("HL_T_ENVOR", "dflt"), "dflt");
    std::env::set_var("HL_T_ENVOR", "set");
    assert_eq!(env_or("HL_T_ENVOR", "dflt"), "set");
}

#[test]
fn parse_servers_reads_total_after_slash() {
    assert_eq!(parse_servers("internal   1/1   0/0   true"), 1);
    assert_eq!(parse_servers("internal   0/1   0/0   true"), 1);
    assert_eq!(parse_servers("internal   1/3   0/0   true"), 3);
    assert_eq!(parse_servers("internal   1/0   0/0   true"), 0);
    assert_eq!(parse_servers("internal   1"), 0);
    assert_eq!(parse_servers("internal"), 0);
    assert_eq!(parse_servers(""), 0);
}

#[test]
fn cluster_servers_is_zero_when_engine_missing() {
    let _g = lock();
    let _p = EmptyPath::new();
    assert_eq!(cluster_servers("internal"), 0);
}

#[test]
fn native_errors_when_engine_missing() {
    let _g = lock();
    let _p = EmptyPath::new();
    assert!(native(vec!["cluster".into(), "list".into()]).is_err());
}

#[test]
fn native_runs_engine_with_args_and_returns_its_exit_code() {
    let _g = lock();
    let (script, out) = fake_engine("fake-k3d");
    let _e = SetEnv::new("CLUSTER_ENGINE", &script);
    assert_eq!(native(vec!["cluster".into(), "list".into(), "--no-headers".into()]).unwrap(), 7);
    assert_eq!(recorded_args(&out), "cluster list --no-headers");
}

#[test]
fn run_cmd_errors_when_engine_missing() {
    let _g = lock();
    let _p = EmptyPath::new();
    for name in [None, Some("internal".to_string()), Some("sit".to_string())] {
        assert!(run_cmd(name).is_err());
    }
}
