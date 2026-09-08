//! Wire types shared with the Lua side. See ../README.md for the schema.

use serde::{Deserialize, Serialize};

pub const PROTOCOL: u32 = 1;

#[derive(Debug, Deserialize)]
pub struct Request {
    #[serde(default)]
    pub protocol: u32,
    pub root: String,
    #[serde(default = "default_glob")]
    pub glob: String,
    #[serde(default)]
    pub exclude: Vec<String>,
    #[serde(default)]
    pub hidden: bool,
    #[serde(default)]
    pub follow: bool,
    #[serde(default = "default_limit")]
    pub limit: usize,
    #[serde(default)]
    pub sort: Option<Sort>,
    #[serde(default)]
    pub fields: Vec<FieldSpec>,
    #[serde(default)]
    pub filters: Vec<FieldFilter>,
    #[serde(default)]
    pub fulltext: Option<FieldFilter>,
}

fn default_glob() -> String {
    "**/*.md".to_string()
}

fn default_limit() -> usize {
    2000
}

#[derive(Debug, Deserialize)]
pub struct Sort {
    pub key: String,
    #[serde(default)]
    pub desc: bool,
}

#[derive(Debug, Clone, Deserialize)]
pub struct FieldSpec {
    pub key: String,
    #[serde(rename = "type", default = "default_type")]
    pub ftype: String,
    /// Accepted for protocol symmetry with the Lua side. Matching treats a
    /// scalar as a one-element list, so nothing needs to read it.
    #[serde(default)]
    #[allow(dead_code)]
    pub list: bool,
}

fn default_type() -> String {
    "text".to_string()
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Mode {
    Any,
    All,
}

#[derive(Debug, Deserialize)]
pub struct FieldFilter {
    pub key: String,
    #[serde(rename = "type", default = "default_type")]
    pub ftype: String,
    /// See `FieldSpec::list`.
    #[serde(default)]
    #[allow(dead_code)]
    pub list: bool,
    pub mode: Mode,
    pub terms: Vec<Term>,
}

#[derive(Debug, Deserialize)]
pub struct Term {
    pub op: String,
    #[serde(default)]
    pub value: Option<serde_json::Value>,
    #[serde(default)]
    pub from: Option<i64>,
    #[serde(default)]
    pub to: Option<i64>,
    #[serde(default)]
    pub negate: bool,
}

impl Term {
    pub fn text(&self) -> String {
        match &self.value {
            Some(serde_json::Value::String(s)) => s.clone(),
            Some(other) => other.to_string(),
            None => String::new(),
        }
    }

    pub fn number(&self) -> Option<i64> {
        match &self.value {
            Some(serde_json::Value::Number(n)) => n.as_i64(),
            Some(serde_json::Value::String(s)) => s.parse().ok(),
            _ => None,
        }
    }
}

#[derive(Debug, Serialize)]
pub struct Row {
    pub path: String,
    pub rel: String,
    pub fields: serde_json::Map<String, serde_json::Value>,
}

#[derive(Debug, Serialize)]
pub struct Meta {
    pub __meta: bool,
    pub truncated: bool,
    pub scanned: usize,
}
