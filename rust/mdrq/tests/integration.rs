//! End-to-end tests over a temporary vault: request in, JSON Lines out.

use serde_json::{json, Value};
use std::io::Write;
use std::process::{Command, Stdio};

fn vault() -> tempfile::TempDir {
    let dir = tempfile::tempdir().unwrap();
    let write = |rel: &str, body: &str| {
        let path = dir.path().join(rel);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, body).unwrap();
    };

    write(
        "linux-server.md",
        "---\ntitle: Linux server setup\ntags:\n  - linux\n  - server\n  - tutorial\nstatus: published\nprio: 3\ndate: 2025-01-15\nupdated: 2025-02-01 09:30\n---\n\nInstall docker.\n",
    );
    write(
        "macos-notes.md",
        "---\ntitle: macOS notes\ntags: [macos, tutorial]\nstatus: draft\nprio: 1\ndate: 2025-03-02\n---\n\nHomebrew.\n",
    );
    write(
        "projects/rust-cli.md",
        "---\ntitle: Rust CLI patterns\ntags: #rust #cli #tutorial\nstatus: published\nprio: 4\ndate: 2024-11-20\n---\n\nClap and docker.\n",
    );
    write(
        "journal/entry.md",
        "---\ntitle: Journal\ntags:\n  - journal\n  - \"personal notes\"\nprio: 1\ndate: 2025-01-02\n---\n\nQuiet day.\n",
    );
    write("archive/old.md", "---\ntitle: Old\ntags: [linux, archive]\nprio: 0\ndate: 2019-05-05\n---\n\nOld.\n");
    write("no-frontmatter.md", "# Nothing here\n");
    write("broken.md", "---\ntitle: unterminated\n");
    dir
}

fn fields() -> Value {
    json!([
        {"key":"title","type":"text","list":false},
        {"key":"tags","type":"text","list":true},
        {"key":"status","type":"text","list":false},
        {"key":"prio","type":"int","list":false},
        {"key":"date","type":"date","list":false},
        {"key":"updated","type":"datetime","list":false}
    ])
}

/// Run mdrq and return the `rel` paths, in the order it emitted them.
fn query(root: &std::path::Path, extra: Value) -> (Vec<String>, Value) {
    let mut req = json!({
        "protocol": 1,
        "root": root.to_string_lossy(),
        "glob": "**/*.md",
        "limit": 100,
        "sort": {"key":"date","desc":false},
        "fields": fields(),
    });
    for (k, v) in extra.as_object().unwrap() {
        req[k] = v.clone();
    }

    let mut child = Command::new(env!("CARGO_BIN_EXE_mdrq"))
        .arg("--stdin")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .as_mut()
        .unwrap()
        .write_all(req.to_string().as_bytes())
        .unwrap();
    let out = child.wait_with_output().unwrap();
    assert!(
        out.status.success(),
        "mdrq failed: {}",
        String::from_utf8_lossy(&out.stderr)
    );

    let mut rels = Vec::new();
    let mut meta = Value::Null;
    for line in String::from_utf8_lossy(&out.stdout).lines() {
        let v: Value = serde_json::from_str(line).unwrap();
        if v.get("__meta").is_some() {
            meta = v;
        } else {
            rels.push(v["rel"].as_str().unwrap().replace('\\', "/"));
        }
    }
    (rels, meta)
}

fn filter(key: &str, ftype: &str, mode: &str, terms: Value) -> Value {
    json!({"filters":[{"key":key,"type":ftype,"list":true,"mode":mode,"terms":terms}]})
}

#[test]
fn prints_its_protocol_version() {
    let out = Command::new(env!("CARGO_BIN_EXE_mdrq"))
        .arg("--protocol")
        .output()
        .unwrap();
    assert_eq!(String::from_utf8_lossy(&out.stdout).trim(), "1");
}

#[test]
fn lists_every_parseable_note_sorted_by_date() {
    let dir = vault();
    let (rels, meta) = query(dir.path(), json!({}));
    assert_eq!(
        rels,
        vec![
            "archive/old.md",
            "projects/rust-cli.md",
            "journal/entry.md",
            "linux-server.md",
            "macos-notes.md",
        ]
    );
    assert_eq!(meta["truncated"], json!(false));
}

