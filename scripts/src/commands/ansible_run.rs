// Port of scripts/windows/ansible-run.ps1 (itself a port of
// scripts/linux/ansible-run.sh). Clones a one-shot Job from the suspended
// ansible-runner CronJob (helm/ansible), streams its logs, lets k8s reap the
// pod when done.
use crate::pipe::pipe_chain;
use crate::util::{capture, capture_status, current_exe, job_id, repo_root};
use std::path::Path;
use std::process::{Command, Stdio};
use std::thread;
use std::time::Duration;

const DEFAULT_FANOUT: &[&str] = &["n8n", "omp", "litellm", "mcp-servers", "openwebui"];

pub fn run(playbook: Option<String>, ansible_args: Vec<String>) -> anyhow::Result<i32> {
    match playbook.as_deref() {
        None | Some("all") => fan_out(ansible_args),
        Some(p) => single_playbook(p, ansible_args),
    }
}

// ponytail: bare `homelab ansible ...` just execs the local ansible CLI.
pub fn native(args: Vec<String>) -> anyhow::Result<i32> {
    Ok(Command::new("ansible").args(args).status()?.code().unwrap_or(1))
}

fn fan_out(ansible_args: Vec<String>) -> anyhow::Result<i32> {
    let exe = current_exe();
    let mut children = Vec::new();
    for p in DEFAULT_FANOUT {
        let mut cmd = Command::new(&exe);
        cmd.args(["ansible", "run"]).arg(p);
        cmd.args(&ansible_args);
        children.push((*p, cmd.spawn()?));
    }

    let mut failed = Vec::new();
    for (name, mut child) in children {
        let status = child.wait()?;
        if !status.success() {
            failed.push(name);
        }
    }

    if !failed.is_empty() {
        println!("FAILED: {} playbook run(s) ({})", failed.len(), failed.join(", "));
        return Ok(1);
    }
    println!("All playbooks complete.");
    Ok(0)
}

/// Text for `homelab ansible run --help`: the playbooks found in the repo
/// (listed live, so it can't drift) plus the accepted argument forms.
pub fn help() -> String {
    let mut names: Vec<String> = std::fs::read_dir(repo_root().join("helm/ansible/playbooks"))
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|e| {
            let p = e.path();
            matches!(p.extension().and_then(|x| x.to_str()), Some("yml" | "yaml"))
                .then(|| p.file_stem()?.to_str().map(String::from))
                .flatten()
        })
        .collect();
    names.sort();
    format_help(&names)
}

fn format_help(names: &[String]) -> String {
    let list = if names.is_empty() {
        "  (run from inside the repo to list helm/ansible/playbooks)".to_string()
    } else {
        names.iter().map(|n| format!("  {n}")).collect::<Vec<_>>().join("\n")
    };
    format!(
        "Available playbooks:\n{list}\n\n\
         Default (no playbook): {} in parallel.\n\
         \"site\" runs the same set serially server-side.\n\n\
         Playbook argument:\n  \
         <name>         a playbook baked into the runner (helm/ansible/playbooks/<name>.yml)\n  \
         <path>.yml     a LOCAL playbook file, shipped to the pod as a one-off ConfigMap\n\n\
         Examples:\n  \
         homelab ansible run\n  \
         homelab ansible run role-accounts\n  \
         homelab ansible run n8n --syntax-check\n  \
         homelab ansible run gitlab-webhook --tags verify -e key=value\n  \
         homelab ansible run ./my-playbook.yml\n\n\
         Env: NS (default ansible), CRONJOB (default ansible-runner)",
        DEFAULT_FANOUT.join(", ")
    )
}

/// A playbook argument that is an existing local .yml/.yaml file is a custom
/// playbook; anything else names one baked into the runner.
fn custom_playbook(arg: &str) -> Option<&Path> {
    let p = Path::new(arg);
    let yaml = matches!(p.extension().and_then(|x| x.to_str()), Some("yml" | "yaml"));
    (yaml && p.is_file()).then_some(p)
}

/// DNS-safe label for job / ConfigMap names.
fn label_of(stem: &str) -> String {
    let s: String = stem
        .to_lowercase()
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '-' })
        .collect();
    s.trim_matches('-').to_string()
}

