// Port of scripts/windows/test-env.ps1 / scripts/linux/test-env.sh.
// Self-check for the dotenv loader.
use crate::dotenv::import_dotenv;
use std::fs;

pub fn run() -> anyhow::Result<i32> {
    let tmp = std::env::temp_dir().join(format!("homelab-env-test-{}.env", std::process::id()));
    fs::write(
        &tmp,
        "# comment line\nPLAIN=hello\nQUOTED=\"a b c\"\nSQUOTED='x y'\nWITH_EQ=key=val\n  SPACED = trimmed\n",
    )?;

    import_dotenv(&tmp);
    let _ = fs::remove_file(&tmp);

    expect("PLAIN", "hello")?;
    expect("QUOTED", "a b c")?;
    expect("SQUOTED", "x y")?;
    expect("WITH_EQ", "key=val")?;
    expect("SPACED", "trimmed")?;

    let missing = std::env::temp_dir().join("homelab-env-test-nope-does-not-exist.env");
    if import_dotenv(&missing) {
        anyhow::bail!("FAIL: missing file should return false");
    }

    println!("ok - import_dotenv");
    Ok(0)
}

fn expect(name: &str, want: &str) -> anyhow::Result<()> {
    let got = std::env::var(name).unwrap_or_default();
    if got != want {
        anyhow::bail!("FAIL {name} : want [{want}] got [{got}]");
    }
    Ok(())
}

#[cfg(test)]
#[path = "../../tests/env_test.rs"]
mod tests;
