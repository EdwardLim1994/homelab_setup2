use std::fs;
use std::path::Path;

/// Minimal .env loader, ported from scripts/windows/_env.ps1's Import-DotEnv:
/// KEY=VALUE lines, `#` comments, optional surrounding quotes, trailing
/// ` # comment` stripped off an unquoted value. Sets process env vars.
/// Returns false if the file doesn't exist (same contract as the PS version).
pub fn import_dotenv(path: &Path) -> bool {
    let Ok(contents) = fs::read_to_string(path) else {
        return false;
    };
    for line in contents.lines() {
        if let Some((key, val)) = parse_kv_line(line) {
            std::env::set_var(key, val);
        }
    }
    true
}

fn parse_kv_line(line: &str) -> Option<(String, String)> {
    // ^\s*([^#=]+?)\s*=\s*(.*)$
    let trimmed_start = line.trim_start();
    if trimmed_start.starts_with('#') {
        return None;
    }
    let eq = line.find('=')?;
    let key_part = &line[..eq];
    // key must contain no '#' (matches [^#=]+ in the original regex)
    if key_part.contains('#') {
        return None;
    }
    let key = key_part.trim();
    if key.is_empty() {
        return None;
    }
    let mut val = line[eq + 1..].to_string();

    // strip trailing ` # comment` (hash preceded by whitespace) on an
    // unquoted-looking value, same as the PS `-replace '\s+#.*$', ''`
    if let Some(hash_idx) = find_comment_hash(&val) {
        val.truncate(hash_idx);
    }
    let val = val.trim();

    let val = if val.len() >= 2 {
        let bytes = val.as_bytes();
        let first = bytes[0];
        let last = bytes[bytes.len() - 1];
        if first == last && (first == b'"' || first == b'\'') {
            &val[1..val.len() - 1]
        } else {
            val
        }
    } else {
        val
    };

    Some((key.to_string(), val.to_string()))
}

/// Find the index of a `#` preceded by whitespace (the start of a trailing
/// comment), mirroring PowerShell's `-replace '\s+#.*$', ''`.
fn find_comment_hash(s: &str) -> Option<usize> {
    let chars: Vec<char> = s.chars().collect();
    for i in 1..chars.len() {
        if chars[i] == '#' && chars[i - 1].is_whitespace() {
            // byte index of this char
            let byte_idx: usize = chars[..i].iter().map(|c| c.len_utf8()).sum();
            // also consume the whitespace run before it
            let mut j = i - 1;
            while j > 0 && chars[j].is_whitespace() {
                j -= 1;
            }
            let start = if chars[j].is_whitespace() { j } else { j + 1 };
            let start_byte: usize = chars[..start].iter().map(|c| c.len_utf8()).sum();
            return Some(start_byte.min(byte_idx));
        }
    }
    None
}

/// Raw `TF_VAR_<name>=<value>` line extraction for gen-tfvars: no comment
/// stripping, no quote unwrapping -- the right-hand side is taken completely
/// literally and re-quoted as a tfvars string, matching gen-tfvars.ps1 (which
/// does NOT dot-source _env.ps1, it has its own regex).
pub fn raw_tf_var_lines(path: &Path) -> anyhow::Result<Vec<(String, String)>> {
    let contents = fs::read_to_string(path)?;
    let mut out = Vec::new();
    for line in contents.lines() {
        if let Some(rest) = line.strip_prefix("TF_VAR_") {
            if let Some(eq) = rest.find('=') {
                let name = rest[..eq].to_string();
                let value = rest[eq + 1..].to_string();
                out.push((name, value));
            }
        }
    }
    Ok(out)
}

#[cfg(test)]
#[path = "../tests/dotenv.rs"]
mod tests;
