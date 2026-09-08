--- mdresearch: search Markdown files by frontmatter, get a table you can load
--- files from.
---
--- This module is the public Lua API. Everything the plugin can do is a
--- function here, an Ex command in `mdresearch.commands`, or an action name in
--- `mdresearch.actions` — no key is mapped unless you map it.
---
--- See doc/mdresearch.txt (`:help mdresearch-api`) for the documented surface
--- and doc/ARCHITECTURE.md for the layering.
local M = {}

M.VERSION = "0.2.0"

local function util()
  return require("mdresearch.util")
end

---Report a failed action the way an interactive caller wants it: a message,
---and `false` for scripts that check.
---@param ok boolean|nil
---@param err string|nil
---@return boolean
local function report(ok, err)
  if not ok and err then
    util().err(err)
  end
  return ok == true
end

---@param opts table|nil
---@return table self
function M.setup(opts)
  local config = require("mdresearch.config")
  config.setup(opts)

  require("mdresearch.ui.highlight").setup()
  require("mdresearch.autocmds").setup()
  require("mdresearch.commands").setup()
  require("mdresearch.keymaps").global()

  local state = require("mdresearch.state")
  state.restore()
  if not require("mdresearch.workspace").get(state.workspace) then
    state.workspace = config.options.default_workspace
  end
  return M
end

------------------------------------------------------------------ searching --

---Open the search mask for a workspace.
---@param opts { prefill?: table<string,string>, modes?: table<string,string>, workspace?: string }|nil
---@return boolean ok
function M.open(opts)
  opts = opts or {}
  local workspace = require("mdresearch.workspace")
  local ws = opts.workspace and workspace.get(opts.workspace) or workspace.current()
  if not ws then
    return report(false, "no such workspace: " .. tostring(opts.workspace))
  end
  local state = require("mdresearch.state")
  require("mdresearch.ui.mask").open(ws, opts.prefill or {}, opts.modes or {}, function(raw, modes)
    state.raw, state.modes = raw, modes
    M.search(raw, modes, { workspace = ws.name })
  end)
  return true
end

---Reopen the mask filled with the last query.
---@param opts { workspace?: string }|nil
---@return boolean ok
function M.resume(opts)
  local state = require("mdresearch.state")
  return M.open({
    prefill = state.raw,
    modes = state.modes,
    workspace = (opts or {}).workspace,
  })
end

---Run a search and show the result table.
---@param raw table<string,string>
---@param modes table<string,string>|nil
---@param opts { workspace?: string, backend?: string, prefilter?: boolean, on_done?: fun(rows: table[]) }|nil
---@return boolean ok  false when the query or workspace was rejected
function M.search(raw, modes, opts)
  opts = opts or {}
  local workspace = require("mdresearch.workspace")
  local ws = opts.workspace and workspace.get(opts.workspace) or workspace.current()
  if not ws then
    return report(false, "no such workspace: " .. tostring(opts.workspace))
  end

  local query = require("mdresearch.query")
  local q, err = query.parse(ws, raw, modes)
  if not q then
    return report(false, err)
  end

  local state = require("mdresearch.state")
  state.query, state.raw, state.modes = q, raw, modes

  local engine = require("mdresearch.engine")
  engine.cancel()
  engine.run(ws, q, opts, function(rows, e, meta)
    if e then
      report(false, e)
      return
    end
    if #rows == 0 then
      util().notify("no matches for " .. query.describe(q))
    end
    require("mdresearch.ui.results").open(ws, q, rows, meta)
    if opts.on_done then
      opts.on_done(rows)
    end
  end)
  return true
end

---Reopen the last result table.
---@return boolean ok
function M.last()
  if require("mdresearch.ui.results").reopen() then
    return true
  end
  return report(false, "no results yet")
end

---Close whichever mdresearch window is open — the mask first, then the table.
---@return boolean ok
function M.close()
  local mask = require("mdresearch.ui.mask")
  if mask.is_open() then
    return report(mask.close())
  end
  local results = require("mdresearch.ui.results")
  if results.is_open() then
    return report(results.close())
  end
  return report(false, "nothing to close")
end

----------------------------------------------------------------- workspaces --

---Switch workspace, or pick one interactively when `name` is nil or empty.
---@param name string|nil
---@return boolean ok
function M.workspace(name)
  local workspace = require("mdresearch.workspace")
  if name and name ~= "" then
    return workspace.switch(name)
  end
  workspace.pick()
  return true
end

---@return boolean ok
function M.workspace_next()
  return require("mdresearch.workspace").cycle(1)
end

---@return boolean ok
function M.workspace_prev()
  return require("mdresearch.workspace").cycle(-1)
end

---Every configured workspace, normalised.
---@return table[]
function M.workspaces()
  return require("mdresearch.workspace").list()
