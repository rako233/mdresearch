//! Typed views of a frontmatter value.
//!
//! The Lua backend is normative, so the rules here mirror
//! `lua/mdresearch/query/predicate.lua`: a scalar behaves as a one-element
//! list, dates compare on the date part only, and anything unparseable simply
//! does not match.

use serde_json::Value as Json;

/// Flatten a frontmatter value into the scalars a filter matches against.
pub fn items(v: Option<&Json>) -> Vec<&Json> {
    let mut out = Vec::new();
    fn walk<'a>(v: &'a Json, out: &mut Vec<&'a Json>) {
        match v {
            Json::Array(items) => {
                for item in items {
                    walk(item, out);
                }
            }
            Json::Null => {}
            other => out.push(other),
        }
    }
    if let Some(v) = v {
        walk(v, &mut out);
    }
    out
}

/// The scalar as text, lowercased, for case-insensitive matching.
pub fn as_text(v: &Json) -> String {
    match v {
        Json::String(s) => s.to_lowercase(),
        Json::Number(n) => n.to_string(),
        Json::Bool(b) => b.to_string(),
        other => other.to_string(),
    }
}

pub fn as_int(v: &Json) -> Option<i64> {
    match v {
        Json::Number(n) => n.as_i64().or_else(|| n.as_f64().map(|f| f as i64)),
        Json::String(s) => s.trim().parse().ok(),
        _ => None,
    }
}

/// `YYYY-MM-DD` prefix of a date or datetime, encoded as `y*10000 + m*100 + d`.
/// Accepts `2025-01-15`, `2025-01-15 10:30`, `2025-01-15T10:30:00` and
/// `2025-01-15-10:30`; the time is deliberately dropped.
pub fn as_ymd(v: &Json) -> Option<i64> {
    let s = match v {
        Json::String(s) => s.trim().to_string(),
        Json::Number(n) => n.to_string(),
        _ => return None,
    };
    let b = s.as_bytes();
    if b.len() < 10 {
        return None;
    }
    if b[4] != b'-' || b[7] != b'-' {
        return None;
    }
    let year: i64 = s.get(0..4)?.parse().ok()?;
    let month: i64 = s.get(5..7)?.parse().ok()?;
    let day: i64 = s.get(8..10)?.parse().ok()?;
    if !(1..=12).contains(&month) || !(1..=31).contains(&day) {
        return None;
    }
    Some(year * 10000 + month * 100 + day)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn flattens_scalars_and_lists() {
        assert_eq!(items(Some(&json!("a"))).len(), 1);
        assert_eq!(items(Some(&json!(["a", "b"]))).len(), 2);
        assert_eq!(items(Some(&json!([["a", "b"], "c"]))).len(), 3);
        assert_eq!(items(None).len(), 0);
        assert_eq!(items(Some(&json!(null))).len(), 0);
    }

    #[test]
    fn reads_every_accepted_datetime_spelling() {
        for s in [
            "2025-01-15",
            "2025-01-15 10:30",
            "2025-01-15T10:30:00",
            "2025-01-15-10:30",
        ] {
            assert_eq!(as_ymd(&json!(s)), Some(20250115), "{s}");
        }
        assert_eq!(as_ymd(&json!("15.01.2025")), None);
        assert_eq!(as_ymd(&json!("2025-13-01")), None);
    }

    #[test]
    fn reads_ints_from_strings() {
        assert_eq!(as_int(&json!("3")), Some(3));
        assert_eq!(as_int(&json!(3)), Some(3));
        assert_eq!(as_int(&json!("x")), None);
    }
}
