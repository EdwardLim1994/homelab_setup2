// Port of scripts/windows/reset-nextcloud.ps1 / scripts/linux/reset-nextcloud.sh.
//
// DESTRUCTIVE: wipes all Nextcloud content. Only run when Nextcloud is
// already broken (crash-looping / 502 with "already exists" in the logs).
use std::process::Command;

pub fn run() -> anyhow::Result<i32> {
    let ns = std::env::var("NS").unwrap_or_else(|_| "nextcloud".to_string());

    println!("Dropping + recreating the nextcloud database in {ns}/nextcloud-mariadb-0 ...");
    let _ = Command::new("kubectl")
        .args([
            "exec",
            "-n",
            &ns,
            "nextcloud-mariadb-0",
            "--",
            "sh",
            "-c",
            r#"mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS nextcloud; CREATE DATABASE nextcloud;""#,
        ])
        .status();

    println!("Restarting Nextcloud ...");
    let _ = Command::new("kubectl")
        .args(["rollout", "restart", "-n", &ns, "deploy/nextcloud"])
        .status();
    let status = Command::new("kubectl")
        .args(["rollout", "status", "-n", &ns, "deploy/nextcloud", "--timeout=300s"])
        .status()?;

    println!("done - Nextcloud re-installed its schema.");
    Ok(if status.success() { 0 } else { 1 })
}

#[cfg(test)]
#[path = "../../tests/reset_nextcloud.rs"]
mod tests;