end

---@return table
function M.current_workspace()
  return require("mdresearch.workspace").current()
end

----------------------------------------------------------------- the mask ---

--- Actions on the open search mask. All of them find the mask themselves, so
--- they work from any window; `field` names a field instead of using the
--- cursor line.
M.mask = {}

---@param opts { buf?: integer }|nil
---@return boolean ok
function M.mask.submit(opts)
  return report(require("mdresearch.ui.mask").submit(opts))
end

---@param opts { buf?: integer }|nil
---@return boolean ok
function M.mask.cancel(opts)
  return report(require("mdresearch.ui.mask").close(opts))
end

---@param opts { buf?: integer, field?: string|integer }|nil
---@return boolean ok
function M.mask.toggle_mode(opts)
  return report(require("mdresearch.ui.mask").toggle_mode(opts))
end

---@param opts { buf?: integer, field?: string|integer, all?: boolean }|nil
---@return boolean ok
function M.mask.clear_field(opts)
  return report(require("mdresearch.ui.mask").clear_field(opts))
end

---@param field string|integer  field key, label, `text`, or a 1-based index
---@param value string
---@param opts { buf?: integer }|nil
---@return boolean ok
function M.mask.set_field(field, value, opts)
  return report(require("mdresearch.ui.mask").set_field(field, value, opts))
end

---@param target string|integer|nil  "next"|"prev"|"first"|"last"|index|field key
---@param opts { buf?: integer }|nil
---@return boolean ok
function M.mask.focus_field(target, opts)
  return report(require("mdresearch.ui.mask").focus_field(target, opts))
end

---The mask's current input, without submitting it.
---@param opts { buf?: integer }|nil
---@return table|nil raw, table|nil modes
function M.mask.get(opts)
  return require("mdresearch.ui.mask").get(opts)
end

---@param opts { buf?: integer }|nil
---@return boolean
function M.mask.is_open(opts)
  return require("mdresearch.ui.mask").is_open((opts or {}).buf)
end

-------------------------------------------------------------- the results ---

--- Actions on the result table. `index` is a 1-based row number; without it
--- they use the row under the cursor.
M.results = {}

---Load a row's file.
---@param how "edit"|"split"|"vsplit"|"tabedit"|nil
---@param opts { buf?: integer, index?: integer }|nil
---@return boolean ok
function M.results.open(how, opts)
  return report(require("mdresearch.ui.results").open_row(how, opts))
end

---@param opts { buf?: integer, index?: integer }|nil
---@return boolean ok
function M.results.preview(opts)
  return report(require("mdresearch.ui.results").preview_row(opts))
end

---Reopen the mask with the query this table came from.
---@param opts { buf?: integer }|nil
---@return boolean ok
function M.results.refine(opts)
  local _, view = require("mdresearch.ui.results").find((opts or {}).buf)
  return M.resume({ workspace = view and view.ws.name or nil })
end

---@param opts { buf?: integer }|nil
---@return boolean ok
function M.results.close(opts)
  return report(require("mdresearch.ui.results").close(opts))
end

---The rows behind the table, in display order.
---@param opts { buf?: integer }|nil
---@return table[]
function M.results.rows(opts)
  return require("mdresearch.ui.results").rows((opts or {}).buf)
end

---@param index integer|nil
---@param opts { buf?: integer }|nil
---@return table|nil row
function M.results.row(index, opts)
  return (require("mdresearch.ui.results").row(index, (opts or {}).buf))
end

---@param opts { buf?: integer }|nil
---@return boolean
function M.results.is_open(opts)
  return require("mdresearch.ui.results").is_open((opts or {}).buf)
end

--------------------------------------------------------------- housekeeping --

---Drop the frontmatter cache and re-detect the backend.
function M.reload()
  require("mdresearch.engine.frontmatter").invalidate()
  require("mdresearch.engine").reset()
  util().notify("caches cleared, backend re-detected")
end

---`:checkhealth mdresearch` entry point.
function M.health()
  require("mdresearch.health").check()
end

---A snapshot of what the plugin currently holds.
---@return { workspace: string|nil, raw: table|nil, modes: table|nil, backend: string|nil, results: integer }
function M.status()
  local state = require("mdresearch.state")
  return {
    workspace = state.workspace,
    raw = state.raw and vim.deepcopy(state.raw) or nil,
    modes = state.modes and vim.deepcopy(state.modes) or nil,
    backend = state.backend,
    results = state.rows and #state.rows or 0,
  }
end

---The normalised configuration.
---@return table
function M.config()
  return require("mdresearch.config").get()
end

---Apply a keymap table on top of the configured ones.
---@param spec { global?: table, mask?: table, results?: table }
function M.keymaps(spec)
  require("mdresearch.keymaps").apply(spec)
end

return M
