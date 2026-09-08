//! Walk the workspace, filter in parallel, sort, emit.

use crate::filter::{self, RegexCache};
use crate::frontmatter;
use crate::protocol::{FieldSpec, Meta, Request, Row};
use crate::value;
use anyhow::{Context, Result};
use globset::{Glob, GlobSetBuilder};
use ignore::overrides::OverrideBuilder;
use ignore::WalkBuilder;
use rayon::prelude::*;
use serde_json::{Map, Value as Json};
use std::path::{Path, PathBuf};

/// Enumerate the files of the workspace. Globs are matched against the path
/// relative to `root`, which is what the plugin config documents.
pub fn enumerate(req: &Request) -> Result<Vec<PathBuf>> {
    let root = Path::new(&req.root);

    let mut overrides = OverrideBuilder::new(root);
    overrides
        .add(&req.glob)
        .with_context(|| format!("bad glob {:?}", req.glob))?;
    for ex in &req.exclude {
        overrides
            .add(&format!("!{ex}"))
            .with_context(|| format!("bad exclude glob {ex:?}"))?;
    }
    let overrides = overrides.build()?;

    // A second matcher, because `ignore`'s overrides whitelist directories too
    // and we only want to *emit* files that match the glob.
    let mut want = GlobSetBuilder::new();
    want.add(Glob::new(&req.glob)?);
    let want = want.build()?;

    let mut out = Vec::new();
    let walker = WalkBuilder::new(root)
        .hidden(!req.hidden)
        .follow_links(req.follow)
        .overrides(overrides)
        .build();
    for entry in walker {
        let entry = match entry {
            Ok(e) => e,
            Err(_) => continue,
        };
        if !entry.file_type().map(|t| t.is_file()).unwrap_or(false) {
            continue;
        }
        let path = entry.into_path();
        let rel = path.strip_prefix(root).unwrap_or(&path);
        if want.is_match(rel) {
            out.push(path);
        }
    }
    out.sort();
    Ok(out)
}

fn sort_value(spec: Option<&FieldSpec>, fields: &Map<String, Json>, key: &str) -> (i64, String) {
    let raw = fields.get(key);
    let items = value::items(raw);
    let first = items.first().copied();
    match spec.map(|s| s.ftype.as_str()) {
        Some("date") | Some("datetime") => (first.and_then(value::as_ymd).unwrap_or(-1), String::new()),
        Some("int") => (first.and_then(value::as_int).unwrap_or(i64::MIN), String::new()),
        _ => (0, first.map(value::as_text).unwrap_or_default()),
    }
}

pub fn run(req: &Request) -> Result<(Vec<Row>, Meta)> {
    let root = Path::new(&req.root);
    let paths = enumerate(req)?;
    let scanned = paths.len();
    let regexes = RegexCache::default();

    let mut hits: Vec<(PathBuf, Map<String, Json>)> = paths
        .par_iter()
        .filter_map(|path| {
            let fields = frontmatter::read(path)?;
            for f in &req.filters {
                if !filter::field(f, fields.get(&f.key), &regexes) {
                    return None;
                }
            }
            if let Some(ft) = &req.fulltext {
                let content = std::fs::read(path).ok()?;
                let lowered = String::from_utf8_lossy(&content).to_lowercase();
                if !filter::fulltext(ft, &lowered) {
                    return None;
                }
            }
            Some((path.clone(), fields))
        })
        .collect();

    if let Some(sort) = &req.sort {
        let spec = req.fields.iter().find(|f| f.key == sort.key);
        hits.sort_by(|a, b| {
            let ka = sort_value(spec, &a.1, &sort.key);
            let kb = sort_value(spec, &b.1, &sort.key);
            // `desc` reverses the key only; ties always break on path
            // ascending, so both backends agree row for row.
            let ord = if sort.desc { kb.cmp(&ka) } else { ka.cmp(&kb) };
            ord.then_with(|| a.0.cmp(&b.0))
        });
    }

    let truncated = hits.len() > req.limit;
    hits.truncate(req.limit);

    let rows = hits
        .into_iter()
        .map(|(path, fields)| {
            let mut out = Map::new();
            for spec in &req.fields {
                if let Some(v) = fields.get(&spec.key) {
                    out.insert(spec.key.clone(), v.clone());
                }
            }
            let rel = path
                .strip_prefix(root)
                .unwrap_or(&path)
                .to_string_lossy()
                .into_owned();
            Row {
                path: path.to_string_lossy().into_owned(),
                rel,
                fields: out,
            }
        })
        .collect();

    Ok((
        rows,
        Meta {
            __meta: true,
            truncated,
            scanned,
        },
    ))
}
