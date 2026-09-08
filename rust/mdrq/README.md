# mdrq — the mdresearch query engine

A standalone CLI. It knows nothing about Neovim: one JSON request in, JSON
Lines out. The Lua plugin is one client; `jq` and a shell are another.

```
mdrq --protocol            print the protocol version (currently 1) and exit
mdrq --version
mdrq --stdin               read the request from stdin
mdrq --query-file PATH     read the request from a file
```

## Request

```jsonc
{
  "protocol": 1,
  "root": "/home/me/notes",       // required
  "glob": "**/*.md",              // default
  "exclude": ["archive/**"],      // matched against the path relative to root
  "hidden": false,                // descend into dot-directories
  "follow": false,                // follow symlinks
  "limit": 2000,
  "sort": { "key": "date", "desc": false },

  // Which frontmatter keys to extract into every row, and how to compare them.
  "fields": [
    { "key": "title",  "type": "text",     "list": false },
    { "key": "tags",   "type": "text",     "list": true  },
    { "key": "prio",   "type": "int",      "list": false },
    { "key": "date",   "type": "date",     "list": false },
    { "key": "updated","type": "datetime", "list": false }
  ],

  // Filters are ANDed with each other. Inside one filter, `mode` decides.
  "filters": [
    { "key": "tags", "type": "text", "list": true, "mode": "all",
      "terms": [ { "op": "contains", "value": "linux" },
                 { "op": "contains", "value": "server" } ] },
    { "key": "date", "type": "date", "mode": "any",
      "terms": [ { "op": "between", "from": 20250101, "to": 20250331 } ] }
  ],

  "fulltext": { "key": "__fulltext", "type": "text", "mode": "all",
                "terms": [ { "op": "contains", "value": "docker" } ] }
}
```

### Terms

| field | meaning |
|---|---|
| `op` | `contains` (case-insensitive substring), `exact`, `regex` (RE2), `eq`, `between` |
| `value` | the literal, for `contains` / `exact` / `regex` / `eq`. Text terms arrive already lowercased |
| `from`, `to` | inclusive bounds for `between`. Dates are encoded `y*10000 + m*100 + d`; either bound may be absent |
| `negate` | invert this term |

A term is satisfied when *some* item of the field value matches it (a scalar
counts as a one-element list). `mode` then combines the terms: `any` = OR,
`all` = AND. A missing field satisfies a negated term and nothing else.

Date and datetime fields compare on the date part only. Accepted spellings:
`2025-01-15`, `2025-01-15 10:30`, `2025-01-15T10:30:00`, `2025-01-15-10:30`.

## Response

JSON Lines. One object per matching file, then a trailing meta line:

```json
{"path":"/home/me/notes/a.md","rel":"a.md","fields":{"title":"A","tags":["linux"],"date":"2025-01-15"}}
{"__meta":true,"truncated":false,"scanned":1423}
```

`fields` carries only the keys declared in `fields`. Files without usable
frontmatter are skipped silently — that is a non-match, not an error. Errors
go to stderr with a non-zero exit code.

## Frontmatter

Real YAML (`serde_yaml`) between the opening and closing `---`, read from at
most the first 64 KiB. One pre-processing step: `tags: #a #b` — the inline tag
form, which YAML would read as a comment — is rewritten to `tags: ["a", "b"]`
before parsing.

## Building

```sh
cargo build --release        # target/release/mdrq
cargo test
```

The plugin finds the binary at `$PATH`, at `config.mdrq.cmd`, or at
`rust/mdrq/target/{release,debug}/mdrq` inside the plugin directory.
