use std::process::{Command, ExitStatus, Stdio};

/// Run a shell-style pipeline of commands, each stage's stdout feeding the
/// next stage's stdin; the final stage's stdout/stderr are inherited.
/// Mirrors `cmd1 | cmd2 | cmd3` without needing an actual shell.
pub fn pipe_chain(cmds: Vec<(&str, Vec<String>)>) -> anyhow::Result<ExitStatus> {
    let mut children = Vec::new();
    let mut prev_stdout = None;
    let n = cmds.len();
    for (i, (cmd, args)) in cmds.into_iter().enumerate() {
        let mut c = Command::new(cmd);
        c.args(&args);
        if let Some(stdout) = prev_stdout.take() {
            c.stdin(stdout);
        }
        let is_last = i == n - 1;
        c.stdout(if is_last {
            Stdio::inherit()
        } else {
            Stdio::piped()
        });
        c.stderr(Stdio::inherit());
        let mut child = c.spawn()?;
        if !is_last {
            prev_stdout = child.stdout.take();
        }
        children.push(child);
    }
    let mut last_status = None;
    for child in &mut children {
        last_status = Some(child.wait()?);
    }
    Ok(last_status.expect("pipeline must have at least one stage"))
}

#[cfg(test)]
#[path = "../tests/pipe.rs"]
mod tests;
