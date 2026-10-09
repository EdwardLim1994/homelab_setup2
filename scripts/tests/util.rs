use super::testutil::*;
use super::*;

fn refs(v: &[String]) -> Vec<&str> {
    v.iter().map(String::as_str).collect()
}

#[test]
fn repo_root_walks_up_to_agent_md() {
    let _g = lock();
    let repo = fake_repo("root", &[("a/b/x.txt", "")]);
    let _cwd = Cwd::set(&repo.join("a").join("b"));
    assert_eq!(repo_root().canonicalize().unwrap(), repo.canonicalize().unwrap());
}

#[test]
fn repo_root_falls_back_to_cwd_when_no_marker() {
    let _g = lock();
    let d = tmpdir("nomarker");
    let _cwd = Cwd::set(&d);
    assert_eq!(repo_root().canonicalize().unwrap(), d.canonicalize().unwrap());
}

#[test]
fn run_returns_exit_status() {
    let (c, a) = sh("exit 0");
    assert!(run(c, &refs(&a)).unwrap().success());
    let (c, a) = sh("exit 3");
    assert_eq!(run(c, &refs(&a)).unwrap().code(), Some(3));
    assert!(run("homelab-no-such-binary", &[]).is_err());
}

#[test]
fn capture_trims_stdout_and_swallows_spawn_errors() {
    let (c, a) = sh("echo hi");
    assert_eq!(capture(c, &refs(&a)), "hi");
    assert_eq!(capture("homelab-no-such-binary", &[]), "");
}

#[test]
fn capture_status_reports_success_flag() {
    let (c, a) = sh("echo hi");
    assert_eq!(capture_status(c, &refs(&a)), ("hi".to_string(), true));
    let (c, a) = sh("exit 3");
    assert!(!capture_status(c, &refs(&a)).1);
    assert_eq!(capture_status("homelab-no-such-binary", &[]), (String::new(), false));
}

#[test]
fn current_exe_points_at_a_file() {
    assert!(current_exe().is_file());
}

#[test]
fn job_id_is_prefix_timestamp_suffix() {
    let id = job_id("ansible-n8n");
    let rest = id.strip_prefix("ansible-n8n-").expect("prefix");
    let mut parts = rest.split('-');
    assert!(parts.next().unwrap().parse::<u64>().unwrap() > 1_600_000_000);
    assert!(parts.next().unwrap().parse::<u32>().unwrap() < 99999);
    assert!(parts.next().is_none());
}

#[test]
fn tf_engine_defaults_to_tofu_and_honours_env() {
    let _g = lock();
    let old = std::env::var_os("TERRAFORM_ENGINE");
    std::env::remove_var("TERRAFORM_ENGINE");
    assert_eq!(tf_engine(), "tofu");
    std::env::set_var("TERRAFORM_ENGINE", "terraform");
    assert_eq!(tf_engine(), "terraform");
    match old {
        Some(v) => std::env::set_var("TERRAFORM_ENGINE", v),
        None => std::env::remove_var("TERRAFORM_ENGINE"),
    }
}

#[test]
fn engine_defaults_to_k3d_and_honours_env() {
    let _g = lock();
    let old = std::env::var_os("CLUSTER_ENGINE");
    std::env::remove_var("CLUSTER_ENGINE");
    assert_eq!(engine(), "k3d");
    std::env::set_var("CLUSTER_ENGINE", "kind");
    assert_eq!(engine(), "kind");
    match old {
        Some(v) => std::env::set_var("CLUSTER_ENGINE", v),
        None => std::env::remove_var("CLUSTER_ENGINE"),
    }
}

#[test]
fn manifest_value_reads_cargo_toml_metadata() {
    let m = "[package]
name = \"x\"
[package.metadata.homelab]
cluster_engine = \"kind\"
terraform_engine=\"terraform\"
";
    assert_eq!(manifest_value(m, "cluster_engine").as_deref(), Some("kind"));
    assert_eq!(manifest_value(m, "terraform_engine").as_deref(), Some("terraform"));
    assert_eq!(manifest_value(m, "missing"), None);
    // the real manifest ships both defaults
    assert_eq!(manifest_value(MANIFEST, "cluster_engine").as_deref(), Some("k3d"));
    assert_eq!(manifest_value(MANIFEST, "terraform_engine").as_deref(), Some("tofu"));
}