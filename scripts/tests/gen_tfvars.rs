use super::*;
use crate::util::testutil::*;

#[test]
fn declared_variables_scans_top_level_tf_only() {
    let d = fake_repo(
        "declared",
        &[
            ("a.tf", "variable \"x\" {}\nvariable   \"y\" {\n}\nresource \"r\" \"n\" {}\n"),
            ("b.txt", "variable \"ignored\" {}"),
            ("sub/c.tf", "variable \"nested\" {}"),
        ],
    );
    let mut names: Vec<_> = declared_variables(&d).unwrap().into_iter().collect();
    names.sort();
    assert_eq!(names, ["x", "y"]);
    assert!(declared_variables(&d.join("nope")).is_err());
}

#[test]
fn run_writes_filtered_tfvars_per_env() {
    let _g = lock();
    let repo = fake_repo(
        "gentf",
        &[
            (".env", "TF_VAR_a=1\nTF_VAR_b=2\nTF_VAR_zzz=3\nNOT_TF=9\n"),
            ("terraform/internal/main.tf", "variable \"a\" {}\nvariable \"b\" {}\n"),
            ("terraform/sit/main.tf", "variable \"b\" {}\n"),
            ("terraform/uat/main.tf", "variable \"q\" {}\n"),
        ],
    );
    let _cwd = Cwd::set(&repo);
    assert_eq!(run().unwrap(), 0);
    let read = |e: &str| fs::read_to_string(repo.join("terraform").join(e).join("local.auto.tfvars")).unwrap();
    assert_eq!(read("internal"), "a = \"1\"\nb = \"2\"\n");
    assert_eq!(read("sit"), "b = \"2\"\n");
    assert_eq!(read("uat"), "");
    assert!(!repo.join("terraform").join("production").exists());
}

#[test]
fn native_errors_when_engine_missing() {
    let _g = lock();
    let _p = EmptyPath::new();
    assert!(native(vec!["plan".into()]).is_err());
}

#[test]
fn native_runs_engine_with_args_and_returns_its_exit_code() {
    let _g = lock();
    let (script, out) = fake_engine("fake-tf");
    let _e = SetEnv::new("TERRAFORM_ENGINE", &script);
    let code = native(vec!["-chdir=terraform/internal".into(), "apply".into(), "-auto-approve".into()]).unwrap();
    assert_eq!(code, 7);
    assert_eq!(recorded_args(&out), "-chdir=terraform/internal apply -auto-approve");
}

#[test]
fn run_errors_without_env_file() {
    let _g = lock();
    let repo = fake_repo("gentf-noenv", &[]);
    let _cwd = Cwd::set(&repo);
    assert!(run().is_err());
}
