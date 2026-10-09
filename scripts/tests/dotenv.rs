use super::*;
use crate::util::testutil::*;

fn pair(k: &str, v: &str) -> Option<(String, String)> {
    Some((k.into(), v.into()))
}

#[test]
fn parse_plain_and_trimmed() {
    assert_eq!(parse_kv_line("PLAIN=hello"), pair("PLAIN", "hello"));
    assert_eq!(parse_kv_line("  SPACED = trimmed  "), pair("SPACED", "trimmed"));
    assert_eq!(parse_kv_line("EMPTY="), pair("EMPTY", ""));
    assert_eq!(parse_kv_line("WITH_EQ=key=val"), pair("WITH_EQ", "key=val"));
}

#[test]
fn parse_unwraps_matching_quotes_only() {
    assert_eq!(parse_kv_line(r#"Q="a b c""#), pair("Q", "a b c"));
    assert_eq!(parse_kv_line("S='x y'"), pair("S", "x y"));
    assert_eq!(parse_kv_line(r#"M="x'"#), pair("M", r#""x'"#));
    assert_eq!(parse_kv_line(r#"ONE=""#), pair("ONE", "\""));
}

#[test]
fn parse_strips_trailing_comment() {
    assert_eq!(parse_kv_line("A=b # note"), pair("A", "b"));
    assert_eq!(parse_kv_line("A=b\t# note"), pair("A", "b"));
    assert_eq!(parse_kv_line("A=b#notcomment"), pair("A", "b#notcomment"));
    assert_eq!(parse_kv_line("A= # only comment"), pair("A", ""));
}

#[test]
fn parse_rejects_non_assignments() {
    assert_eq!(parse_kv_line("# comment=1"), None);
    assert_eq!(parse_kv_line("   # comment=1"), None);
    assert_eq!(parse_kv_line("no equals here"), None);
    assert_eq!(parse_kv_line("=novalue"), None);
    assert_eq!(parse_kv_line("   =x"), None);
    assert_eq!(parse_kv_line("K#=v"), None);
    assert_eq!(parse_kv_line(""), None);
}

#[test]
fn comment_hash_index() {
    assert_eq!(find_comment_hash("a # c"), Some(1));
    assert_eq!(find_comment_hash("a   # c"), Some(1));
    assert_eq!(find_comment_hash(" # c"), Some(0));
    assert_eq!(find_comment_hash("a#c"), None);
    assert_eq!(find_comment_hash("#c"), None);
    assert_eq!(find_comment_hash(""), None);
    // byte index, not char index, after a multibyte char
    assert_eq!(find_comment_hash("é # c"), Some(2));
}

#[test]
fn import_sets_env_and_reports_presence() {
    let _g = lock();
    let d = tmpdir("dotenv");
    let f = d.join(".env");
    fs::write(&f, "# c\nHL_T_A=1\nHL_T_B=\"two words\"\nHL_T_C=3 # tail\n").unwrap();
    assert!(import_dotenv(&f));
    assert_eq!(std::env::var("HL_T_A").unwrap(), "1");
    assert_eq!(std::env::var("HL_T_B").unwrap(), "two words");
    assert_eq!(std::env::var("HL_T_C").unwrap(), "3");
    assert!(!import_dotenv(&d.join("missing.env")));
}

#[test]
fn raw_tf_var_lines_is_literal() {
    let d = tmpdir("rawtf");
    let f = d.join(".env");
    fs::write(
        &f,
        "OTHER=1\nTF_VAR_a=plain\nTF_VAR_b=\"quoted\" # keep\nTF_VAR_noeq\n  TF_VAR_indented=x\nTF_VAR_c=x=y\n",
    )
    .unwrap();
    assert_eq!(
        raw_tf_var_lines(&f).unwrap(),
        vec![
            ("a".to_string(), "plain".to_string()),
            ("b".to_string(), "\"quoted\" # keep".to_string()),
            ("c".to_string(), "x=y".to_string()),
        ]
    );
    assert!(raw_tf_var_lines(&d.join("missing.env")).is_err());
}
