//! Term evaluation. Mirrors `lua/mdresearch/query/predicate.lua`.

use crate::protocol::{FieldFilter, Mode, Term};
use crate::value;
use regex::Regex;
use serde_json::Value as Json;
use std::collections::HashMap;
use std::sync::Mutex;

/// Compiled `/regex/` terms, keyed by pattern.
#[derive(Default)]
pub struct RegexCache(Mutex<HashMap<String, Option<Regex>>>);

impl RegexCache {
    pub fn matches(&self, pattern: &str, haystack: &str) -> bool {
        let mut cache = self.0.lock().unwrap();
        let entry = cache
            .entry(pattern.to_string())
            .or_insert_with(|| Regex::new(pattern).ok());
        match entry {
            Some(re) => re.is_match(haystack),
            None => false,
        }
    }
}

fn match_text(term: &Term, item: &Json, regexes: &RegexCache) -> bool {
    let s = value::as_text(item);
    match term.op.as_str() {
        "exact" => s == term.text(),
        "regex" => regexes.matches(&term.text(), &s),
        _ => s.contains(&term.text()),
    }
}

fn match_int(term: &Term, item: &Json) -> bool {
    let Some(n) = value::as_int(item) else {
        return false;
    };
    if term.op == "eq" {
        return Some(n) == term.number();
    }
    within(n, term)
}

fn match_date(term: &Term, item: &Json) -> bool {
    let Some(d) = value::as_ymd(item) else {
        return false;
    };
    within(d, term)
}

fn within(n: i64, term: &Term) -> bool {
    if let Some(from) = term.from {
        if n < from {
            return false;
        }
    }
    if let Some(to) = term.to {
        if n > to {
            return false;
        }
    }
    true
}

/// Is `term` satisfied by the flattened field value?
pub fn term(ftype: &str, term: &Term, items: &[&Json], regexes: &RegexCache) -> bool {
    let hit = items.iter().any(|item| match ftype {
        "int" => match_int(term, item),
        "date" | "datetime" => match_date(term, item),
        _ => match_text(term, item, regexes),
    });
    hit != term.negate
}

/// Evaluate a whole field filter against a raw frontmatter value.
pub fn field(filter: &FieldFilter, v: Option<&Json>, regexes: &RegexCache) -> bool {
    let items = value::items(v);
    match filter.mode {
        Mode::All => filter
            .terms
            .iter()
            .all(|t| term(&filter.ftype, t, &items, regexes)),
        Mode::Any => filter
            .terms
            .iter()
            .any(|t| term(&filter.ftype, t, &items, regexes)),
    }
}

/// Full text is matched against the file body, case-insensitively.
pub fn fulltext(filter: &FieldFilter, lowered_content: &str) -> bool {
    let hit = |t: &Term| {
        let found = lowered_content.contains(&t.text().to_lowercase());
        found != t.negate
    };
    match filter.mode {
        Mode::All => filter.terms.iter().all(hit),
        Mode::Any => filter.terms.iter().any(hit),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn filter(json: serde_json::Value) -> FieldFilter {
        serde_json::from_value(json).unwrap()
    }

    #[test]
    fn list_field_any_and_all() {
        let tags = json!(["linux", "server", "Tutorial"]);
        let re = RegexCache::default();

        let any = filter(json!({"key":"tags","type":"text","list":true,"mode":"any",
            "terms":[{"op":"contains","value":"macos"},{"op":"contains","value":"server"}]}));
        assert!(field(&any, Some(&tags), &re));

        let all = filter(json!({"key":"tags","type":"text","list":true,"mode":"all",
            "terms":[{"op":"contains","value":"linux"},{"op":"contains","value":"macos"}]}));
        assert!(!field(&all, Some(&tags), &re));
    }

    #[test]
    fn matching_ignores_capitalisation() {
        let re = RegexCache::default();
        let f = filter(json!({"key":"tags","type":"text","list":true,"mode":"any",
            "terms":[{"op":"contains","value":"tutorial"}]}));
        assert!(field(&f, Some(&json!(["Tutorial"])), &re));
    }

    #[test]
    fn negation_matches_a_missing_field() {
        let re = RegexCache::default();
        let f = filter(json!({"key":"tags","type":"text","list":true,"mode":"all",
            "terms":[{"op":"contains","value":"linux","negate":true}]}));
        assert!(field(&f, None, &re));
        assert!(!field(&f, Some(&json!(["linux"])), &re));
    }

    #[test]
    fn date_bounds_are_inclusive() {
        let re = RegexCache::default();
        let f = filter(json!({"key":"date","type":"date","mode":"any",
            "terms":[{"op":"between","from":20250101,"to":20250331}]}));
        assert!(field(&f, Some(&json!("2025-01-01")), &re));
        assert!(field(&f, Some(&json!("2025-03-31")), &re));
        assert!(!field(&f, Some(&json!("2025-04-01")), &re));
    }

    #[test]
    fn int_ranges() {
        let re = RegexCache::default();
        let f = filter(json!({"key":"prio","type":"int","mode":"any",
            "terms":[{"op":"between","from":4}]}));
        assert!(field(&f, Some(&json!(5)), &re));
        assert!(!field(&f, Some(&json!(3)), &re));
    }

    #[test]
    fn fulltext_ands_by_default() {
        let f = filter(json!({"key":"__fulltext","type":"text","mode":"all",
            "terms":[{"op":"contains","value":"docker"},{"op":"contains","value":"ripgrep"}]}));
        assert!(fulltext(&f, "uses ripgrep and docker"));
        assert!(!fulltext(&f, "uses docker"));
    }
}
