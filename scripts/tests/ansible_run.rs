use super::*;
use crate::util::testutil::*;

// fan_out (and run(None)) re-exec current_exe(), which under `cargo test`
// is the test harness itself -- not safe to call here.

#[test]
fn single_playbook_errors_when_kubectl_missing() {
    let _g = lock();
    let _p = EmptyPath::new();
    assert!(single_playbook("n8n", vec!["--syntax-check".into()]).is_err());
}

#[test]
fn run_with_playbook_dispatches_to_single_playbook() {
    let _g = lock();
    let _p = EmptyPath::new();
    assert!(run(Some("role-accounts".into()), vec![]).is_err());
}

#[test]
fn native_errors_when_ansible_missing() {
    let _g = lock();
    let _p = EmptyPath::new();
    assert!(native(vec!["all".into(), "-m".into(), "ping".into()]).is_err());
}

#[test]
fn format_help_lists_playbooks_and_forms() {
    let h = format_help(&["n8n".to_string(), "site".to_string()]);
    assert!(h.contains("Available playbooks:
  n8n
  site
"), "{h}");
    assert!(h.contains("n8n, omp, litellm, mcp-servers, openwebui"));
    assert!(h.contains("<path>.yml"));
    assert!(format_help(&[]).contains("run from inside the repo"));
}

#[test]
fn help_lists_repo_playbooks_sorted() {
    let _g = lock();
    let repo = fake_repo(
        "help",
        &[
            ("helm/ansible/playbooks/zeta.yml", ""),
            ("helm/ansible/playbooks/alpha.yaml", ""),
            ("helm/ansible/playbooks/notes.txt", ""),
        ],
    );
    let _cwd = Cwd::set(&repo);
    let h = help();
    assert!(h.contains("Available playbooks:
  alpha
  zeta
"), "{h}");
    assert!(!h.contains("notes"));
}

#[test]
fn custom_playbook_needs_existing_yaml_file() {
    let d = tmpdir("custom");
    let yml = d.join("my.yml");
    std::fs::write(&yml, "").unwrap();
    std::fs::write(d.join("my.txt"), "").unwrap();
    assert_eq!(custom_playbook(yml.to_str().unwrap()), Some(yml.as_path()));
    assert!(custom_playbook(d.join("my.txt").to_str().unwrap()).is_none());
    assert!(custom_playbook(d.join("missing.yml").to_str().unwrap()).is_none());
    assert!(custom_playbook("n8n").is_none());
}

#[test]
fn label_of_is_dns_safe() {
    assert_eq!(label_of("My_Play.book"), "my-play-book");
    assert_eq!(label_of("-x-"), "x");
}

#[test]
fn custom_playbook_errors_when_kubectl_missing() {
    let _g = lock();
    let d = tmpdir("custom-run");
    let yml = d.join("my.yml");
    std::fs::write(&yml, "").unwrap();
    let _p = EmptyPath::new();
    assert!(single_playbook(yml.to_str().unwrap(), vec![]).is_err());
}
