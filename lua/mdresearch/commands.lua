--- The Ex commands. Every action the plugin has is reachable from command
--- mode; `mdresearch.actions` holds the same set under stable names for
--- mapping, and `require("mdresearch")` is the Lua API behind both.
---
--- The table `M.specs` is the single source of truth: `setup()` creates the
--- commands from it, `plugin/mdresearch.lua` installs them at startup, and
--- `:MdResearchActions` prints it.
local M = {}

---@param args string
---@return string[]
local function words(args)
  local out = {}
  for w in args:gmatch("%S+") do
    out[#out + 1] = w
  end
  return out
end

local function unquote(s)
  local q = s:sub(1, 1)
  if (q == '"' or q == "'") and s:sub(-1) == q and #s > 1 then
    return s:sub(2, -2)
  end
  return s
end

---Parse `:MdResearchSearch tags="linux server" date=>=2025-01 text=docker`
---into the same shape the mask produces. `all:`/`any:` prefixes work inside
---the quoted value, exactly as in the mask.
---@param args string
---@return table raw, table modes
function M.parse_args(args)
  local lexer = require("mdresearch.query.lexer")
  local raw, modes = {}, {}
  for _, tok in ipairs(lexer.tokens(args)) do
    local key, value = tok.text:match("^([%w_%-%.]+)=(.*)$")
    if key then
      if key == "text" or key == "fulltext" then
        key = require("mdresearch.ui.mask").FULLTEXT
      end
      local rest, mode = require("mdresearch.query.parser").split_mode(value)
      raw[key] = rest
      if mode then
        modes[key] = mode
      end
    end
  end
  return raw, modes
end

---------------------------------------------------------------- completion --

local function prefixed(lead, candidates)
  local out = {}
  for _, c in ipairs(candidates) do
    if c:find(lead, 1, true) == 1 then
      out[#out + 1] = c
    end
  end
  table.sort(out)
  return out
end

---Field keys of the current workspace, plus `text` for the free-text row.
---@return string[]
local function field_keys()
  local ok, keys = pcall(function()
    local out = {}
    for _, f in ipairs(require("mdresearch.workspace").current().fields) do
      out[#out + 1] = f.key
    end
    out[#out + 1] = "text"
    return out
  end)
  return ok and keys or {}
end

local function complete_fields(lead)
  return prefixed(lead, field_keys())
end

local function complete_workspaces(lead)
  local ok, names = pcall(function()
    local out = {}
    for _, w in ipairs(require("mdresearch.workspace").list()) do
      out[#out + 1] = w.name
    end
    return out
  end)
  return prefixed(lead, ok and names or {})
end

local function complete_query(lead)
  if lead:find("=") then
    return {}
  end
  local out = {}
  for _, k in ipairs(field_keys()) do
    out[#out + 1] = k .. "="
  end
  return prefixed(lead, out)
end

local function complete_targets(lead)
  local out = { "next", "prev", "first", "last" }
  vim.list_extend(out, field_keys())
  return prefixed(lead, out)
end

local function complete_how(lead)
  return prefixed(lead, { "edit", "split", "vsplit", "tabedit" })
end

------------------------------------------------------------------- commands --

local function md()
  return require("mdresearch")
end

---@return integer|nil
local function count_of(o)
  if o.count and o.count > 0 then
    return o.count
  end
  return nil
end

--- One entry per command: `name`, the `nvim_create_user_command` options, and
--- `run`. `desc` doubles as the documentation blurb.
---@type { name: string, desc: string, opts: table, run: fun(o: table) }[]
M.specs = {
  {
    name = "MdResearch",
    desc = "open the search mask",
    opts = { nargs = 0 },
    run = function()
      md().open()
    end,
  },
  {
    name = "MdResearchSearch",
    desc = 'search without the mask: tags="linux server" date=>=2025-01 text=docker',
    opts = { nargs = "*", complete = complete_query },
    run = function(o)
      local raw, modes = M.parse_args(o.args)
      md().search(raw, modes)
    end,
  },
  {
    name = "MdResearchResume",
    desc = "reopen the mask filled with the last query",
    opts = { nargs = 0 },
    run = function()
      md().resume()
    end,
  },
  {
    name = "MdResearchResults",
    desc = "reopen the last result table",
    opts = { nargs = 0 },
    run = function()
      md().last()
    end,
  },
  {
    name = "MdResearchClose",
    desc = "close the mask, or the result table",
    opts = { nargs = 0 },
    run = function()
      md().close()
    end,
  },
  {
    name = "MdResearchWorkspace",
    desc = "switch workspace, or pick one when no name is given",
    opts = { nargs = "?", complete = complete_workspaces },
    run = function(o)
      md().workspace(o.args)
    end,
  },
  {
    name = "MdResearchWorkspaceNext",
    desc = "switch to the next workspace",
    opts = { nargs = 0 },
    run = function()
      md().workspace_next()
    end,
  },
  {
    name = "MdResearchWorkspacePrev",
    desc = "switch to the previous workspace",
    opts = { nargs = 0 },
    run = function()
      md().workspace_prev()
    end,
  },

  -- the mask ---------------------------------------------------------------
  {
    name = "MdResearchSubmit",
    desc = "run the search the mask describes",
    opts = { nargs = 0 },
    run = function()
      md().mask.submit()
    end,
  },
  {
    name = "MdResearchToggleMode",
    desc = "flip any/all on [field], or on the field under the cursor",
    opts = { nargs = "?", complete = complete_fields },
    run = function(o)
      md().mask.toggle_mode({ field = o.args ~= "" and o.args or nil })
    end,
  },
  {
    name = "MdResearchClearField",
    desc = "empty [field], the field under the cursor, or with ! every field",
    opts = { nargs = "?", bang = true, complete = complete_fields },
    run = function(o)
      md().mask.clear_field({ field = o.args ~= "" and o.args or nil, all = o.bang })
    end,
  },
  {
    name = "MdResearchSetField",
    desc = "fill a mask field: :MdResearchSetField tags=linux server",
    opts = { nargs = "+", complete = complete_query },
    run = function(o)
      local field, value = o.args:match("^([^=]+)=(.*)$")
      if not field then
        require("mdresearch.util").err("usage: :MdResearchSetField <field>=<value>")
        return
      end
      md().mask.set_field(vim.trim(field), unquote(vim.trim(value)))
    end,
  },
  {
    name = "MdResearchField",
    desc = "put the cursor on a mask field: next|prev|first|last|<field>|<n>",
    opts = { nargs = 1, complete = complete_targets },
    run = function(o)
      md().mask.focus_field(o.args)
    end,
  },

  -- the result table -------------------------------------------------------
  {
    name = "MdResearchOpen",
    desc = "load a row's file; [how] is edit|split|vsplit|tabedit, {count} names the row",
    opts = { nargs = "?", count = true, complete = complete_how },
    run = function(o)
      md().results.open(o.args ~= "" and o.args or "edit", { index = count_of(o) })
    end,
  },
  {
    name = "MdResearchPreview",
    desc = "preview a row's file; {count} names the row",
    opts = { nargs = 0, count = true },
    run = function(o)
      md().results.preview({ index = count_of(o) })
    end,
  },
  {
    name = "MdResearchRefine",
    desc = "reopen the mask with the query the table came from",
    opts = { nargs = 0 },
    run = function()
      md().results.refine()
    end,
  },

  -- housekeeping -----------------------------------------------------------
  {
    name = "MdResearchReload",
    desc = "drop the frontmatter cache and re-detect the backend",
    opts = { nargs = 0 },
    run = function()
      md().reload()
    end,
  },
  {
    name = "MdResearchHealth",
    desc = "run the health check",
    opts = { nargs = 0 },
    run = function()
      md().health()
    end,
  },
  {
    name = "MdResearchActions",
    desc = "list the action names you can map",
    opts = { nargs = 0 },
    run = function()
      local actions = require("mdresearch.actions")
      local lines = {}
      for _, a in ipairs(actions.list) do
        lines[#lines + 1] = string.format("%-22s %-8s %s", a.name, a.scope, a.desc)
      end
      require("mdresearch.util").notify("actions\n" .. table.concat(lines, "\n"))
    end,
  },
}

---@return string[]
function M.names()
  local out = {}
  for _, s in ipairs(M.specs) do
    out[#out + 1] = s.name
  end
  return out
end

--- A config error or a missing `setup()` reaches the user as a message, not
--- as a stack trace in the middle of command mode.
local function guarded(spec)
  return function(o)
    local ok, err = pcall(spec.run, o)
    if not ok then
      local msg = tostring(err):gsub("^.-:%d+:%s*", ""):gsub("^mdresearch:%s*", "")
      require("mdresearch.util").err(msg)
    end
  end
end

---Create every command. Idempotent, so calling it again is harmless.
function M.setup()
  for _, spec in ipairs(M.specs) do
    local opts = vim.tbl_extend("force", spec.opts, { desc = "mdresearch: " .. spec.desc })
    vim.api.nvim_create_user_command(spec.name, guarded(spec), opts)
  end
end

return M
