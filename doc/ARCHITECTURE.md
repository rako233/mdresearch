# mdresearch — Architecture

> Task 1 deliverable: configuration structure, autocmds, Lua functions.

## 1. Purpose

`mdresearch` searches Markdown files by their YAML frontmatter (including
multi-line tag lists) and by full text, and renders the hits as an aligned
table in a scratch buffer. A command (or a key you mapped yourself) on a
table row loads that file — the plugin ships no keymap of its own.

## 2. Layers

```
                 ┌──────────────────────────────────────────┐
  user  ──────▶  │  ui.mask      search mask buffer          │
                 │  ui.results   result table buffer         │
                 └───────────────┬──────────────────────────┘
                                 │ Query (plain Lua table)
                 ┌───────────────▼──────────────────────────┐
                 │  query.*   lexer → parser → predicate     │
                 │            (typed terms, any/all, ranges) │
                 └───────────────┬──────────────────────────┘
                                 │ normalised Query
                 ┌───────────────▼──────────────────────────┐
                 │  engine.init   backend selection          │
                 │   ├─ engine.mdrq   Rust worker (JSONL)    │
                 │   └─ engine.lua    rg prefilter + Lua     │
                 │        ├─ engine.rg          candidates   │
                 │        └─ engine.frontmatter YAML subset  │
                 └───────────────┬──────────────────────────┘
                                 │ Row[] { path, rel, fields }
                 ┌───────────────▼──────────────────────────┐
                 │  ui.table   column layout + rendering     │
                 └──────────────────────────────────────────┘

  workspace.*  supplies root, field schema and columns to every layer.
  state.*      holds current workspace, last query, last result set.
```

The **Query** is the only contract between the UI and the engines, and it is
plain data. Both engines are required to return the same rows for the same
query; the Lua engine is the reference implementation.

## 3. Configuration structure

`require("mdresearch").setup(opts)`. Everything is optional except
`workspaces`. Unknown keys are rejected with a readable error so typos do not
silently disable a feature.

```lua
require("mdresearch").setup({
  ---------------------------------------------------------------- workspaces
  workspaces = {
    {
      name = "notes",                 -- unique id, used by :MdResearchWorkspace
      root = "~/notes",               -- the Markdown directory
      glob = "**/*.md",               -- default "**/*.md"
      exclude = { "archive/**" },     -- glob list, default {}
      follow = false,                 -- follow symlinks
      hidden = false,                 -- descend into dot-directories

      -- The standard tags of this workspace. Order = order in the search mask.
      fields = {
        { key = "title",  type = "text",     label = "Title"  },
        { key = "tags",   type = "text",     label = "Tags",
          list = true, mode = "all" },       -- default per-field any/all
        { key = "status", type = "text"      },
        { key = "prio",   type = "int"       },
        { key = "date",   type = "date"      },
        { key = "updated",type = "datetime"  },
      },

      -- Result table layout. Defaults to every field, "title" first.
      columns = {
        { key = "title", width = 40 },       -- width = max width, nil = auto
        { key = "tags",  width = 28 },
        { key = "date",  width = 10 },
        { key = "path",  width = nil },      -- "path" is a virtual column
      },
      sort = { key = "date", desc = true },  -- default { key="title" }
    },
  },
  default_workspace = "notes",        -- default: first entry

  ------------------------------------------------------------------- backend
  backend = "auto",                   -- "auto" | "mdrq" | "lua"
  mdrq = { cmd = nil, args = {} },    -- nil = search PATH, then rust/mdrq/target
  rg   = { cmd = "rg", args = {} },   -- used by the Lua backend for prefilter
  limit = 2000,                       -- hard cap on rows
  cache = true,                       -- memoise parsed frontmatter by mtime

  ------------------------------------------------------------------------ ui
  ui = {
    mask = {
      border = "rounded", width = 0.6, height = 0.5, title = " mdresearch ",
      hint = true,                    -- the hint line under the mask
      insert = true,                  -- open the mask in insert mode
    },
    results = {
      style = "split",                -- "split" | "float" | "tab"
      position = "botright", size = 0.45,
      show_header = true, show_count = true,
    },
    icons = { any = "any", all = "all" },
  },

  -------------------------------------------------------------------- keymaps
  -- Empty by default: the plugin maps nothing. Each scope is `lhs = action`,
  -- where an action is a name from §5.2, a function, or
  -- `{ action, mode = ..., desc = ... }`. Validated at setup time, so an
  -- unknown or mis-scoped action is an error, not a dead key.
  keymaps = {
    global = {                        -- set once by setup()
      -- ["<leader>ms"] = "open",
    },
    mask = {                          -- buffer-local to the search mask
      -- ["<CR>"] = "mask.submit",
    },
    results = {                       -- buffer-local to the result table
      -- ["<CR>"] = "results.open",
    },
  },

  --------------------------------------------------------------------- events
  on_open = nil,                      -- function(path, row) called before edit
})
```

