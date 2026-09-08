# mdresearch

Search Markdown notes by their YAML frontmatter — multi-line tag lists
included — and by full text, from inside Neovim. Results arrive as a table in
a scratch buffer; put the cursor on a row and load that file.

The plugin maps no key of its own: everything is an Ex command, a Lua
function, or a named action you bind yourself.

```
1 file  ·  notes  ·  tags all(linux server)

Title              │ Tags                    │ Date       │ Path
───────────────────┼─────────────────────────┼────────────┼────────────────
Linux server setup │ linux, server, tutorial │ 2025-01-15 │ linux-server.md
```

## Install

Any plugin manager. With lazy.nvim:

```lua
{
  dir = "~/Projects/mdresearch",
  opts = {
    workspaces = {
      {
        name = "notes",
        root = "~/notes",
        fields = {
          { key = "title",   type = "text" },
          { key = "tags",    type = "text", list = true, mode = "all" },
          { key = "status",  type = "text" },
          { key = "prio",    type = "int" },
          { key = "date",    type = "date" },
          { key = "updated", type = "datetime" },
        },
        columns = { "title", "tags", "date", "path" },
        sort = { key = "date", desc = true },
      },
    },
  },
}
```

Nothing else is required. `ripgrep`, if present, is used to narrow the search;
`scripts/build-mdrq.sh` builds an optional Rust backend that does the whole
query in one process. `:checkhealth mdresearch` reports what it found.

## Use

`:MdResearch` opens the search mask — one line per standard tag of the current
workspace, plus a free-text line:

```
Title    [any] │
Tags     [all] │ linux server
Status   [any] │ published
Prio     [any] │ >=3
Date     [any] │ 2025-01-01..2025-03-31
Text     [all] │ docker
```

Empty fields are ignored. `[any]`/`[all]` is the or/and condition over that
field's values; `:MdResearchToggleMode` flips it. `:MdResearchSubmit`
searches.

Values are space-separated, and quoted when they contain a space:
`linux server "personal notes"`. Capitalisation never matters.

| field type | you can write |
|---|---|
| text | `foo`, `=exact`, `/regex/`, `!not-foo` |
| int | `3`, `>=3`, `<5`, `1..5` |
| date, datetime | `2025-01-15`, `2025-01`, `2025`, `>=2025-01-15`, `before:2025-06`, `2025-01-01..2025-03-31` |

Every date bound includes the day it names. Datetime fields are searched by
date alone.

## Commands

| | |
|---|---|
| `:MdResearch` | the search mask |
| `:MdResearchSearch tags="linux server" date=>=2025-01 text=docker` | skip the mask |
| `:MdResearchResume` / `:MdResearchResults` | last query / last table |
| `:MdResearchWorkspace [name]`, `…Next`, `…Prev` | switch workspace |
| `:MdResearchSubmit`, `…ToggleMode [f]`, `…ClearField[!] [f]`, `…SetField f=v`, `…Field next` | drive the mask |
| `:[count]MdResearchOpen [split]`, `:[count]MdResearchPreview`, `:MdResearchRefine` | drive the table |
| `:MdResearchClose`, `:MdResearchReload`, `:MdResearchHealth`, `:MdResearchActions` | the rest |

The mask and table commands work from any window, and take a field name or a
row count instead of the cursor. The same set is a Lua API —
`require("mdresearch").mask.submit()`, `md.results.open("vsplit", { index = 3 })`,
`md.search({ tags = "linux server" }, { tags = "all" })` — and a registry of
named actions (`:MdResearchActions`) you can map:

```lua
keymaps = {
  global  = { ["<leader>ms"] = "open", ["<leader>mw"] = "workspace" },
  mask    = { ["<CR>"] = "mask.submit", ["<C-a>"] = "mask.toggle_mode" },
  results = { ["<CR>"] = "results.open", ["p"] = "results.preview" },
}
```

An unknown action name, or one used in the wrong scope, is a setup error
rather than a key that silently does nothing.

`:help mdresearch-commands`, `:help mdresearch-api` and
`:help mdresearch-mappings` document the whole surface.

## Layout

```
lua/mdresearch/   the plugin          doc/ARCHITECTURE.md   config, autocmds, API
rust/mdrq/        optional backend    doc/TOOLING.md        why rg + mdrq, not fzf
tests/            make test-lua       doc/STRUCTURE.md      the lua/rust split
                                      doc/IMPLEMENTATION.md build order
```

```sh
make test        # 217 Lua specs + 26 Rust tests
make build       # the optional Rust backend
```

The Lua backend is the reference implementation; `tests/mdresearch/parity_spec.lua`
runs both backends over the same fixture vault and requires identical rows.
