// Port of scripts/windows/create-cluster.ps1 / scripts/linux/create-cluster.sh.
use crate::util::{capture, current_exe, engine, run};
use std::fs;
use std::process::{Command, Stdio};

// ponytail: bare `homelab cluster ...` just execs the configured engine.
pub fn native(args: Vec<String>) -> anyhow::Result<i32> {
    Ok(Command::new(engine()).args(args).status()?.code().unwrap_or(1))
}

fn env_or(name: &str, default: &str) -> String {
    std::env::var(name).unwrap_or_else(|_| default.to_string())
}

pub fn run_cmd(cluster_name: Option<String>) -> anyhow::Result<i32> {
    let registry_mirror_port = env_or("REGISTRY_MIRROR_PORT", "30500");
    let mimir_push_port = env_or("MIMIR_PUSH_PORT", "30510");
    let loki_push_port = env_or("LOKI_PUSH_PORT", "30511");
    let tempo_push_port = env_or("TEMPO_PUSH_PORT", "30512");

    if cluster_name.as_deref() == Some("phases") {
        let exe = current_exe();
        for phase in ["sit", "uat", "production"] {
            println!("=== {phase} ===");
            let _ = Command::new(&exe).args(["cluster", "create", phase]).status();
        }
        return Ok(0);
    }

    let cluster_name = cluster_name.unwrap_or_else(|| env_or("K3D_CLUSTER_NAME", "internal"));
    let is_phase = matches!(cluster_name.as_str(), "sit" | "uat" | "production");
    let storage_volume = env_or("K3D_STORAGE_VOLUME", &format!("k3d-{cluster_name}-storage"));

    let kafka_nodeport = std::env::var("KAFKA_NODEPORT").ok().or_else(|| {
        match cluster_name.as_str() {
            "sit" => Some("30901".to_string()),
            "uat" => Some("30902".to_string()),
            "production" => Some("30903".to_string()),
            _ => None,
        }
    });
    let apicurio_nodeport = std::env::var("APICURIO_NODEPORT").ok().or_else(|| {
        match cluster_name.as_str() {
            "sit" => Some("30911".to_string()),
            "uat" => Some("30912".to_string()),
            "production" => Some("30913".to_string()),
            _ => None,
        }
    });

    if cluster_servers(&cluster_name) > 0 {
        println!(
            "k3d cluster '{cluster_name}' already exists - skipping (delete it first if you want to recreate)."
        );
        let vol_exists = Command::new("docker")
            .args(["volume", "inspect", &storage_volume])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        if !vol_exists {
            println!("WARNING: docker volume '{storage_volume}' is missing but the cluster is running -");
            println!("         PVC data is likely lost and pods will fail on restart. Recreate:");
            println!("         k3d cluster delete {cluster_name}; homelab cluster create {cluster_name}");
        }
        if cluster_name == "internal" {
            for port in [&registry_mirror_port, &mimir_push_port, &loki_push_port, &tempo_push_port] {
                let _ = Command::new(engine())
                    .args(["cluster", "edit", "internal", "--port-add", &format!("{port}:{port}@loadbalancer")])
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .status();
            }
        } else if is_phase {
            if let Some(p) = &kafka_nodeport {
                let _ = Command::new(engine())
                    .args(["cluster", "edit", &cluster_name, "--port-add", &format!("{p}:{p}@loadbalancer")])
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .status();
            }
            if let Some(p) = &apicurio_nodeport {
                let _ = Command::new(engine())
                    .args(["cluster", "edit", &cluster_name, "--port-add", &format!("{p}:{p}@loadbalancer")])
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .status();
            }
        }
        return Ok(0);
    }

    // Clear a leftover 0-server entry so `k3d cluster create` won't refuse the name.
    let stale = capture(&engine(), &["cluster", "list", &cluster_name]);
    if !stale.is_empty() {
        println!("Removing stale '{cluster_name}' entry (0 servers)...");
        let _ = Command::new(engine())
            .args(["cluster", "delete", &cluster_name])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    }

    let _ = Command::new("docker")
        .args(["volume", "create", &storage_volume])
        .stdout(Stdio::null())
        .status();

    // The shared k3d-registry survives `k3d cluster delete` but stays tagged
    // to the deleted cluster, and `k3d cluster create` refuses the name
    // while any node (registry included) still claims it.
    let reg_list = capture(&engine(), &["registry", "list", "--no-headers"]);
    let mut reg_cluster = reg_list
        .lines()
        .find(|l| l.trim_start().starts_with("k3d-registry") && l.trim_start()[12..].starts_with(char::is_whitespace))
        .and_then(|l| l.split_whitespace().nth(2))
        .unwrap_or("")
        .to_string();

    if !reg_cluster.is_empty() && reg_cluster == cluster_name {
        println!("Removing stale registry (tagged to '{cluster_name}')...");
        let _ = Command::new(engine())
            .args(["registry", "delete", "k3d-registry"])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
        reg_cluster.clear();
    }

    let mut registry_arg: Vec<String> = if !reg_cluster.is_empty() {
        vec!["--registry-use".into(), "k3d-registry:5111".into()]
    } else {
        vec!["--registry-create".into(), "k3d-registry:0.0.0.0:5111".into()]
    };

    let mut extra_args: Vec<String> = Vec::new();
    let mut mirror_config_path: Option<std::path::PathBuf> = None;

    if cluster_name == "internal" {
        for port in [&registry_mirror_port, &mimir_push_port, &loki_push_port, &tempo_push_port] {
            extra_args.push("-p".into());
            extra_args.push(format!("{port}:{port}@loadbalancer"));
        }
    } else if is_phase {
        let content = format!(
            "mirrors:\n  \"harbor.harbor.svc.cluster.local:80\":\n    endpoint:\n      - \"http://host.docker.internal:{registry_mirror_port}\"\n"
        );
        let path = std::env::temp_dir().join(format!("homelab-mirror-{cluster_name}.yaml"));
        fs::write(&path, content)?;
        extra_args.push("--registry-config".into());
        extra_args.push(path.to_string_lossy().to_string());
        mirror_config_path = Some(path);

        extra_args.push("--k3s-arg".into());
        extra_args.push("--disable=traefik@server:*".into());

        if let Some(p) = &kafka_nodeport {
            extra_args.push("-p".into());
            extra_args.push(format!("{p}:{p}@loadbalancer"));
        }
        if let Some(p) = &apicurio_nodeport {
            extra_args.push("-p".into());
            extra_args.push(format!("{p}:{p}@loadbalancer"));
        }
    }

    // docker.sock mount is internal-only.
    let mut docker_sock_arg: Vec<String> = Vec::new();
    if cluster_name == "internal" {
        docker_sock_arg.push("--volume".into());
        docker_sock_arg.push("/var/run/docker.sock:/var/run/docker.sock@server:0".into());
    }

    let mut args: Vec<String> = vec![
        "cluster".into(),
        "create".into(),
        cluster_name.clone(),
        "--volume".into(),
        format!("{storage_volume}://var/lib/rancher/k3s/storage@server:0"),
    ];
    args.extend(docker_sock_arg);
    args.append(&mut registry_arg);
    args.extend(extra_args);

    let status = run(&engine(), &args.iter().map(String::as_str).collect::<Vec<_>>())?;
    if !status.success() {
        anyhow::bail!("k3d cluster create failed ({:?})", status.code());
    }
    if let Some(p) = mirror_config_path {
        let _ = fs::remove_file(p);
    }

    let _ = Command::new("docker")
        .args(["update", "--restart", "unless-stopped", "k3d-registry"])
        .stdout(Stdio::null())
        .status();

    println!();
    println!("Cluster '{cluster_name}' created. PVC data persists in docker volume: {storage_volume}");
    if is_phase {
        println!("Registry mirror wired: harbor.harbor.svc.cluster.local:80 -> host.docker.internal:{registry_mirror_port}");
        println!("(needs harbor exposed as a NodePort {registry_mirror_port} Service on k3d-internal - separate step)");
        println!("NOTE: this mirror config is baked in at cluster CREATION time - an");
        println!("already-running phase cluster still points at whatever this script said");
        println!("when it was created; recreate it to pick up this change (see AGENT.md).");
    } else {
        println!("Next: load .env (copy from .env.example if you haven't), homelab terraform genvars, then (cd terraform/internal; tofu apply).");
    }

    Ok(0)
}

/// `k3d cluster list <name> --no-headers` exits 0 even when only the shared
/// k3d-registry node is left -- check the actual server count from the
/// SERVERS(x/y) column.
fn cluster_servers(name: &str) -> u32 {
    parse_servers(&capture(&engine(), &["cluster", "list", name, "--no-headers"]))
}

fn parse_servers(line: &str) -> u32 {
    if line.is_empty() {
        return 0;
    }
    let Some(servers_col) = line.split_whitespace().nth(1) else {
        return 0;
    };
    if let Some(slash) = servers_col.find('/') {
        servers_col[slash + 1..]
            .trim_end_matches(|c: char| !c.is_ascii_digit())
            .parse()
            .unwrap_or(0)
    } else {
        0
    }
}

#[cfg(test)]
#[path = "../../tests/create_cluster.rs"]
mod tests;