### 3.1 Field types

| type       | frontmatter accepted                                     | query operators |
|------------|----------------------------------------------------------|-----------------|
| `text`     | scalar, `[a, b]`, block `- a`, `#a #b`                    | substring (default), `=exact`, `/regex/`, `!negate` |
| `int`      | `3`, `"3"`                                                | `3`, `>=3`, `<=3`, `>3`, `<3`, `1..5`, `!3` |
| `date`     | `2025-01-15`                                              | `2025-01-15`, `2025-01`, `2025`, `>=`, `<=`, `a..b` |
| `datetime` | `2025-01-15`, `2025-01-15 10:30`, `2025-01-15T10:30:00`, `2025-01-15-10:30` | same as `date` — **comparison is date-only** |

`list = true` marks a field whose frontmatter value is a sequence (the
multi-line tags case). It changes matching semantics, not parsing: every
scalar is treated as a one-element list, so a field works either way.

### 3.2 Field `mode` (the and/or condition)

Each field carries a `mode`, `"any"` (OR) or `"all"` (AND), seeded from the
workspace config and toggled per search with `:MdResearchToggleMode`. It can
also be written inline, `all: linux server`, which wins over the toggle.

| mode  | list field (`tags`)                        | scalar field (`title`)             |
|-------|--------------------------------------------|------------------------------------|
| `any` | at least one term matches at least one item| at least one term matches the value|
| `all` | every term matches at least one item       | every term matches the value       |

An empty field is dropped from the query entirely.

## 4. Autocmds

All in the augroup `MdResearch` (cleared on `setup`). Buffer-local groups use
`MdResearchBuf`.

| event | pattern | purpose |
|-------|---------|---------|
| `FileType` | `mdresearch-mask` | apply the user's `keymaps.mask`, if any |
| `FileType` | `mdresearch-results` | apply the user's `keymaps.results`, if any |
| `CursorMoved` | mask buffer | keep the cursor out of the label column |
| `CursorMoved` | results buffer | move the row highlight, update the preview |
| `BufWinLeave` / `BufWipeout` | our buffers | drop window/extmark state |
| `VimResized` | `*` | re-layout open floats |
| `BufWritePost` | `*.md` | invalidate that file in the frontmatter cache |
| `DirChanged` | `global` | re-detect the workspace from the new cwd |
| `VimLeavePre` | `*` | persist last workspace + query to `stdpath("state")` |
| `User` | `MdResearchWorkspaceChanged` | **emitted** by the plugin |
| `User` | `MdResearchResults` | **emitted** after a result buffer is filled |

The two `User` events are the plugin's public hook surface — they carry
`data = { workspace = ... }` and `data = { count = n, query = q }`.

## 5. Lua function surface

`require("mdresearch")` is the public API; `:help mdresearch-api` is its
reference. Everything the plugin can do is a function here, so a command and a
mapping are two thin callers of the same code. Every function reports its own
failure (a message plus `false`) instead of raising.

