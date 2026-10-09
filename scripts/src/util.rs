use std::path::PathBuf;
use std::process::{Command, ExitStatus};

/// Find the repo root by walking up from the current directory looking for
/// AGENT.md (unique marker file in this repo). Falls back to the current
/// directory if never found, so the binary still runs from anywhere -- the
/// original scripts derived this from $PSScriptRoot instead, but this CLI
/// isn't necessarily invoked from inside the repo's scripts dir.
pub fn repo_root() -> PathBuf {
    let mut dir = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    loop {
        if dir.join("AGENT.md").is_file() {
            return dir;
        }
        if !dir.pop() {
            return std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
        }
    }
}

/// Run a command, inheriting stdio, returning its exit status.
pub fn run(cmd: &str, args: &[&str]) -> anyhow::Result<ExitStatus> {
    Ok(Command::new(cmd).args(args).status()?)
}

/// Run a command, capturing stdout as a trimmed String. Ignores exit code
/// (callers check stdout emptiness / parse content, matching how the
/// PowerShell scripts largely do `2>$null` and look at output).
pub fn capture(cmd: &str, args: &[&str]) -> String {
    match Command::new(cmd).args(args).output() {
        Ok(out) => String::from_utf8_lossy(&out.stdout).trim().to_string(),
        Err(_) => String::new(),
    }
}

pub fn capture_status(cmd: &str, args: &[&str]) -> (String, bool) {
    match Command::new(cmd).args(args).output() {
        Ok(out) => (
            String::from_utf8_lossy(&out.stdout).trim().to_string(),
            out.status.success(),
        ),
        Err(_) => (String::new(), false),
    }
}

pub fn current_exe() -> PathBuf {
    std::env::current_exe().expect("could not determine current executable path")
}

pub fn job_id(prefix: &str) -> String {
    use rand::RngExt;
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let suffix: u32 = rand::rng().random_range(0..99999);
    format!("{prefix}-{now}-{suffix}")
}

/// Cluster engine binary. Set CLUSTER_ENGINE in .env or the environment
/// (default: Cargo.toml cluster_engine, "k3d"). ponytail: swaps only the binary -- create_cluster.rs still
/// speaks k3d's CLI dialect, so it must be k3d-compatible.
pub fn engine() -> String {
    env_binary("CLUSTER_ENGINE", "cluster_engine", "k3d")
}

/// IaC binary for `homelab terraform ...`. Set TERRAFORM_ENGINE in .env or the
/// environment (default: Cargo.toml terraform_engine, "tofu", what this repo uses; set "terraform" for HashiCorp's).
pub fn tf_engine() -> String {
    env_binary("TERRAFORM_ENGINE", "terraform_engine", "tofu")
}

/// Build-time defaults live in Cargo.toml's [package.metadata.homelab].
const MANIFEST: &str = include_str!("../Cargo.toml");

fn manifest_value(manifest: &str, key: &str) -> Option<String> {
    manifest.lines().find_map(|l| {
        let (k, v) = l.split_once('=')?;
        (k.trim() == key).then(|| v.trim().trim_matches('"').to_string())
    })
}

/// env var / .env > Cargo.toml metadata > hardcoded fallback.
fn env_binary(var: &str, key: &str, fallback: &str) -> String {
    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(|| {
        crate::dotenv::import_dotenv(&repo_root().join(".env"));
    });
    std::env::var(var)
        .ok()
        .or_else(|| manifest_value(MANIFEST, key))
        .unwrap_or_else(|| fallback.to_string())
}

#[cfg(test)]
#[path = "../tests/testutil.rs"]
pub mod testutil;

#[cfg(test)]
#[path = "../tests/util.rs"]
mod tests;
