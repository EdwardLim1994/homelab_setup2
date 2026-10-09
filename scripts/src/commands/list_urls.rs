// Port of scripts/windows/list-urls.ps1 / scripts/linux/list-urls.sh.
use crate::dotenv::import_dotenv;
use crate::util::{capture, repo_root};
use std::collections::HashMap;

struct App {
    name: &'static str,
    host: &'static str,
    ingress: &'static str,
    path: &'static str,
}

const APPS: &[App] = &[
    App { name: "authentik", host: "authentik", ingress: "authentik.local", path: "" },
    App { name: "gitlab", host: "gitlab", ingress: "gitlab.local", path: "" },
    App { name: "minio (API)", host: "minio", ingress: "minio.local", path: "" },
    App { name: "minio (console)", host: "minio-console", ingress: "minio-console.local", path: "" },
    App { name: "n8n", host: "n8n", ingress: "", path: "" },
    App { name: "sonarqube", host: "sonarqube", ingress: "sonarqube.local", path: "" },
    App { name: "nextcloud", host: "nextcloud", ingress: "nextcloud.local", path: "" },
    App { name: "argocd", host: "argocd", ingress: "argocd.local", path: "" },
    App { name: "grafana", host: "grafana", ingress: "grafana.local", path: "" },
    App { name: "litellm", host: "litellm", ingress: "", path: "/ui" },
    App { name: "openwebui", host: "openwebui", ingress: "", path: "" },
    App { name: "kafka-ui", host: "kafka-ui", ingress: "", path: "" },
    App { name: "harbor", host: "harbor", ingress: "harbor.local", path: "" },
    App { name: "kaneo", host: "kaneo", ingress: "kaneo.local", path: "" },
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
        eprintln!("warning: can't determine tailnet domain - set TF_VAR_tailnet_domain or TS_HOST in .env");
    }

    let timeout: u32 = std::env::var("LIST_URLS_TIMEOUT")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(20);

    let ts_hosts = ts_hosts_from_ingresses();

    println!("{:<18} {:<45} {:<14}", "APP", "TAILSCALE (operator)", "STATUS");
    for a in APPS {
        let ts_host = ts_hosts
            .get(&format!("ts-{}", a.host))
            .cloned()
            .unwrap_or_else(|| format!("{}.{}", a.host, domain));
        let ts_url = format!("https://{ts_host}{}", a.path);
        let status = http_status(&ts_url, timeout);
        println!("{:<18} {:<45} {:<14}", a.name, ts_url, status);
    }

    println!();
    println!("LAN fallback (need hosts-file entry + trust the homelab CA):");
    for a in APPS {
        if !a.ingress.is_empty() {
            println!("  https://{}  ({})", a.ingress, a.name);
        }
    }

    Ok(0)
}

fn ts_hosts_from_ingresses() -> HashMap<String, String> {
    let jp = r#"{range .items[?(@.spec.ingressClassName=="tailscale")]}{.metadata.name}{"\t"}{.status.loadBalancer.ingress[0].hostname}{"\n"}{end}"#;
    let out = capture("kubectl", &["get", "ingress", "-A", "-o", &format!("jsonpath={jp}")]);
    parse_ts_hosts(&out)
}

fn parse_ts_hosts(out: &str) -> HashMap<String, String> {
    let mut map = HashMap::new();
    for line in out.lines() {
        let mut parts = line.splitn(2, '\t');
        if let (Some(n), Some(h)) = (parts.next(), parts.next()) {
            if !n.is_empty() && !h.is_empty() {
                map.insert(n.to_string(), h.to_string());
            }
        }
    }
    map
}

/// curl.exe without -L: SSO apps 302/307 to a login page, no need to follow.
/// 2xx/3xx/401/403 all mean "app is up".
fn http_status(url: &str, timeout: u32) -> String {
    let null_dev = if cfg!(windows) { "NUL" } else { "/dev/null" };
    let code = capture(
        "curl",
        &[
            "-sk",
            "-o",
            null_dev,
            "-m",
            &timeout.to_string(),
            "--connect-timeout",
            "5",
            "-w",
            "%{http_code}",
            url,
        ],
    );
    classify(&code)
}

fn classify(code: &str) -> String {
    if code.is_empty() || code.chars().all(|c| c == '0') {
        return "unreachable".to_string();
    }
    let ok = code.len() == 3
        && (code.starts_with('2') || code.starts_with('3') || code == "401" || code == "403");
    if ok {
        format!("OK ({code})")
    } else {
        format!("DOWN ({code})")
    }
}

#[cfg(test)]
#[path = "../../tests/list_urls.rs"]
mod tests;