```lua
local md = require("mdresearch")

md.setup(opts)                     -- validate + install commands/autocmds/keymaps
md.open(opts)                      -- the search mask   { prefill, modes, workspace }
md.resume(opts)                    -- the mask, filled with the last query
md.search(raw, modes, opts)        -- search without the mask; async, on_done
md.last()                          -- reopen the last result table
md.close()                         -- close the mask, else the table
md.workspace(name)                 -- switch, or vim.ui.select when nil
md.workspace_next() / md.workspace_prev()
md.workspaces() / md.current_workspace()
md.reload()                        -- drop caches, re-detect the backend
md.health()                        -- :checkhealth mdresearch entry point
md.status()                        -- { workspace, raw, modes, backend, results }
md.config()                        -- the normalised configuration
md.keymaps(spec)                   -- add maps after setup()
md.VERSION
```

The mask and the table each get a table of actions. None of them needs the
cursor to be in the buffer: they resolve the buffer themselves (`opts.buf`
overrides), address a mask field by key/label/`text`/index, and a result row
by 1-based `index`.

```lua
md.mask.submit(opts)               -- opts = { buf }
md.mask.cancel(opts)
md.mask.toggle_mode(opts)          -- opts = { buf, field }
md.mask.clear_field(opts)          -- opts = { buf, field, all }
md.mask.set_field(field, value, opts)
md.mask.focus_field(target, opts)  -- next|prev|first|last|<field>|<n>
md.mask.get(opts)                  -- -> raw, modes, without submitting
md.mask.is_open(opts)

md.results.open(how, opts)         -- how = edit|split|vsplit|tabedit
md.results.preview(opts)           -- opts = { buf, index }
md.results.refine(opts)            -- the mask, with this table's query
md.results.close(opts)
md.results.rows(opts) / md.results.row(index, opts)
md.results.is_open(opts)           -- true while a window shows it
```

```lua
local ws = require("mdresearch.workspace")
ws.list()            -- Workspace[]
ws.current()         -- Workspace
ws.get(name)         -- Workspace|nil
ws.switch(name)      -- set current, fire User MdResearchWorkspaceChanged
ws.cycle(delta)      -- switch by offset (+1/-1)
ws.pick()            -- vim.ui.select over ws.list()
ws.detect(path)      -- innermost workspace containing path, or nil
ws.field(ws, key)    -- field spec lookup
```

```lua
local q = require("mdresearch.query")
q.new(workspace)                   -- empty Query for a workspace
q.parse(workspace, raw)            -- raw = { [key]=string, __fulltext=string }
q.is_empty(query)
q.match(query, fields)             -- evaluate a parsed row -> boolean
q.describe(query)                  -- one-line human summary for the statusline
```

```lua
local lex = require("mdresearch.query.lexer")
lex.split(str)                     -- "a \"b c\"" -> { "a", "b c" }

local parser = require("mdresearch.query.parser")
parser.field(fieldspec, str)       -- -> FieldFilter | nil, err

local pred = require("mdresearch.query.predicate")
pred.text(term, value); pred.int(term, value); pred.date(term, value)
```

```lua
local engine = require("mdresearch.engine")
engine.pick()                      -- resolve backend name for the config
engine.run(workspace, query, cb)   -- cb(rows|nil, err); always async
engine.cancel()                    -- abort the in-flight search
```

```lua
local fm = require("mdresearch.engine.frontmatter")
fm.read(path)                      -- -> table|nil  (cached by mtime)
fm.parse(text)                     -- -> table      (YAML subset)
fm.invalidate(path)
```

