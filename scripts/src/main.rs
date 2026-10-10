mod commands;
mod dotenv;
mod pipe;
mod util;

use clap::{Parser, Subcommand};

/// homelab_setup2 operator CLI.
///
/// Replaces the one-script-per-task layout under scripts/windows/*.ps1 and
/// scripts/linux/*.sh with a single binary: `homelab <command> [args...]`.
#[derive(Parser)]
#[command(name = "homelab", version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum AnsibleAction {
    /// Run a playbook as a k8s Job: a baked-in one by name, or a local .yml file
    #[command(after_help = commands::ansible_run::help())]
    Run {
        /// Playbook name, or path to a local .yml file (omit for the default parallel fan-out)
        playbook: Option<String>,
        /// Extra ansible args, e.g. --syntax-check, --tags <tag>, -e key=value
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        args: Vec<String>,
    },
    /// Run the native ansible CLI with the remaining args, e.g. `native --version`
    #[command(disable_help_flag = true)]
    Native {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        args: Vec<String>,
    },
    /// (any other word) is passed to the native CLI too
    #[command(external_subcommand)]
    Passthrough(Vec<String>),
}

#[derive(Subcommand)]
enum ClusterAction {
    /// Create (or verify) a cluster: internal (default), phases, sit, uat, production
    Create {
        /// Cluster name
        name: Option<String>,
    },
    /// Run the native cluster engine (k3d) CLI with the remaining args, e.g. `native --version`
    #[command(disable_help_flag = true)]
    Native {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        args: Vec<String>,
    },
    /// (any other word) is passed to the native CLI too
    #[command(external_subcommand)]
    Passthrough(Vec<String>),
}

#[derive(Subcommand)]
enum TerraformAction {
    /// Regenerate terraform/<env>/local.auto.tfvars from the root .env
    Genvars,
    /// Run the native terraform/tofu CLI with the remaining args, e.g. `native --version`
    #[command(disable_help_flag = true)]
    Native {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        args: Vec<String>,
    },
    /// (any other word) is passed to the native CLI too
    #[command(external_subcommand)]
    Passthrough(Vec<String>),
}

#[derive(Subcommand)]
enum Command {
    /// Ansible. `ansible run [playbook]` clones a one-shot Job from the
    /// suspended ansible-runner CronJob and streams its logs. No playbook:
    /// default parallel fan-out (n8n, omp, litellm, mcp-servers, openwebui).
    /// "site" runs the same set serially server-side; any other name
    /// (role-accounts, gitlab-webhook, ...) runs just that one. Anything else
    /// (`homelab ansible all -m ping`) is passed
    /// straight to the local ansible CLI; `ansible native <args>` does the same
    /// verbatim, flags first included (`homelab ansible native --version`).
    Ansible {
        #[command(subcommand)]
        action: AnsibleAction,
    },

    /// Cluster engine (default k3d, from Cargo.toml; override with CLUSTER_ENGINE in .env).
    /// `cluster create [name]` creates or verifies a cluster: name defaults
    /// to "internal"; "phases" creates sit/uat/production in one go. Anything
    /// else (`homelab cluster list`, `homelab cluster delete sit`) is passed
    /// straight to the engine CLI; `cluster native <args>` does so verbatim
    /// (`homelab cluster native version`).
    K8S {
        #[command(subcommand)]
        action: ClusterAction,
    },

    /// Terraform/OpenTofu (default binary tofu, from Cargo.toml; override with TERRAFORM_ENGINE in .env).
    /// `terraform genvars` regenerates terraform/<env>/local.auto.tfvars from
    /// .env. Anything else (`homelab terraform apply`) is passed straight to
    /// the engine in the current directory; `terraform native <args>` does so
    /// verbatim, flags first included (`homelab terraform native -chdir=x plan`).
    #[command(after_help = "Available options:
  genvars              regenerate terraform/<env>/local.auto.tfvars from the root
                       .env's TF_VAR_* lines (only vars each dir declares)
  native <args...>     run the engine with <args> verbatim (flags allowed first)
  <anything else>      shorthand for native, when it doesn't start with a flag

Examples:
  homelab terraform genvars
  cd terraform/internal && homelab terraform plan
  homelab terraform native apply -auto-approve
  homelab terraform native -chdir=terraform/internal plan
  homelab terraform                (no args: the engine's own help)

Engine: TERRAFORM_ENGINE in .env/env, else Cargo.toml [package.metadata.homelab]
        terraform_engine (default tofu; terraform also works)")]
    Terraform {
        #[command(subcommand)]
        action: Option<TerraformAction>,
    },

    /// Print every app's Tailscale + LAN URL with a live reachability check.
    ListUrls,

    /// Wake the omp pod, drop into its TUI, scale it back to 0 on exit.
    OmpShell,

    /// Local port-forwards for the terraform-deployed apps (CLI/debug only --
    /// browser/SSO logins must use the Tailscale URL). Ctrl+C to stop.
    PortForward,

    /// DESTRUCTIVE: drop + recreate Nextcloud's database and restart it.
    /// Only run when Nextcloud is already broken (crash-looping / 502 with
    /// "already exists" in the logs).
    ResetNextcloud,

    /// Self-check for the .env parser.
    EnvTest,
}

fn main() {
    let cli = Cli::parse();

    let result = dispatch(cli.command);

    match result {
        Ok(code) => std::process::exit(code),
        Err(e) => {
            eprintln!("error: {e:#}");
            std::process::exit(1);
        }
    }
}

fn dispatch(command: Command) -> anyhow::Result<i32> {
    match command {
        Command::Ansible { action } => match action {
            AnsibleAction::Run { playbook, args } => commands::ansible_run::run(playbook, args),
            AnsibleAction::Native { args } | AnsibleAction::Passthrough(args) => {
                commands::ansible_run::native(args)
            }
        },
        Command::K8S { action } => match action {
            ClusterAction::Create { name } => commands::create_cluster::run_cmd(name),
            ClusterAction::Native { args } | ClusterAction::Passthrough(args) => {
                commands::create_cluster::native(args)
            }
        },
        Command::Terraform { action } => match action {
            Some(TerraformAction::Genvars) => commands::gen_tfvars::run(),
            Some(TerraformAction::Native { args } | TerraformAction::Passthrough(args)) => {
                commands::gen_tfvars::native(args)
            }
            None => commands::gen_tfvars::native(vec![]),
        },
        Command::ListUrls => commands::list_urls::run(),
        Command::OmpShell => commands::omp_shell::run(),
        Command::PortForward => commands::port_forward::run(),
        Command::ResetNextcloud => commands::reset_nextcloud::run(),
        Command::EnvTest => commands::env_test::run(),
    }
}

#[cfg(test)]
#[path = "../tests/main.rs"]
mod tests;
