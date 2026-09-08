# mdresearch — External tool strategy

> Task 2 deliverable. This is the analysis that fed back into
> [ARCHITECTURE.md](ARCHITECTURE.md) §2 (the backend abstraction).

## 1. What the search actually needs

1. **Enumerate** Markdown files under a workspace root, honouring globs and
   ignore files.
2. **Filter** on typed frontmatter fields: text/int/date/datetime, per-field
   AND/OR over multiple values, inclusive date ranges, case-insensitive.
3. **Extract** the frontmatter values of the *surviving* files — the result
   buffer is a table, so we need the values, not just the paths.
4. **Full-text** filter on the file body.

Step 3 is the one that decides the architecture: whatever tool we use has to
hand back field *values*, or we have to re-read the matched files ourselves.

## 2. Candidate tools

### `fmd` (the fork at `github.com/rako233/fmd`)

Reviewed at commit `9f126e9` (v0.1.1, single 832-line `src/main.rs`).

What it already does well:

- YAML frontmatter parsing including multi-line `tags:` block sequences, plus
  inline `#tag` metadata — exactly our input format.
- Arbitrary field filtering, `-f field:pattern`, case-insensitive.
- `ignore`-crate walking (respects `.gitignore`), `globset`, `rayon`
  parallelism. Fast and correct on enumeration.
- Date filtering, `--date-after` / `--date-before`, inclusive, ISO input.

Where it stops short of this plugin's requirements:

| requirement | fmd v0.1.1 |
|---|---|
| structured output for the table | ✗ prints paths only (`output_files`) |
| AND across values of one field | ✗ same-type filters are always OR |
| date compare on an *arbitrary* field | ✗ hardcoded to `date`/`created`/`updated`/`modified` |
| date *equality* / `between` on one field | partial — only the two global bounds |
| datetime values | ✗ `parse_date_from_yaml_value` is `%Y-%m-%d` only |
| int fields with `>=`/ranges | ✗ every field is a regex/substring match |
| full-text body search | ✗ `--content` is still on `PLAN.md`, not implemented |
| negation | ✗ `--exclude-*` is on `PLAN.md` |

So `fmd` as shipped covers roughly the enumeration half and none of the
output half. Using it unchanged would still force us to re-open every hit to
build the table, at which point it is only buying us the candidate list.

### `rg`

Not frontmatter-aware, but unbeatable at the two things we need most:
enumerating files (`rg --files`) and answering *"which files contain this
literal"* (`rg -l -F -i`). It is already installed, needs no build step, and
its answer to the full-text half of the query is **exact**, not a prefilter.

### `fzf`

Interactive fuzzy filtering over a list. It is a *picker*, and the
requirement is a table buffer with a load-on-cursor keybinding, not a picker.
Shelling out to `fzf` would mean a terminal buffer we cannot render a table
into or attach extmarks to. **Not used for the search path.** It stays useful
as an optional front end for `:MdResearchWorkspace` — but `vim.ui.select`
already covers that and lets the user route it to their own picker.

## 3. Decision

**Two interchangeable backends behind `engine.run()`, with the Lua one as the
reference implementation.**

### Backend `lua` — always available, zero build step

```
   query
     │
     ├─ push-down: collect the literals that a hit *must* contain
     │     (all-mode terms, single any-mode terms, full-text all-terms;
     │      never negated terms, never regex terms)
     │
     ├─ rg -l -i -F <literal> …  ∩ …          → candidate paths
     │     (no literals? rg --files)          → all paths
     │     (no rg at all?   vim.uv walk)
     │
     ├─ read frontmatter of candidates (cached by mtime)
     ├─ evaluate the full typed predicate in Lua   → precise hits
     └─ rg -l -i -F over the hits for full-text    → rows
```

The push-down is a **superset filter**: `rg` searches the whole file, so it
can only ever return too many candidates, never too few, and the Lua
predicate then decides. That keeps correctness in one place (Lua) while still
skipping the vast majority of files without opening them.

### Backend `mdrq` — optional accelerator, `rust/mdrq`

A small Rust binary that does the whole pipeline in one process and emits
**JSON Lines** so the table can be built with no second read:

```
$ mdrq --query-file query.json      # or query JSON on stdin
{"path":"/n/a.md","rel":"a.md","fields":{"title":"A","tags":["linux"],"date":"2025-01-15"}}
{"path":"/n/b.md","rel":"b.md","fields":{...}}
```

It reuses `fmd`'s proven approach (`ignore` + `globset` + `rayon` + a
frontmatter reader that stops at the closing `---`) and adds the seven rows
missing from the table above: typed fields, per-field any/all, per-field date
comparison, datetime, ints, negation, full-text, and structured output.

It lives in this repository rather than in the `fmd` fork because its
interface is this plugin's query protocol, not a general-purpose CLI — and
because keeping it here preserves the lua/non-lua split (see
[STRUCTURE.md](STRUCTURE.md)). The pieces that are genuinely general — sorting,
exclusion filters, content search — are worth upstreaming into the `fmd` fork
separately; they are already on its `PLAN.md`.

### Selection

`backend = "auto"` (default) resolves once per session:

1. `config.mdrq.cmd` if set, else `mdrq` on `$PATH`, else
   `rust/mdrq/target/release/mdrq` next to the plugin — if it runs
   `--protocol` and reports a compatible version → **mdrq**.
2. otherwise → **lua** (which uses `rg` when present, and a `vim.uv` walk when
   not).

`:checkhealth mdresearch` reports which one won and why.

## 4. Why not one backend

The Lua backend has to exist: it is the fallback when no one has run
`cargo build`, and it is the executable specification the Rust backend is
tested against (`tests/mdresearch/parity_spec.lua` runs both over the same
fixture vault and diffs the rows). The Rust backend has to exist because
opening tens of thousands of notes from Lua to read six lines of YAML each is
the one thing that will not scale.
