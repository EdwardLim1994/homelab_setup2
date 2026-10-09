use super::*;
use crate::util::testutil::*;

#[test]
fn classify_buckets() {
    assert_eq!(classify(""), "unreachable");
    assert_eq!(classify("000"), "unreachable");
    assert_eq!(classify("200"), "OK (200)");
    assert_eq!(classify("302"), "OK (302)");
    assert_eq!(classify("401"), "OK (401)");
    assert_eq!(classify("403"), "OK (403)");
    assert_eq!(classify("404"), "DOWN (404)");
    assert_eq!(classify("502"), "DOWN (502)");
    assert_eq!(classify("20"), "DOWN (20)");
}

#[test]
fn parse_ts_hosts_keeps_complete_rows_only() {
    let m = parse_ts_hosts("ts-n8n\tn8n.tail.ts.net\nts-empty\t\n\tnoname.ts.net\nbroken\nts-gl\tgl.ts.net");
    assert_eq!(m.len(), 2);
    assert_eq!(m["ts-n8n"], "n8n.tail.ts.net");
    assert_eq!(m["ts-gl"], "gl.ts.net");
    assert!(parse_ts_hosts("").is_empty());
}

#[test]
fn ts_hosts_from_ingresses_empty_without_kubectl() {
    let _g = lock();
    let _p = EmptyPath::new();
    assert!(ts_hosts_from_ingresses().is_empty());
}

#[test]
fn http_status_unreachable_for_closed_port() {
    assert_eq!(http_status("http://127.0.0.1:1", 1), "unreachable");
}

#[test]
fn run_prints_table_without_cluster() {
    let _g = lock();
    let repo = fake_repo(
        "listurls",
        &[(".env", "TF_VAR_tailnet_domain=invalid.invalid\nLIST_URLS_TIMEOUT=1\n")],
    );
    let _cwd = Cwd::set(&repo);
    let _p = EmptyPath::new();
    assert_eq!(run().unwrap(), 0);
}
