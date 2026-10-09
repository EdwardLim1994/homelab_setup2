use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{Mutex, MutexGuard};

static LOCK: Mutex<()> = Mutex::new(());

/// Serialise tests that touch process-global state (env vars, cwd).
pub fn lock() -> MutexGuard<'static, ()> {
    let g = LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let _ = super::engine(); // burn the one-shot .env import before tests set vars
    g
}

pub fn tmpdir(tag: &str) -> PathBuf {
    static N: AtomicU32 = AtomicU32::new(0);
    let d = std::env::temp_dir().join(format!(
        "homelab-test-{}-{tag}-{}",
        std::process::id(),
        N.fetch_add(1, Ordering::SeqCst)
    ));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    d
}

/// Points PATH at an empty dir so kubectl/k3d/docker/ansible are "not
/// installed" -- shell-out code paths fail fast without touching a cluster.
pub struct EmptyPath(Option<OsString>);
impl EmptyPath {
    pub fn new() -> Self {
        let old = std::env::var_os("PATH");
        std::env::set_var("PATH", tmpdir("path"));
        Self(old)
    }
}
impl Drop for EmptyPath {
    fn drop(&mut self) {
        match self.0.take() {
            Some(p) => std::env::set_var("PATH", p),
            None => std::env::remove_var("PATH"),
        }
    }
}

pub struct Cwd(PathBuf);
impl Cwd {
    pub fn set(p: &Path) -> Self {
        let old = std::env::current_dir().unwrap();
        std::env::set_current_dir(p).unwrap();
        Self(old)
    }
}
impl Drop for Cwd {
    fn drop(&mut self) {
        let _ = std::env::set_current_dir(&self.0);
    }
}

/// Fake repo root: AGENT.md marker + extra files.
pub fn fake_repo(tag: &str, files: &[(&str, &str)]) -> PathBuf {
    let d = tmpdir(tag);
    std::fs::write(d.join("AGENT.md"), "").unwrap();
    for (rel, body) in files {
        let p = d.join(rel);
        std::fs::create_dir_all(p.parent().unwrap()).unwrap();
        std::fs::write(p, body).unwrap();
    }
    d
}

/// Cross-platform "run this snippet" command.
pub fn sh(script: &str) -> (&'static str, Vec<String>) {
    if cfg!(windows) {
        ("cmd", vec!["/C".into(), script.into()])
    } else {
        ("sh", vec!["-c".into(), script.into()])
    }
}

/// Restores an env var to its previous value on drop.
pub struct SetEnv(String, Option<OsString>);
impl SetEnv {
    pub fn new(k: &str, v: impl AsRef<std::ffi::OsStr>) -> Self {
        let old = std::env::var_os(k);
        std::env::set_var(k, v);
        Self(k.to_string(), old)
    }
}
impl Drop for SetEnv {
    fn drop(&mut self) {
        match self.1.take() {
            Some(v) => std::env::set_var(&self.0, v),
            None => std::env::remove_var(&self.0),
        }
    }
}

/// Mock engine binary: records its args (space-joined) to the returned file
/// and exits 7. Point CLUSTER_ENGINE / TERRAFORM_ENGINE at the returned path.
pub fn fake_engine(tag: &str) -> (PathBuf, PathBuf) {
    let d = tmpdir(tag);
    let out = d.join("out.txt");
    let script = if cfg!(windows) {
        let s = d.join("fake.cmd");
        std::fs::write(&s, "@echo off
echo(%*> \"%~dp0out.txt\"
exit /b 7
").unwrap();
        s
    } else {
        let s = d.join("fake.sh");
        std::fs::write(&s, "#!/bin/sh
printf '%s ' \"$@\" > \"$(dirname \"$0\")/out.txt\"
exit 7
").unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&s, std::fs::Permissions::from_mode(0o755)).unwrap();
        }
        s
    };
    (script, out)
}

pub fn recorded_args(out: &Path) -> String {
    // cmd.exe batch quoting: Rust wraps args containing `=` in quotes for .cmd targets
    std::fs::read_to_string(out).unwrap().replace('"', "").trim().to_string()
}