fn single_playbook(playbook: &str, ansible_args: Vec<String>) -> anyhow::Result<i32> {
    let ns = std::env::var("NS").unwrap_or_else(|_| "ansible".to_string());
    let cronjob = std::env::var("CRONJOB").unwrap_or_else(|_| "ansible-runner".to_string());
    let pb_args = ansible_args.join(" ");

    // Custom local playbook: ship it in a ConfigMap, mount at /custom.
    let custom = custom_playbook(playbook);
    let (label, pb_env) = match custom {
        Some(p) => {
            let file = p.file_name().and_then(|f| f.to_str()).unwrap_or("custom.yml");
            (label_of(p.file_stem().and_then(|f| f.to_str()).unwrap_or("custom")), format!("../custom/{file}"))
        }
        None => (playbook.to_string(), format!("{playbook}.yml")),
    };
    let playbook = label.as_str();
    let job = job_id(&format!("ansible-{playbook}"));
    if let Some(p) = custom {
        let file = p.file_name().and_then(|f| f.to_str()).unwrap_or("custom.yml");
        let (_, ok) = capture_status(
            "kubectl",
            &["-n", &ns, "create", "configmap", &job, &format!("--from-file={file}={}", p.display())],
        );
        if !ok {
            anyhow::bail!("failed to create ConfigMap {job} from {}", p.display());
        }
    }
    // kubectl create job ... --dry-run=client -o yaml | kubectl set env --local -f - ... | [kubectl patch --local ...] | kubectl apply -f -
    let k = |args: Vec<String>| ("kubectl", args);
    let s = |v: &[&str]| v.iter().map(|x| x.to_string()).collect::<Vec<String>>();
    let mut stages = vec![
        k(vec![
            "-n".into(),
            ns.clone(),
            "create".into(),
            "job".into(),
            job.clone(),
            format!("--from=cronjob/{cronjob}"),
            "--dry-run=client".into(),
            "-o".into(),
            "yaml".into(),
        ]),
        k({
            let mut v = s(&["set", "env", "--local", "-f", "-", "-o", "yaml"]);
            v.push(format!("PLAYBOOK={pb_env}"));
            v.push(format!("ANSIBLE_ARGS={pb_args}"));
            v
        }),
    ];
    if custom.is_some() {
        let patch = format!(
            r#"[{{"op":"add","path":"/spec/template/spec/volumes/-","value":{{"name":"custom","configMap":{{"name":"{job}"}}}}}},{{"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{{"name":"custom","mountPath":"/custom"}}}}]"#
        );
        let mut v = s(&["patch", "--local", "-f", "-", "--type=json", "-o", "yaml", "-p"]);
        v.push(patch);
        stages.push(k(v));
    }
    stages.push(k(s(&["apply", "-f", "-"])));
    let status = pipe_chain(stages);
    if custom.is_some() && !status.as_ref().is_ok_and(|s| s.success()) {
        let _ = capture_status("kubectl", &["-n", &ns, "delete", "configmap", &job, "--ignore-not-found"]);
    }
    let status = status?;
    if !status.success() {
        anyhow::bail!("failed to create job {job}");
    }

    println!("[{playbook}] Job {job} created - waiting for pod...");

    let mut pod = String::new();
    for _ in 0..60 {
        let out = capture(
            "kubectl",
            &["-n", &ns, "get", "pod", "-l", &format!("job-name={job}"), "-o", "name"],
        );
        if let Some(first) = out.lines().next() {
            if !first.is_empty() {
                pod = first.to_string();
                break;
            }
        }
        thread::sleep(Duration::from_secs(2));
    }
    if pod.is_empty() {
        println!("[{playbook}] pod never appeared - inspect: kubectl -n {ns} describe job/{job}");
        return Ok(1);
    }
    let pod_name = pod.trim_start_matches("pod/").to_string();

    // Stream logs in a background, killable child -- kubectl logs -f can
    // block forever; the job-status poll below is the authority on "done".
    let mut log_child = Command::new("kubectl")
        .args(["-n", &ns, "logs", "-f", &pod_name])
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .ok();
    if let Some(child) = &mut log_child {
        if let Some(stdout) = child.stdout.take() {
            let prefix = playbook.to_string();
            thread::spawn(move || {
                use std::io::{BufRead, BufReader};
                for line in BufReader::new(stdout).lines().flatten() {
                    println!("[{prefix}] {line}");
                }
            });
        }
    }

    // Poll the job's terminal condition. A single failed `kubectl get job`
    // is frequently just a transient API-server blip -- require 3
    // CONSECUTIVE failures before concluding the job is genuinely gone.
    let mut rc = 1;
    let mut seen = String::new();
    let mut gone_streak = 0;
    let mut blips = 0;
    let mut timed_out = true;

    for i in 0..400 {
        let (_, ok) = crate::util::capture_status("kubectl", &["-n", &ns, "get", "job", &job]);
        if !ok {
            gone_streak += 1;
            blips += 1;
            if gone_streak < 3 {
                thread::sleep(Duration::from_secs(2));
                continue;
            }
            rc = if seen.contains("Complete") { 0 } else { 1 };
            timed_out = false;
            break;
        }
        gone_streak = 0;
        let types = capture(
            "kubectl",
            &["-n", &ns, "get", "job", &job, "-o", "jsonpath={.status.conditions[*].type}"],
        );
        if types.is_empty() {
            blips += 1;
        }
        seen = types.clone();
        if types.contains("Complete") {
            let _ = Command::new("kubectl")
                .args(["-n", &ns, "delete", "job", &job, "--ignore-not-found"])
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status();
            rc = 0;
            timed_out = false;
            break;
        }
        if types.contains("Failed") {
            rc = 1;
            timed_out = false;
            break;
        }
        if i % 40 == 0 && i > 0 {
            println!("[{playbook}] ...still running ({}s)", i * 3);
        }
        thread::sleep(Duration::from_secs(3));
    }

    if let Some(mut child) = log_child {
        let _ = child.kill();
    }
    if custom.is_some() {
        let _ = capture_status("kubectl", &["-n", &ns, "delete", "configmap", &job, "--ignore-not-found"]);
    }

    if timed_out {
        println!("[{playbook}] RESULT: FAILED - timed out after 20m - kubectl -n {ns} describe job/{job}");
        return Ok(1);
    }
    if rc == 0 {
        if blips > 0 {
            println!(
                "[{playbook}] RESULT: WARNING - job Complete, but {blips} transient kubectl API blip(s) occurred while polling (not a real failure; verify yourself if unsure: kubectl -n {ns} get job {job} -o yaml)"
            );
        } else {
            println!("[{playbook}] RESULT: SUCCESS - job Complete");
        }
    } else if gone_streak >= 3 {
        let last_seen = if seen.is_empty() { "none".to_string() } else { seen };
        println!(
            "[{playbook}] RESULT: FAILED - job genuinely vanished (confirmed gone across 3 consecutive checks, last seen condition: '{last_seen}') - kubectl -n {ns} get events"
        );
    } else {
        println!("[{playbook}] RESULT: FAILED - job condition Failed - kubectl -n {ns} describe job/{job}");
    }
    Ok(rc)
}

#[cfg(test)]
#[path = "../../tests/ansible_run.rs"]
mod tests;
