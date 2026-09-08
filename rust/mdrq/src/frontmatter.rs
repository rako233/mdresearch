//! Reads the YAML frontmatter block of a Markdown file.
//!
//! Real YAML via serde_yaml, plus one pre-processing step: `tags: #a #b` is
//! the inline tag form that fmd supports and that YAML would read as a
//! comment, so it is rewritten to a flow sequence before parsing.

use serde_json::{Map, Value as Json};

const MAX_BYTES: usize = 64 * 1024;

/// The text between the opening and closing `---`, or `None`.
pub fn extract(content: &str) -> Option<&str> {
    let content = content.strip_prefix('\u{feff}').unwrap_or(content);
    let mut rest = content;
    let first_end = rest.find('\n')?;
    if rest[..first_end].trim_end() != "---" {
        return None;
    }
    let body_start = first_end + 1;
    rest = &content[body_start..];

    let mut offset = 0usize;
    loop {
        let line_end = rest[offset..].find('\n');
        let line = match line_end {
            Some(n) => &rest[offset..offset + n],
            None => return None, // unterminated frontmatter
        };
        let trimmed = line.trim_end();
        if trimmed == "---" || trimmed == "..." {
            return Some(&rest[..offset]);
        }
        offset += line_end.unwrap() + 1;
    }
}

/// `key: #a #b`  ->  `key: [a, b]`
fn rewrite_inline_tags(yaml: &str) -> String {
    let mut out = String::with_capacity(yaml.len());
    for line in yaml.lines() {
        let rewritten = (|| {
            let colon = line.find(':')?;
            let (key, rest) = line.split_at(colon);
            if key.trim().is_empty() || !key.trim_start().chars().all(is_key_char) {
                return None;
            }
            let value = rest[1..].trim();
            if !value.starts_with('#') {
                return None;
            }
            let tags: Vec<&str> = value.split_whitespace().collect();
            if !tags.iter().all(|t| t.starts_with('#') && t.len() > 1) {
                return None;
            }
            let inner: Vec<String> = tags
                .iter()
                .map(|t| format!("\"{}\"", t[1..].replace('"', "\\\"")))
                .collect();
            Some(format!("{}: [{}]", key, inner.join(", ")))
        })();
        out.push_str(&rewritten.unwrap_or_else(|| line.to_string()));
        out.push('\n');
    }
    out
}

fn is_key_char(c: char) -> bool {
    c.is_alphanumeric() || matches!(c, '_' | '-' | '.' | '$')
}

fn yaml_to_json(v: serde_yaml::Value) -> Json {
    match v {
        serde_yaml::Value::Null => Json::Null,
        serde_yaml::Value::Bool(b) => Json::Bool(b),
        serde_yaml::Value::Number(n) => n
            .as_i64()
            .map(Json::from)
            .or_else(|| n.as_f64().map(Json::from))
            .unwrap_or(Json::Null),
        serde_yaml::Value::String(s) => Json::String(s),
        serde_yaml::Value::Sequence(items) => Json::Array(items.into_iter().map(yaml_to_json).collect()),
        serde_yaml::Value::Mapping(map) => {
            let mut out = Map::new();
            for (k, v) in map {
                let key = match k {
                    serde_yaml::Value::String(s) => s,
                    other => serde_yaml::to_string(&other)
                        .unwrap_or_default()
                        .trim()
                        .to_string(),
                };
                out.insert(key, yaml_to_json(v));
            }
            Json::Object(out)
        }
        serde_yaml::Value::Tagged(t) => yaml_to_json(t.value),
    }
}

/// Parse a frontmatter block into a JSON object. Junk yields an empty map.
pub fn parse(yaml: &str) -> Map<String, Json> {
    let prepared = rewrite_inline_tags(yaml);
    match serde_yaml::from_str::<serde_yaml::Value>(&prepared) {
        Ok(v) => match yaml_to_json(v) {
            Json::Object(map) => map,
            _ => Map::new(),
        },
        Err(_) => Map::new(),
    }
}

/// Read a file's frontmatter. `None` means "no usable frontmatter", which the
/// scanner treats as "not a match" rather than as an error.
pub fn read(path: &std::path::Path) -> Option<Map<String, Json>> {
    use std::io::Read;
    let mut file = std::fs::File::open(path).ok()?;
    let mut buf = vec![0u8; MAX_BYTES];
    let n = file.read(&mut buf).ok()?;
    buf.truncate(n);
    let content = String::from_utf8_lossy(&buf);
    let block = extract(&content)?;
    Some(parse(block))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn extracts_the_block() {
        assert_eq!(extract("---\na: 1\n---\nbody\n"), Some("a: 1\n"));
        assert_eq!(extract("no frontmatter\n"), None);
        assert_eq!(extract("---\na: 1\n"), None); // never closed
        assert_eq!(extract("---\na: 1\n...\nbody"), Some("a: 1\n"));
    }

    #[test]
    fn reads_multiline_tags() {
        let m = parse("tags:\n  - linux\n  - \"server stuff\"\n");
        assert_eq!(m["tags"], json!(["linux", "server stuff"]));
    }

    #[test]
    fn reads_inline_hash_tags() {
        let m = parse("tags: #rust #cli\ntitle: x\n");
        assert_eq!(m["tags"], json!(["rust", "cli"]));
        assert_eq!(m["title"], json!("x"));
    }

    #[test]
    fn leaves_a_real_comment_alone() {
        let m = parse("title: x # a note\n");
        assert_eq!(m["title"], json!("x"));
    }

    #[test]
    fn junk_is_an_empty_map() {
        assert!(parse("\t:::\n\tnot: [yaml").is_empty());
    }
}
