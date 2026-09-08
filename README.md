# mdresearch

Search Markdown notes by their YAML frontmatter, multi-line tag lists
included, and by full text, from inside Neovim. Hits arrive as a table in a
scratch buffer. Put the cursor on a row, hit your open key, and the file
loads.

The plugin maps no key of its own. Everything it does is an Ex command, a Lua
function, or a named action you bind yourself.

```
1 file  ·  notes  ·  tags all(linux server)

Title              │ Tags                    │ Date       │ Path
───────────────────┼─────────────────────────┼────────────┼────────────────
Linux server setup │ linux, server, tutorial │ 2025-01-15 │ linux-server.md
```

## Requirements

Neovim 0.12 or newer, because `vim.pack` is the plugin manager this expects
you to install it with. Nothing else is mandatory.

Two optional pieces make it faster, and `:checkhealth mdresearch` tells you
which ones it found:

- **ripgrep** narrows the candidate files before the Lua backend parses them.
  Without it the plugin walks the directory itself, which works but is slower
  on a large vault.
- **mdrq**, the Rust backend in `rust/mdrq/`, does the whole query in one
  process. Needs a Rust toolchain to build. See [the backends
  section](#backends).

## Install

The repository is private, so a plugin manager has to clone it over SSH. If
you have the `github.com-rako` host alias in `~/.ssh/config`, use
`git@github.com-rako:rako233/mdresearch.git` as the source. Plain
`https://github.com/rako233/mdresearch` works once the repo is public.

### vim.pack

Neovim's own plugin manager since 0.12, and the one these instructions
assume. No third-party manager needed. In `init.lua`:

```lua
vim.pack.add({
  { src = "git@github.com-rako:rako233/mdresearch.git" },
})

require("mdresearch").setup({
  workspaces = {
    {
      name = "notes",
      root = "~/notes",
      fields = {
        { key = "title", type = "text" },
        { key = "tags",  type = "text", list = true, mode = "all" },
        { key = "date",  type = "date" },
      },
    },
  },
})
```

`vim.pack.add` clones on first start and asks you to confirm; pass
`{ confirm = false }` as the second argument to skip the prompt. The install
directory is named after the repository, so `name` is only worth setting when
you want a different one.

Pin a revision with `version`, which takes a branch, a tag, a commit hash, or
a semver range:

```lua
vim.pack.add({
  {
    src     = "git@github.com-rako:rako233/mdresearch.git",
    version = vim.version.range("^0.2"),
  },
})
```

Housekeeping is three calls: `vim.pack.update()` shows a confirmation buffer
you accept with `:write` and reject with `:quit`, `vim.pack.get()` lists what
is installed, and `vim.pack.del({ "mdresearch" })` removes it from disk.

One thing to know: while `init.lua` is being sourced, `vim.pack.add` does not
source the plugin's `plugin/` files right away, it defers them to the normal
startup step. That is fine here. `setup()` installs the commands itself, and
`plugin/mdresearch.lua` installs the same set idempotently a moment later.

### lazy.nvim

Still supported, if that is what the rest of your config uses.

```lua
{
  "rako233/mdresearch",
  cmd  = { "MdResearch", "MdResearchSearch", "MdResearchResume", "MdResearchWorkspace" },
  opts = {
    -- the same table setup() takes, see Configuration below
    workspaces = { { name = "notes", root = "~/notes", fields = { { key = "tags", list = true } } } },
  },
}
```

`opts` is passed straight to `setup()`. For the private repo add
`url = "git@github.com-rako:rako233/mdresearch.git"` to the spec.

### Manual, no manager

```sh
git clone git@github.com-rako:rako233/mdresearch.git \
  ~/.local/share/nvim/site/pack/plugins/start/mdresearch
```

Then call `require("mdresearch").setup()` from your config.

### Working on a local checkout

```lua
-- lazy.nvim
{ dir = "~/Projects/mdresearch", opts = { workspaces = { … } } }

-- vim.pack does not manage local paths; add it to the runtimepath yourself
vim.opt.runtimepath:prepend("~/Projects/mdresearch")
```

## Configuration

`setup()` validates everything and rejects unknown keys by name, so a typo
never silently disables a feature. That includes a misspelled action name in
`keymaps`.

At least one workspace is required. Every other key has a default:

```lua
require("mdresearch").setup({
  workspaces        = {},      -- required, see below
  default_workspace = nil,     -- default: the first workspace

  backend = "auto",            -- "auto" | "mdrq" | "lua"
  mdrq    = { cmd = nil, args = {} },   -- cmd = nil means search $PATH
  rg      = { cmd = "rg", args = {} },
  limit   = 2000,              -- cap the rows in the table
  cache   = true,              -- cache parsed frontmatter per file

  ui = {
    mask = {
      border = "rounded",
      width  = 0.6,            -- fraction of the editor
      height = 0.5,
      title  = " mdresearch ",
      hint   = true,           -- the hint line under the mask
      insert = true,           -- open the mask in insert mode
    },
    results = {
      style       = "split",   -- "split" | "float" | "tab"
      position    = "botright",
      size        = 0.45,
      show_header = true,
      show_count  = true,
      link = {                 -- what MdResearchYankLink copies
        format   = "markdown", -- "markdown" | "wiki" | "path"
        label    = "title",    -- field for the link text, false = file stem
        ext      = true,       -- keep the extension in the target
        register = nil,        -- default register; nil = the unnamed one
      },
    },
    icons = { any = "any", all = "all" },
  },

  keymaps = { global = {}, mask = {}, results = {} },   -- nothing by default

  on_open = nil,   -- function(path, row), runs before a row's file is loaded
})
```

### Workspaces

A workspace is a Markdown directory plus the standard tags its notes use.
Each one has its own fields, columns and sort order.

```lua
{
  name    = "notes",              -- required, unique
  root    = "~/notes",            -- required, ~ and $VARS are expanded
  glob    = "**/*.md",            -- which files to consider
  exclude = { "archive/**" },     -- globs to skip
  hidden  = false,                -- descend into dot-directories
  follow  = false,                -- follow symlinks

  fields = {
    { key = "title",   type = "text" },
    { key = "tags",    type = "text", list = true, mode = "all" },
    { key = "status",  type = "text" },
    { key = "prio",    type = "int" },
    { key = "date",    type = "date" },
    { key = "updated", type = "datetime" },
  },

  columns = { "title", "tags", "date", "path" },
  sort    = { key = "date", desc = true },
}
```

**Fields.** `key` is the frontmatter key and is required. `type` is one of
`text`, `int`, `date`, `datetime` and defaults to `text`. `label` is the name
shown in the mask and the table header, and defaults to the capitalised key.
`list = true` marks a field whose value is a YAML sequence, the multi-line
tags case. `mode` is that field's default `any` or `all`. `width` caps the
column.

A scalar is always treated as a one-element list, so `list` only changes how
`mode` reads; parsing works either way. Three spellings give the same list:
a multi-line block, the flow form `tags: [a, b]`, and `tags: #a #b`. Note
that a bare `tags: a b` is one string containing a space, not two values.

**Columns.** A list of field keys, or `{ key = …, label = …, width = … }`
tables. Two extra keys are always available: `path` and `rel`, the absolute
and workspace-relative file path. Omit `columns` and you get every field plus
`path`.

**Sort.** `{ key = <field key, or path, or rel>, desc = <boolean> }`.
Defaults to the first field, ascending.

Switching between workspaces happens with `:MdResearchWorkspace`, its `Next`
and `Prev` variants, or on its own: when `DirChanged` lands inside another
workspace root, the plugin follows. The current workspace and the last query
survive a restart, in `stdpath("state") .. "/mdresearch.json"`.

### The frontmatter it reads

```markdown
---
title: Linux server setup
tags:
  - linux
  - server
  - tutorial
status: published
prio: 3
date: 2025-01-15
updated: 2025-02-01 09:30
---

Body text, searched by the free-text field.
```

A file with no frontmatter, or with frontmatter that fails to parse, is
skipped rather than reported as an error. Date and datetime values are read
from `2025-01-15`, `2025-01-15 10:30`, `2025-01-15T10:30:00` and
`2025-01-15-10:30`.

## Operation

### The search mask

`:MdResearch` opens one line per standard tag of the current workspace, plus
a free-text line:

```
Title    [any] │
Tags     [all] │ linux server
Status   [any] │ published
Prio     [any] │ >=3
Date     [any] │ 2025-01-01..2025-03-31
Updated  [any] │
Text     [all] │ docker
```

Empty fields sit out of the search. `[any]`/`[all]` is the or/and condition
over that field's values, and `:MdResearchToggleMode` flips it.
`:MdResearchSubmit` runs the search and closes the mask.

You type into the mask as in any buffer. The cursor is kept out of the label
column, so you cannot damage the layout. The hint line under the mask lists
your own mappings when you have declared some and the commands when you have
not; `ui.mask.hint = false` turns it off.

Every mask command works from any window. Each one finds the open mask
itself, and takes a field name instead of relying on the cursor line, which
is what makes them mappable from anywhere and scriptable.

### Query syntax

Values are separated by spaces, and a value containing a space has to be
quoted:

```
linux server "personal notes"
```

Capitalisation never matters, on either side of the comparison.

| field type | you can write |
|---|---|
| text | `foo` contains · `=foo` exact · `/fo.*o/` regex · `!foo` negated · `#foo` same as `foo` |
| int | `3` · `>=3` `>3` `<=3` `<3` · `1..5` inclusive range · `!3` |
| date, datetime | `2025-01-15` · `2025-01` · `2025` · `>=2025-01-15` · `<=2025-06` · `after:2025-01` · `before:2025-06` · `2025-01-01..2025-03-31` |

Dates are ISO and read left to right, so a partial date is a period rather
than an error. `2025-01` means any day in January 2025, and as a range bound
it expands to the end that faces the range: `2025-01..2025-06` covers
2025-01-01 through 2025-06-30.

Every bound written with `>=`, `<=`, `after:`, `before:` or `..` includes the
day it names. `>` and `<` exclude the whole named period, so `>2025-01` starts
on 2025-02-01. Write no spaces around `..`, and do not combine `..` with a
comparison operator. For an exclusive range, either move the bound by a day
or AND two comparisons in one field:

```vim
:MdResearchSearch date=all:">2025-01-01 <2025-04-01"
```

Datetime fields are compared on their date part only. Searching by time of
day is deliberately not supported.

**Overriding and/or inline.** A leading `all:` or `any:` on a field beats the
mask toggle and the field's configured `mode`. `and:` and `or:` are aliases.
This matters for the two-comparison trick above, since fields default to
`any` and an OR of two open bounds matches almost everything.

**Full text.** Terms are literals matched against the whole file and ANDed by
default. `!term` excludes, `any:` switches to OR.

**A note on `/regex/`.** The Lua backend uses Lua patterns, mdrq uses RE2.
They agree on literals, `.`, `*`, `+`, `^`, `$` and `[...]` classes, and
disagree on everything else, `%d` against `\d` among them. Stick to the
common subset if you expect to switch backends.

### The result table

A `nomodifiable` scratch buffer with `filetype=mdresearch-results`: a summary
line, the column header, then one line per file. Columns are sized to the
data and truncated with an ellipsis rather than wrapped.

The line-to-file mapping is held out of band, not parsed back out of the
buffer text, so truncating a long path can never send `:MdResearchOpen` to
the wrong file.

Load a row with `:MdResearchOpen`, peek at one with `:MdResearchPreview`,
copy a link to one with `:MdResearchYankLink`, reopen the mask on the same
query with `:MdResearchRefine`. The first three take a `{count}` naming a row
outright, as in `:3MdResearchOpen vsplit`, so they work with the cursor
elsewhere.

### Copying a link to a row

Put the cursor on a row and `:MdResearchYankLink` copies a link to that file
into a register. The target is always the path relative to the workspace
root, so the link resolves from any note in the same vault.

```vim
:MdResearchYankLink                    " the configured format, unnamed register
:MdResearchYankLink +                  " into the system clipboard
:MdResearchYankLink format=wiki        " override the format for this call
:3MdResearchYankLink + format=path     " row 3, no cursor needed
```

Three formats, shown for `projects/rust-cli.md` titled "Rust CLI patterns":

| `format` | result |
|---|---|
| `markdown` | `[Rust CLI patterns](projects/rust-cli.md)` |
| `wiki` | `[[projects/rust-cli.md]]` |
| `path` | `projects/rust-cli.md` |

`ui.results.link` sets the default, and the command and the API override it
per call. `label` names the field the link text comes from and defaults to
`title`; set `label = false` for the file name instead. `ext = false` drops
the extension from the target, which is what a wiki link usually wants:
`[[projects/rust-cli]]`.

The escaping is handled. A markdown target containing a space or a paren is
wrapped in angle brackets, and `[` or `]` in the label is backslash-escaped,
so the link survives a renderer.

The yank lands in the unnamed register, and in `+` or `*` as well when your
`clipboard` option contains `unnamedplus` or `unnamed`. So if you already run
`clipboard=unnamedplus`, a bare yank reaches the system clipboard with no
extra configuration. Name a register to bypass that.

Bind it like anything else, and bind a second format with a Lua function:

```lua
results = {
  ["y"]  = "results.yank_link",
  ["gy"] = function() require("mdresearch").results.yank_link({ format = "path" }) end,
},
```

## Commands

Every command exists from startup, before `setup()` has run, so `<Tab>`
completes them. The ones that need a mask or a table say so rather than doing
nothing.

| command | what it does |
|---|---|
| `:MdResearch` | open the search mask |
| `:MdResearchSearch tags="linux server" date=>=2025-01 text=docker` | search without the mask; `text=` and `fulltext=` address the free-text field |
| `:MdResearchResume` | reopen the mask filled with the last query |
| `:MdResearchResults` | reopen the last result table |
| `:MdResearchClose` | close the mask if one is open, else the table |
| `:MdResearchWorkspace [name]` | switch workspace, or pick one with `vim.ui.select` |
| `:MdResearchWorkspaceNext`, `…Prev` | cycle workspaces |
| `:MdResearchSubmit` | run the search the mask describes |
| `:MdResearchToggleMode [field]` | flip `[any]`/`[all]` |
| `:MdResearchClearField[!] [field]` | empty one field, or with `!` every field |
| `:MdResearchSetField tags=linux server` | write a value into a mask field |
| `:MdResearchField {next\|prev\|first\|last\|<field>\|<n>}` | move the cursor to a field |
| `:[count]MdResearchOpen [edit\|split\|vsplit\|tabedit]` | load a row's file |
| `:[count]MdResearchPreview` | show the head of a row's file in a float |
| `:[count]MdResearchYankLink [register] [format=…]` | copy a link to a row's file, relative to the workspace |
| `:MdResearchRefine` | reopen the mask with the query the table came from |
| `:MdResearchReload` | drop the frontmatter cache, re-detect the backend |
| `:MdResearchHealth` | the `:checkhealth mdresearch` report |
| `:MdResearchActions` | list the action names you can map |

Wherever a command takes `[field]`, that is a field key, its label, `text`
for the free-text row, or a 1-based row number.

## Keymaps

The plugin ships no mapping. Declare your own in `setup()`, per scope, as
`lhs = action`:

```lua
keymaps = {
  global = {
    ["<leader>ms"] = "open",
    ["<leader>mr"] = "resume",
    ["<leader>ml"] = "last",
    ["<leader>mw"] = "workspace",
  },
  mask = {
    ["<CR>"]    = "mask.submit",
    ["<C-a>"]   = "mask.toggle_mode",
    ["<C-u>"]   = "mask.clear_field",
    ["<Tab>"]   = "mask.next_field",
    ["<S-Tab>"] = "mask.prev_field",
    ["<Esc>"]   = "mask.cancel",
  },
  results = {
    ["<CR>"]  = "results.open",
    ["<C-x>"] = "results.split",
    ["<C-v>"] = "results.vsplit",
    ["<C-t>"] = "results.tab",
    ["p"]     = "results.preview",
    ["y"]     = "results.yank_link",
    ["r"]     = "results.refine",
    ["q"]     = "results.close",
  },
}
```

`global` maps are set once by `setup()`. `mask` and `results` maps are
buffer-local and set when such a buffer opens, so they never leak into your
notes.

A right-hand side is an action name, a Lua function, or
`{ action_or_function, mode = …, desc = … }` when you want modes other than
the action's own. Mask actions default to `{ "n", "i" }` and the rest to
`"n"`. An unknown action name, or one used in the wrong scope, is a setup
error naming the offending key rather than a key that quietly does nothing.

Add maps after `setup()` with
`require("mdresearch").keymaps({ results = { ["gO"] = "results.tab" } })`.

### Actions

`:MdResearchActions` prints the registry with scopes and descriptions.

| scope | actions |
|---|---|
| `global` | `open` `resume` `last` `close` `workspace` `workspace.next` `workspace.prev` `reload` `health` |
| `mask` | `mask.submit` `mask.cancel` `mask.toggle_mode` `mask.clear_field` `mask.clear_all` `mask.next_field` `mask.prev_field` |
| `results` | `results.open` `results.split` `results.vsplit` `results.tab` `results.preview` `results.yank_link` `results.refine` `results.close` |

## Lua API

`require("mdresearch")` is the public surface. Every function reports its
reason and returns `false` when it cannot do the job, rather than raising, so
it is safe to call when nothing is open.

```lua
local md = require("mdresearch")

md.setup(opts)
md.open({ prefill = { tags = "linux server" }, modes = { tags = "all" } })
md.resume()
md.search({ tags = "linux server" }, { tags = "all" })
md.last()
md.close()

md.workspace("notes")          -- no name opens vim.ui.select
md.workspace_next()            -- and md.workspace_prev()
md.workspaces()
md.current_workspace()

md.mask.submit()
md.mask.toggle_mode({ field = "tags" })
md.mask.clear_field({ all = true })
md.mask.set_field("tags", "linux server")
md.mask.focus_field("next")
md.mask.get()                  -- returns raw, modes without submitting
md.mask.is_open()

md.results.open("vsplit", { index = 3 })
md.results.preview({ index = 3 })
md.results.yank_link()                    -- copy a link to a register
md.results.yank_link({ index = 3, format = "path", register = "+" })
md.results.link({ index = 3 })            -- the link text, without yanking
md.results.refine()
md.results.rows()              -- the rows behind the table, in display order
md.results.row(3)
md.results.close()
md.results.is_open()

md.reload()
md.health()
md.status()                    -- { workspace, raw, modes, backend, results }
md.config()                    -- the normalised configuration
md.keymaps({ global = {} })
md.VERSION
```

`md.search` is asynchronous and takes
`opts = { workspace, backend, prefilter, on_done }`; `on_done(rows)` runs
after the table is filled. The free-text field is keyed `"__fulltext"`, which
is `require("mdresearch.ui.mask").FULLTEXT`, and `text=` in
`:MdResearchSearch` is an alias for it.

A row is `{ path = string, rel = string, fields = table }`, where `fields`
holds the parsed frontmatter values keyed by field.

`yank_link` and `link` take `{ buf, index, format, label, ext, register }`,
and fall back to `ui.results.link` for anything you leave out. `link`
returns the text plus an error string, `yank_link` returns a boolean and
reports its own failure. `require("mdresearch.link").render(row, opts)` is
the same formatting as a pure function, for a row you got some other way.

## Events

Two `User` events, both carrying `data`:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern  = "MdResearchResults",              -- { count, workspace }
  callback = function(ev) print(ev.data.count .. " hits") end,
})

