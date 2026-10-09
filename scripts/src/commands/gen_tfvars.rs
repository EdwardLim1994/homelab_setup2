// Port of scripts/windows/gen-tfvars.ps1 / scripts/linux/gen-tfvars.sh.
use crate::dotenv::raw_tf_var_lines;
use crate::util::{repo_root, tf_engine};
use std::fs;

// ponytail: bare `homelab terraform ...` just execs the configured IaC binary.
pub fn native(args: Vec<String>) -> anyhow::Result<i32> {
    Ok(std::process::Command::new(tf_engine()).args(args).status()?.code().unwrap_or(1))
}

pub fn run() -> anyhow::Result<i32> {
    let repo_root = repo_root();
    let env_file = repo_root.join(".env");
    let env_lines = raw_tf_var_lines(&env_file)?;

    for env in ["internal", "sit", "uat", "production"] {
        let env_dir = repo_root.join("terraform").join(env);
        if !env_dir.is_dir() {
            continue;
        }
        let declared = declared_variables(&env_dir)?;
        let lines: Vec<String> = env_lines
            .iter()
            .filter(|(name, _)| declared.contains(name))
            .map(|(name, value)| format!("{name} = \"{value}\""))
            .collect();

        let out = env_dir.join("local.auto.tfvars");
        let mut content = lines.join("\n");
        if !content.is_empty() {
            content.push('\n');
        }
        fs::write(&out, content)?;
        println!("Generated {} ({} vars)", out.display(), lines.len());
    }
    Ok(0)
}

/// Collect every `variable "<name>"` declaration across the *.tf files in a
/// terraform root module directory (non-recursive, matching the PS version's
/// `Get-ChildItem $envDir -Filter '*.tf'`).
fn declared_variables(dir: &std::path::Path) -> anyhow::Result<std::collections::HashSet<String>> {
    let mut names = std::collections::HashSet::new();
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("tf") {
            continue;
        }
        let content = fs::read_to_string(&path)?;
        let mut rest = content.as_str();
        while let Some(idx) = rest.find("variable") {
            rest = &rest[idx + "variable".len()..];
            // skip whitespace up to the opening quote
            let trimmed = rest.trim_start();
            if let Some(stripped) = trimmed.strip_prefix('"') {
                if let Some(end) = stripped.find('"') {
                    names.insert(stripped[..end].to_string());
                }
            }
        }
    }
    Ok(names)
}

#[cfg(test)]
#[path = "../../tests/gen_tfvars.rs"]
mod tests;
