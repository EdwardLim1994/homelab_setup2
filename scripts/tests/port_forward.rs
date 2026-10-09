use super::*;

// run() loops forever and installs a ctrlc handler -- not unit-testable.

#[test]
fn kill_pid_terminates_process() {
    let mut cmd = if cfg!(windows) {
        let mut c = Command::new("ping");
        c.args(["-n", "30", "127.0.0.1"]);
        c
    } else {
        let mut c = Command::new("sleep");
        c.arg("30");
        c
    };
    let mut child = cmd.stdout(Stdio::null()).spawn().unwrap();
    kill_pid(child.id());
    assert!(!child.wait().unwrap().success());
}

#[test]
fn kill_pid_ignores_dead_pid() {
    kill_pid(u32::MAX); // must not panic
}

#[test]
fn raw_http_code_for_closed_port() {
    let code = raw_http_code("http://127.0.0.1:1");
    assert!(code == "000" || code.is_empty(), "{code}");
}
