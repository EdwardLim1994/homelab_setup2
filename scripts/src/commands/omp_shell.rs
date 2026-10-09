// Port of scripts/windows/omp-shell.ps1 / scripts/linux/omp-shell.sh.
// Wake the omp pod, drop into its TUI, scale it back to 0 on exit (any path
// out -- normal exit or Ctrl+C).
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

pub fn run() -> anyhow::Result<i32> {
    let ns = std::env::var("NS").unwrap_or_else(|_| "omp".to_string());
    let deploy = std::env::var("DEPLOY").unwrap_or_else(|_| "omp".to_string());

    let scaled_down = Arc::new(AtomicBool::new(false));
    {
        let ns = ns.clone();
        let deploy = deploy.clone();
        let scaled_down = scaled_down.clone();
        ctrlc::set_handler(move || {
            scale_down(&ns, &deploy, &scaled_down);
            std::process::exit(130);
        })?;
    }

    let _ = Command::new("kubectl")
        .args(["-n", &ns, "scale", &format!("deploy/{deploy}"), "--replicas=1"])
        .stdout(Stdio::null())
        .status();
    let _ = Command::new("kubectl")
        .args(["-n", &ns, "rollout", "status", &format!("deploy/{deploy}"), "--timeout=120s"])
        .status();

    // The pod's PID 1 is pod-openai.py (the :4096 shim); `omp` starts the
    // TUI alongside it.
    let _ = Command::new("kubectl")
        .args(["-n", &ns, "exec", "-it", &format!("deploy/{deploy}"), "--", "omp"])
        .status();

    println!();
    println!("Scaling {deploy} back to 0...");
    scale_down(&ns, &deploy, &scaled_down);

    Ok(0)
}

fn scale_down(ns: &str, deploy: &str, scaled_down: &AtomicBool) {
    if scaled_down.swap(true, Ordering::SeqCst) {
        return;
    }
    let _ = Command::new("kubectl")
        .args(["-n", ns, "scale", &format!("deploy/{deploy}"), "--replicas=0"])
        .stdout(Stdio::null())
        .status();
}

#[cfg(test)]
#[path = "../../tests/omp_shell.rs"]
mod tests;