```lua
local mask = require("mdresearch.ui.mask")
mask.open(ws, prefill, modes, on_submit)  -- -> buf
mask.build(ws, prefill, modes)            -- pure: -> { lines, rows, label_width }
mask.read(lines, rows)                    -- pure: inverse of build
mask.find(buf)                            -- -> buf, mask  (the open mask)
mask.field_index(mask, field)             -- key | label | "text" | n -> row
mask.hint()                               -- the hint line, from your keymaps
-- submit/close/toggle_mode/clear_field/set_field/focus_field/get all
-- return `ok, err`; the API layer turns `err` into the message.

local results = require("mdresearch.ui.results")
results.open(ws, query, rows, meta)       -- -> buf (reuses the table buffer)
results.find(buf)                         -- -> buf, view
results.row(index, buf) / results.rows(buf)
results.open_row(how, opts) / results.preview_row(opts) / results.close(opts)
results.reopen()                          -- bring a hidden table back

local tbl = require("mdresearch.ui.table")   -- render(columns, rows) -> lines, spans
```

### 5.1 User commands

`commands.lua` holds one declarative spec per command — name, the
`nvim_create_user_command` options, the `run` function and the description
used for `:command` and the docs. `plugin/mdresearch.lua` installs them at
startup (before `setup()`, so `<Tab>` completes them), and `setup()` installs
them again, idempotently. Errors from a command body reach the user as a
message, not a stack trace.

| command | effect |
|---------|--------|
| `:MdResearch` | open the search mask |
| `:MdResearchSearch {args}` | headless query, e.g. `tags="linux server" date=>=2025-01` |
| `:MdResearchResume` | reopen the mask with the last query |
| `:MdResearchResults` | reopen the last result table |
| `:MdResearchClose` | close the mask, else the table |
| `:MdResearchWorkspace [name]` | switch workspace, or pick when no name |
| `:MdResearchWorkspaceNext` / `…Prev` | cycle workspaces |
| `:MdResearchSubmit` | run the search the mask describes |
| `:MdResearchToggleMode [field]` | flip any/all |
| `:MdResearchClearField[!] [field]` | empty one field, or all of them |
| `:MdResearchSetField {field}={value}` | fill a mask field |
| `:MdResearchField {target}` | cursor to `next\|prev\|first\|last\|<field>\|<n>` |
| `:[count]MdResearchOpen [how]` | load a row: `edit\|split\|vsplit\|tabedit` |
| `:[count]MdResearchPreview` | preview a row |
| `:MdResearchRefine` | the mask, with the table's query |
| `:MdResearchReload` | drop caches and re-detect the backend |
| `:MdResearchHealth` | the `:checkhealth` report |
| `:MdResearchActions` | list the mappable action names |

Completion is wired per command: field keys for the mask commands and for
`:MdResearchSearch` (`key=`), workspace names, `next\|prev\|first\|last` plus
field keys for `:MdResearchField`, and the four window verbs for
`:MdResearchOpen`.

### 5.2 Actions

`actions.lua` is a registry of named, argument-free operations —
`{ name, scope, desc, modes, fn }`. It exists so that a key mapping, a
command and `:MdResearchActions` all run the same function, and so that a
mis-typed mapping fails at `setup()`.

| scope | names |
|-------|-------|
| `global` | `open`, `resume`, `last`, `close`, `workspace`, `workspace.next`, `workspace.prev`, `reload`, `health` |
| `mask` | `mask.submit`, `mask.cancel`, `mask.toggle_mode`, `mask.clear_field`, `mask.clear_all`, `mask.next_field`, `mask.prev_field` |
| `results` | `results.open`, `results.split`, `results.vsplit`, `results.tab`, `results.preview`, `results.refine`, `results.close` |

`scope` decides where a name may be mapped and what `modes` it defaults to
(`mask` actions map in normal and insert mode, the rest in normal mode).
`keymaps.lua` resolves a config entry to `vim.keymap.set` arguments and is the
only place that calls it.

## 6. Data shapes

```lua
---@class Row      { path:string, rel:string, fields:table<string, any> }
---@class Term     { op:string, value?:any, from?:any, to?:any, negate?:boolean }
---@class FieldFilter { key:string, type:string, list:boolean, mode:"any"|"all", terms:Term[] }
---@class Query    { workspace:string, fields:table<string,FieldFilter>, fulltext:FieldFilter? }
```
