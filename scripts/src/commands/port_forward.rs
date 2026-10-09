// Port of scripts/windows/port-forward-terraform-apps.ps1 /
// scripts/linux/port-forward-terraform-apps.sh.
//
// Browser/SSO: use the TAILNET column. The localhost forwards are for
// non-browser access only (S3 clients, psql, curl) where the Host header
// doesn't matter -- every OIDC app bakes the tailnet origin into its
// redirect_uri.
use crate::dotenv::import_dotenv;
use crate::util::repo_root;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

struct App {
    name: &'static str,
    ns: &'static str,
    svc: &'static str,
    svc_port: u16,
    local_port: u16,
    slug: &'static str,
    path: &'static str,
}

const APPS: &[App] = &[
    App { name: "authentik", ns: "authentik", svc: "authentik-server", svc_port: 80, local_port: 9000, slug: "authentik", path: "" },
    App { name: "gitlab", ns: "gitlab", svc: "gitlab-webservice-default", svc_port: 8181, local_port: 8181, slug: "gitlab", path: "" },
    App { name: "minio (API)", ns: "minio", svc: "minio", svc_port: 9000, local_port: 9002, slug: "minio", path: "" },
    App { name: "minio (browser)", ns: "minio", svc: "minio-console", svc_port: 9001, local_port: 9003, slug: "minio-console", path: "" },
    App { name: "n8n", ns: "n8n", svc: "n8n", svc_port: 5678, local_port: 5678, slug: "n8n", path: "" },
    App { name: "sonarqube", ns: "sonarqube", svc: "sonarqube-sonarqube", svc_port: 9000, local_port: 9010, slug: "sonarqube", path: "" },
    App { name: "nextcloud", ns: "nextcloud", svc: "nextcloud", svc_port: 8080, local_port: 8082, slug: "nextcloud", path: "" },
    App { name: "argocd", ns: "argocd", svc: "argocd-server", svc_port: 80, local_port: 9001, slug: "argocd", path: "" },
    App { name: "grafana", ns: "observability", svc: "observability-grafana", svc_port: 80, local_port: 3000, slug: "grafana", path: "" },
    App { name: "litellm", ns: "litellm", svc: "litellm", svc_port: 4000, local_port: 4000, slug: "litellm", path: "/ui" },
];

pub fn run() -> anyhow::Result<i32> {
    import_dotenv(&repo_root().join(".env"));

    let mut domain = std::env::var("TF_VAR_tailnet_domain").unwrap_or_default();
    if domain.is_empty() {
        if let Ok(ts_host) = std::env::var("TS_HOST") {
            if let Some(idx) = ts_host.find('.') {
                domain = ts_host[idx + 1..].to_string();
            }
        }
    }
    if domain.is_empty() {
        eprintln!("warning: no TF_VAR_tailnet_domain / TS_HOST - TAILNET column will be blank");
    }

    let stop = Arc::new(AtomicBool::new(false));
    let slots: Vec<Arc<Mutex<Option<u32>>>> = APPS.iter().map(|_| Arc::new(Mutex::new(None))).collect();

    {
        let stop = stop.clone();
        let slots = slots.clone();
        ctrlc::set_handler(move || {
            println!("\nstopping port-forwards...");
            stop.store(true, Ordering::SeqCst);
            for slot in &slots {
                if let Ok(guard) = slot.lock() {
                    if let Some(pid) = *guard {
                        kill_pid(pid);
                    }
                }
            }
            std::process::exit(0);
        })?;
    }

    for (i, a) in APPS.iter().enumerate() {
        let slot = slots[i].clone();
        let stop = stop.clone();
        let ns = a.ns.to_string();
        let svc = a.svc.to_string();
        let local_port = a.local_port;
        let svc_port = a.svc_port;
        std::thread::spawn(move || {
            // Respawn loop: kubectl port-forward drops on idle resets /
            // apiserver blips, self-heal within ~2s.
            while !stop.load(Ordering::SeqCst) {
                let child = Command::new("kubectl")
                    .args([
                        "port-forward",
                        "-n",
                        &ns,
                        &format!("svc/{svc}"),
                        &format!("{local_port}:{svc_port}"),
                    ])
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .spawn();
                if let Ok(mut c) = child {
                    *slot.lock().unwrap() = Some(c.id());
                    let _ = c.wait();
                    *slot.lock().unwrap() = None;
                }
                std::thread::sleep(Duration::from_secs(2));
            }
        });
    }

    println!("waiting for port-forwards to come up...");
    std::thread::sleep(Duration::from_secs(3));

    println!(
        "{:<18} {:<32} {:<8} {:<45} {:<8}",
        "APP", "LOCALHOST (CLI/debug only)", "STATUS", "TAILNET (browser/SSO)", "STATUS"
    );
    for a in APPS {
        let local_url = format!("http://localhost:{}{}", a.local_port, a.path);
        let local_status = raw_http_code(&local_url);
        let ts_url = if !domain.is_empty() {
            format!("https://{}.{domain}{}", a.slug, a.path)
        } else {
            String::new()
        };
        let ts_status = if !ts_url.is_empty() { raw_http_code(&ts_url) } else { String::new() };
        println!(
            "{:<18} {:<32} {:<8} {:<45} {:<8}",
            a.name, local_url, local_status, ts_url, ts_status
        );
    }

    println!("\nport-forwards running, Ctrl+C to stop");
    loop {
        std::thread::sleep(Duration::from_secs(1));
    }
}

fn kill_pid(pid: u32) {
    if cfg!(windows) {
        let _ = Command::new("taskkill")
            .args(["/PID", &pid.to_string(), "/T", "/F"])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    } else {
        let _ = Command::new("kill")
            .args(["-9", &pid.to_string()])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    }
}

fn raw_http_code(url: &str) -> String {
    let null_dev = if cfg!(windows) { "NUL" } else { "/dev/null" };
    crate::util::capture(
        "curl",
        &["-sk", "-o", null_dev, "-m", "3", "--connect-timeout", "3", "-w", "%{http_code}", url],
    )
}

#[cfg(test)]
#[path = "../../tests/port_forward.rs"]
mod tests;