#[test]
fn ors_and_ands_tag_values() {
    let dir = vault();
    let (any, _) = query(
        dir.path(),
        filter("tags", "text", "any", json!([{"op":"contains","value":"macos"},{"op":"contains","value":"rust"}])),
    );
    assert_eq!(any, vec!["projects/rust-cli.md", "macos-notes.md"]);

    let (all, _) = query(
        dir.path(),
        filter("tags", "text", "all", json!([{"op":"contains","value":"linux"},{"op":"contains","value":"server"}])),
    );
    assert_eq!(all, vec!["linux-server.md"]);
}

#[test]
fn matches_a_quoted_tag_with_a_space() {
    let dir = vault();
    let (rels, _) = query(
        dir.path(),
        filter("tags", "text", "any", json!([{"op":"contains","value":"personal notes"}])),
    );
    assert_eq!(rels, vec!["journal/entry.md"]);
}

#[test]
fn date_ranges_include_both_bounds() {
    let dir = vault();
    let (rels, _) = query(
        dir.path(),
        filter("date", "date", "any", json!([{"op":"between","from":20250102,"to":20250115}])),
    );
    assert_eq!(rels, vec!["journal/entry.md", "linux-server.md"]);
}

#[test]
fn datetime_fields_compare_on_the_date_alone() {
    let dir = vault();
    let (rels, _) = query(
        dir.path(),
        filter("updated", "datetime", "any", json!([{"op":"between","from":20250201,"to":20250201}])),
    );
    assert_eq!(rels, vec!["linux-server.md"]);
}

#[test]
fn int_fields_take_ranges() {
    let dir = vault();
    let (rels, _) = query(
        dir.path(),
        filter("prio", "int", "any", json!([{"op":"between","from":3}])),
    );
    assert_eq!(rels, vec!["projects/rust-cli.md", "linux-server.md"]);
}

#[test]
fn searches_the_body() {
    let dir = vault();
    let (rels, _) = query(
        dir.path(),
        json!({"fulltext":{"key":"__fulltext","type":"text","mode":"all",
            "terms":[{"op":"contains","value":"docker"}]}}),
    );
    assert_eq!(rels, vec!["projects/rust-cli.md", "linux-server.md"]);
}

#[test]
fn honours_exclude_globs() {
    let dir = vault();
    let mut req = filter("tags", "text", "any", json!([{"op":"contains","value":"linux"}]));
    req["exclude"] = json!(["archive/**"]);
    let (rels, _) = query(dir.path(), req);
    assert_eq!(rels, vec!["linux-server.md"]);
}

#[test]
fn caps_the_result_count() {
    let dir = vault();
    let (rels, meta) = query(dir.path(), json!({"limit": 2}));
    assert_eq!(rels.len(), 2);
    assert_eq!(meta["truncated"], json!(true));
}

#[test]
fn returns_the_field_values_for_the_table() {
    let dir = vault();
    let mut child = Command::new(env!("CARGO_BIN_EXE_mdrq"))
        .arg("--stdin")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let req = json!({
        "protocol":1, "root": dir.path().to_string_lossy(), "fields": fields(),
        "filters":[{"key":"title","type":"text","mode":"all",
            "terms":[{"op":"contains","value":"linux server"}]}]
    });
    child
        .stdin
        .as_mut()
        .unwrap()
        .write_all(req.to_string().as_bytes())
        .unwrap();
    let out = child.wait_with_output().unwrap();
    let first: Value = serde_json::from_str(String::from_utf8_lossy(&out.stdout).lines().next().unwrap()).unwrap();
    assert_eq!(first["fields"]["tags"], json!(["linux", "server", "tutorial"]));
    assert_eq!(first["fields"]["prio"], json!(3));
}

#[test]
fn rejects_a_foreign_protocol() {
    let mut child = Command::new(env!("CARGO_BIN_EXE_mdrq"))
        .arg("--stdin")
        .stdin(Stdio::piped())
        .stderr(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .as_mut()
        .unwrap()
        .write_all(br#"{"protocol":99,"root":"/tmp"}"#)
        .unwrap();
    let out = child.wait_with_output().unwrap();
    assert!(!out.status.success());
    assert!(String::from_utf8_lossy(&out.stderr).contains("protocol"));
}
