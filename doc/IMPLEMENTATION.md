# mdresearch — Implementation strategy

> Task 4 deliverable. Order, contracts, and the check that closes each stage.

## Principle

Build **inside-out**: the query model first, then the reference engine, then
the UI, then the accelerator. Every stage lands with tests that run headless,
so a stage is never "probably fine". The Rust backend is last on purpose — it
is an optimisation of a thing that already works, and it is verified by
diffing it against the Lua backend rather than by its own opinion.

## Stages

### S1 — Config + workspaces  *(no user-visible behaviour yet)*
`config.lua`, `workspace.lua`, `state.lua`, `util.lua`.

- `config.normalize(opts)` fills defaults, expands `~`, sorts nothing, and
  **errors on unknown keys** and on a field with an unknown `type`.
- Each workspace gets `fields` (ordered), a `by_key` index, and `columns`
  defaulted to every field with `title` first plus a virtual `path` column.
- Done when: `config_spec` accepts a full config and rejects six malformed
  ones with useful messages.

### S2 — Query model
`query/lexer.lua`, `query/parser.lua`, `query/predicate.lua`, `query/init.lua`.

- Lexer: split on whitespace, honour `"…"` and `'…'`, keep a quoted value
  atomic, tolerate an unterminated quote (take the rest).
- Parser, per field type, produces `Term`s:
  - text — `foo` contains, `=foo` exact, `/re/` regex, `!` prefix negates
  - int — `3`, `>=3`, `>3`, `<=3`, `<3`, `1..5`
  - date/datetime — `2025-01-15`, `2025-01`, `2025` (implicit range),
    `>=d` / `after:d` on-or-after, `<=d` / `before:d` on-or-before, `a..b`
    between, all **inclusive**; datetimes compare on the date part only.
  - a leading `any:` / `all:` on the whole field overrides its mode.
- Predicates take a *parsed* value and are total: a missing field never
  matches a positive term and always matches a negated one.
- Done when: `lexer_spec`, `parser_spec`, `predicate_spec` are green,
  including the "quoted value with a space" and "inclusive boundary" cases
  from CLAUDE.md.

### S3 — Frontmatter reader
`engine/frontmatter.lua`.

- Read at most 64 KiB; require `---` on line 1; stop at the closing `---`.
- Support: `key: scalar`, `key: [a, b]`, block sequences (`  - a`), quoted
  scalars, `#` comments, `|`/`>` block scalars, and `tags: #a #b`.
- Coerce per the workspace field type at *match* time, not at parse time, so
  one cache entry serves every workspace.
- Cache `path -> { mtime, size, fields }`; `BufWritePost *.md` invalidates.
- Done when: `frontmatter_spec` parses the fixture vault, multi-line tags
  included, and a malformed file yields `nil` instead of an error.

### S4 — Lua backend
`engine/rg.lua`, `engine/lua.lua`, `engine/init.lua`.

- `rg.files(ws, cb)` → all paths; `rg.with_literal(paths, lit, cb)` → subset.
- Push down only literals that are *necessarily* present (see TOOLING §3);
  intersect the resulting sets; fall back to `rg --files`, then to a
  `vim.uv.fs_scandir` walk.
- Everything async on `vim.system`, with a single in-flight search that
  `engine.cancel()` kills.
- Done when: `engine_spec` runs eight queries against the fixture vault and
  gets exactly the expected paths — with `rg` forced off as well as on, which
  proves the prefilter is a true superset.

### S5 — UI
`ui/table.lua`, `ui/results.lua`, `ui/mask.lua`, `ui/highlight.lua`.

- `table.render` computes column widths from the data, clamps to configured
  maxima, truncates with `…`, and returns byte spans so highlights do not
  need a second pass. Display width via `vim.fn.strdisplaywidth`.
- Results buffer: `nomodifiable`, `nofile`, row→`Row` map in a local table;
  loading a row opens it in the window the search came from. A row is
  addressable by 1-based index, so `:3MdResearchOpen` needs no cursor.
- Mask buffer: one line per field, `Label  [mode] │ value`; the cursor is
  kept in the value column; a field is addressable by key, label or index.
- Done when: `table_spec` covers padding/truncation/CJK width, and the mask
  round-trips a query through render → read-back unchanged.

### S6 — Wiring
`commands.lua`, `actions.lua`, `keymaps.lua`, `autocmds.lua`, `health.lua`,
`plugin/`.

- The action registry (ARCHITECTURE §5.2), one Ex command per action or
  argument shape (§5.1), the `MdResearch` augroup, and the two `User` events
  from §4. No key is mapped: `keymaps` in `setup()` is validated against the
  registry and applied per scope.
- Done when: a real `nvim` session opens the mask, searches, and loads a file
  using commands only, and `api_spec` covers the registry, the commands, the
  keymap resolution and every mask/table action.

### S7 — Rust accelerator
`rust/mdrq/*`, `engine/mdrq.lua`, `scripts/build-mdrq.sh`.

- Implement the JSON protocol; `--protocol` prints the version so the Lua
  side can refuse a stale binary.
- Reuse `fmd`'s crate set: `ignore`, `globset`, `rayon`, `serde`,
  `serde_yaml`, `chrono`.
- Done when: `cargo test` is green **and** `parity_spec` gets byte-identical
  row sets from both backends over the fixture vault.

## Risks and how each is contained

| risk | containment |
|---|---|
| YAML subset too small for a real vault | frontmatter reader returns `nil` (file skipped, not an error) and `:checkhealth` counts unparseable files |
| `rg` prefilter drops a hit | prefilter only ever pushes down literals that must appear; `engine_spec` runs every query with the prefilter disabled and compares |
| two backends drift | `parity_spec` diffs them; the Lua one is normative |
| large vault blocks the UI | all IO through `vim.system` callbacks; `limit` caps rows; one in-flight search, cancellable |
| datetime format zoo | one `to_ymd()` funnel, tested against all four accepted spellings |