vim.api.nvim_create_autocmd("User", {
  pattern  = "MdResearchWorkspaceChanged",     -- { workspace, root }
  callback = function(ev) print("now in " .. ev.data.workspace) end,
})
```

`on_open = function(path, row)` in `setup()` runs before a row's file is
loaded.

## Backends

`backend = "auto"`, the default, uses mdrq when a compatible binary is on
`$PATH`, at `mdrq.cmd`, or in `rust/mdrq/target/release/` inside the plugin.
Otherwise it uses the Lua backend, which shells out to ripgrep to narrow the
candidates and falls back to a directory walk when ripgrep is missing.

Build mdrq with:

```sh
./scripts/build-mdrq.sh     # or: make build
```

The script needs `cargo` and prints where the plugin will pick the binary up.
Nothing else to configure. `:checkhealth mdresearch` confirms which backend
won and why.

Both backends return the same rows for the same query, and
`tests/mdresearch/parity_spec.lua` runs them over the same fixture vault and
requires the results to be identical. The Lua one is the reference
implementation. Force either with `backend = "lua"` or `backend = "mdrq"`.

## Troubleshooting

Start with `:checkhealth mdresearch`. It reports the workspaces and whether
their roots exist, the ripgrep version, the chosen backend and the reason,
the commands it installed, how many mappings you declared, and the cache
size.

- **No hits you expected.** The summary line of the table shows the query as
  parsed, which is the fastest way to see that a field was read as OR when
  you wanted AND. Reach for `all:`.
- **A field is ignored.** Only keys declared in that workspace's `fields`
  are searched. Frontmatter keys you never declared are not.
- **Stale results after editing a note.** Writing a `*.md` file invalidates
  that file's cache entry on its own. `:MdResearchReload` clears everything
  and re-detects the backend.
- **`setup()` errors.** The message names the offending key. Unknown keys are
  rejected on purpose.

`:help mdresearch` documents the same surface in more detail, with tags for
every command, action and API function.

## Layout

```
lua/mdresearch/   the plugin          doc/ARCHITECTURE.md    config, autocmds, API
rust/mdrq/        optional backend    doc/TOOLING.md         why rg + mdrq, not fzf
tests/            make test-lua       doc/STRUCTURE.md       the lua/rust split
plugin/           the commands        doc/IMPLEMENTATION.md  build order
```

```sh
make test     # 245 Lua specs and 26 Rust tests
make build    # the optional Rust backend
make fmt      # cargo fmt, plus stylua when installed
```

The Lua specs run in headless Neovim through `tests/run.lua` and need no
plugin manager or test framework.
