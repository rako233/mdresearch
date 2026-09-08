# mdresearch — Project structure

> Task 3 deliverable. The rule: **Lua under `lua/`, everything else under a
> language-named top-level directory.** No `.rs` under `lua/`, no build
> artefacts inside the runtimepath, no generated files checked in.

```
mdresearch/
├── CLAUDE.md
├── README.md
├── Makefile                      # test / build / fmt entry points
│
├── doc/                          # design docs + :help
│   ├── ARCHITECTURE.md           # task 1
│   ├── TOOLING.md                # task 2
│   ├── STRUCTURE.md              # task 3 (this file)
│   ├── IMPLEMENTATION.md         # task 4
│   └── mdresearch.txt            # vim help file
│
├── plugin/
│   └── mdresearch.lua            # installs the commands; no other work
│
├── lua/                          # ── Lua only ──────────────────────────
│   └── mdresearch/
│       ├── init.lua              # the public Lua API: setup, open, search,
│       │                         #   md.mask.*, md.results.*, status
│       ├── config.lua            # defaults + validation + normalisation
│       ├── workspace.lua         # workspace registry, switching, detection
│       ├── state.lua             # current ws, last query, last rows
│       ├── util.lua              # paths, tables, shell quoting
│       ├── commands.lua          # :MdResearch* — one spec per command
│       ├── actions.lua           # named actions: the mappable surface
│       ├── keymaps.lua           # applies the maps *you* declare (none by default)
│       ├── autocmds.lua          # the MdResearch augroup
│       ├── health.lua            # :checkhealth mdresearch
│       │
│       ├── query/
│       │   ├── init.lua          # Query construction / matching / describe
│       │   ├── lexer.lua         # quote-aware value splitting
│       │   ├── parser.lua        # string -> typed Term[] per field type
│       │   └── predicate.lua     # Term x value -> boolean
│       │
│       ├── engine/
│       │   ├── init.lua          # backend selection + async dispatch
│       │   ├── lua.lua           # reference backend
│       │   ├── mdrq.lua          # Rust backend client (JSONL over stdout)
│       │   ├── rg.lua            # ripgrep invocations + uv walk fallback
│       │   └── frontmatter.lua   # YAML-subset reader with an mtime cache
│       │
│       └── ui/
│           ├── mask.lua          # search mask buffer
│           ├── results.lua       # result table buffer
│           ├── table.lua         # column widths, padding, truncation
│           └── highlight.lua     # highlight group definitions
│
├── rust/                         # ── Rust only ─────────────────────────
│   └── mdrq/
│       ├── Cargo.toml
│       ├── README.md             # the query/response protocol
│       └── src/
│           ├── main.rs           # CLI, stdin/stdout plumbing
│           ├── protocol.rs       # Request/Response serde types
│           ├── frontmatter.rs    # YAML frontmatter -> Value map
│           ├── value.rs          # typed coercion: text/int/date/datetime
│           ├── filter.rs         # Term evaluation, any/all, ranges
│           └── scan.rs           # walk + parallel filter + full text
│
├── scripts/
│   └── build-mdrq.sh             # cargo build --release + report the path
│
└── tests/                        # ── Lua tests, no external runner ─────
    ├── run.lua                   # nvim --headless -l tests/run.lua
    ├── harness.lua               # describe/it/expect, ~120 lines
    ├── fixtures/vault/           # the sample note tree every spec uses
    └── mdresearch/
        ├── lexer_spec.lua
        ├── parser_spec.lua
        ├── predicate_spec.lua
        ├── frontmatter_spec.lua
        ├── engine_spec.lua
        ├── table_spec.lua
        └── parity_spec.lua       # lua backend vs mdrq, same rows
```

## Boundaries

| boundary | contract |
|---|---|
| `plugin/` → `lua/` | `plugin/mdresearch.lua` only declares commands; the first one to run calls `require("mdresearch")`. Startup cost stays at one small file. |
| `ui/` → `engine/` | only through `engine.run(workspace, query, cb)`. The UI never reads a file. |
| `lua/` → `rust/` | only through the JSON protocol in `rust/mdrq/README.md`. Lua never links Rust, never parses its source, and works when it is absent. |
| `rust/` → `lua/` | nothing. `mdrq` is a standalone CLI, testable with `cargo test` alone. |
| `tests/` | pure Lua, run by Neovim itself. `cargo test` covers Rust. `make test` runs both. |

`rust/mdrq/target/` is git-ignored; the built binary is discovered at runtime,
never committed.
