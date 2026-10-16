use super::*;
use crate::util::testutil::*;

fn parse(args: &[&str]) -> Command {
    let mut v = vec!["homelab"];
    v.extend(args);
    Cli::try_parse_from(v).unwrap().command
}

#[test]
fn cli_definition_is_valid() {
    use clap::CommandFactory;
    Cli::command().debug_assert();
}

#[test]
fn ansible_run_parses_playbook_and_trailing_args() {
    match parse(&[
        "ansible",
        "run",
        "role-accounts",
        "--tags",
        "x",
        "-e",
        "k=v",
    ]) {
        Command::Ansible {
            action: AnsibleAction::Run { playbook, args },
        } => {
            assert_eq!(playbook.as_deref(), Some("role-accounts"));
            assert_eq!(args, ["--tags", "x", "-e", "k=v"]);
        }
        _ => panic!("wrong variant"),
    }
    match parse(&["ansible", "run"]) {
        Command::Ansible {
            action: AnsibleAction::Run { playbook, args },
        } => {
            assert!(playbook.is_none() && args.is_empty());
        }
        _ => panic!("wrong variant"),
    }
}

#[test]
fn ansible_other_is_native_passthrough() {
    match parse(&["ansible", "all", "-m", "ping"]) {
        Command::Ansible {
            action: AnsibleAction::Passthrough(a),
        } => assert_eq!(a, ["all", "-m", "ping"]),
        _ => panic!("wrong variant"),
    }
}

#[test]
fn cluster_create_and_native_parse() {
    match parse(&["k8s", "create", "sit"]) {
        Command::K8S {
            action: ClusterAction::Create { name },
        } => assert_eq!(name.as_deref(), Some("sit")),
        _ => panic!("wrong variant"),
    }
    match parse(&["k8s", "create"]) {
        Command::K8S {
            action: ClusterAction::Create { name },
        } => assert!(name.is_none()),
        _ => panic!("wrong variant"),
    }
    match parse(&["k8s", "list"]) {
        Command::K8S {
            action: ClusterAction::Passthrough(a),
        } => assert_eq!(a, ["list"]),
        _ => panic!("wrong variant"),
    }
}

#[test]
fn tf_genvars_and_native_parse() {
    assert!(matches!(
        parse(&["tf", "genvars"]),
        Command::Tf {
            action: Some(TerraformAction::Genvars)
        }
    ));
    match parse(&["tf", "apply", "-auto-approve"]) {
        Command::Tf {
            action: Some(TerraformAction::Passthrough(a)),
        } => assert_eq!(a, ["apply", "-auto-approve"]),
        _ => panic!("wrong variant"),
    }
    assert!(matches!(
        parse(&["tf"]),
        Command::Tf { action: None }
    ));
    assert!(Cli::try_parse_from(["homelab", "terraform", "plan"]).is_err());
    assert!(Cli::try_parse_from(["homelab", "gen-tfvars"]).is_err());
}

#[test]
fn native_subcommand_takes_everything_verbatim() {
    match parse(&[
        "tf",
        "native",
        "-chdir=x",
        "apply",
        "-auto-approve",
        "--help",
    ]) {
        Command::Tf {
            action: Some(TerraformAction::Native { args }),
        } => {
            assert_eq!(args, ["-chdir=x", "apply", "-auto-approve", "--help"]);
        }
        _ => panic!("wrong variant"),
    }
    match parse(&["ansible", "native", "--version"]) {
        Command::Ansible {
            action: AnsibleAction::Native { args },
        } => assert_eq!(args, ["--version"]),
        _ => panic!("wrong variant"),
    }
    match parse(&["k8s", "native", "k8s", "list"]) {
        Command::K8S {
            action: ClusterAction::Native { args },
        } => assert_eq!(args, ["k8s", "list"]),
        _ => panic!("wrong variant"),
    }
    match parse(&["k8s", "native"]) {
        Command::K8S {
            action: ClusterAction::Native { args },
        } => assert!(args.is_empty()),
        _ => panic!("wrong variant"),
    }
}

#[test]
fn simple_subcommands_parse() {
    assert!(matches!(parse(&["list-urls"]), Command::ListUrls));
    assert!(matches!(parse(&["omp-shell"]), Command::OmpShell));
    assert!(matches!(parse(&["port-forward"]), Command::PortForward));
    assert!(matches!(
        parse(&["reset-nextcloud"]),
        Command::ResetNextcloud
    ));
    assert!(matches!(parse(&["env-test"]), Command::EnvTest));
}

#[test]
fn old_names_and_missing_command_rejected() {
    assert!(Cli::try_parse_from(["homelab", "ansible-run"]).is_err());
    assert!(Cli::try_parse_from(["homelab", "create-cluster"]).is_err());
    assert!(Cli::try_parse_from(["homelab"]).is_err());
}

#[test]
fn dispatch_native_forms_reach_the_engine() {
    let _g = lock();
    let (tf, tf_out) = fake_engine("disp-tf");
    let (cl, cl_out) = fake_engine("disp-cl");
    let _a = SetEnv::new("TERRAFORM_ENGINE", &tf);
    let _b = SetEnv::new("CLUSTER_ENGINE", &cl);
    // explicit `native` (flag-first ok) and bare shorthand both land on the engine
    assert_eq!(
        dispatch(parse(&["tf", "native", "-chdir=x", "plan"])).unwrap(),
        7
    );
    assert_eq!(recorded_args(&tf_out), "-chdir=x plan");
    assert_eq!(dispatch(parse(&["tf", "apply"])).unwrap(), 7);
    assert_eq!(recorded_args(&tf_out), "apply");
    assert_eq!(dispatch(parse(&["tf"])).unwrap(), 7);
    assert_eq!(recorded_args(&tf_out), "");
    assert_eq!(dispatch(parse(&["k8s", "native", "version"])).unwrap(), 7);
    assert_eq!(recorded_args(&cl_out), "version");
    assert_eq!(dispatch(parse(&["k8s", "list"])).unwrap(), 7);
    assert_eq!(recorded_args(&cl_out), "list");
}

#[test]
fn dispatch_routes_commands() {
    let _g = lock();
    assert_eq!(dispatch(Command::EnvTest).unwrap(), 0);
    let _p = EmptyPath::new();
    assert!(dispatch(parse(&["ansible", "all"])).is_err());
    assert!(dispatch(parse(&["k8s", "list"])).is_err());
    assert!(dispatch(parse(&["tf", "plan"])).is_err());
    assert!(dispatch(parse(&["tf", "native", "plan"])).is_err());
    assert!(dispatch(parse(&["ansible", "native", "--version"])).is_err());
    assert!(dispatch(parse(&["k8s", "native", "version"])).is_err());
    assert!(dispatch(parse(&["k8s", "create", "internal"])).is_err());
    assert!(dispatch(parse(&["ansible", "run", "n8n"])).is_err());
    assert!(dispatch(Command::ResetNextcloud).is_err());
}
