local util = require("mdresearch.util")

local M = {}

M.FIELD_TYPES = { text = true, int = true, date = true, datetime = true }

M.defaults = {
  workspaces = {},
  default_workspace = nil,
  backend = "auto", -- "auto" | "mdrq" | "lua"
  mdrq = { cmd = nil, args = {} },
  rg = { cmd = "rg", args = {} },
  limit = 2000,
  cache = true,
  ui = {
    mask = {
      border = "rounded",
      width = 0.6,
      height = 0.5,
      title = " mdresearch ",
      hint = true, -- the "<CR> search …" line under the mask
      insert = true, -- start the mask in insert mode
    },
    results = {
      style = "split", -- "split" | "float" | "tab"
      position = "botright",
      size = 0.45,
      show_header = true,
      show_count = true,
      --- What `results.yank_link` puts in a register. The target is always
      --- the path relative to the workspace root.
      link = {
        format = "markdown", -- "markdown" | "wiki" | "path"
        label = "title", -- field key for the link text, or false for the file stem
        ext = true, -- keep the file extension in the target
        register = nil, -- default register; nil means the unnamed one
      },
    },
    icons = { any = "any", all = "all" },
  },
  --- No key is mapped unless you ask for it. Each scope is `lhs = action`,
  --- where an action is a name from `mdresearch.actions`, a function, or
  --- `{ action, mode = ..., desc = ... }`. See |mdresearch-mappings|.
  keymaps = {
    global = {},
    mask = {},
    results = {},
  },
  on_open = nil,
}

--- Every accepted top-level key. It cannot be derived from `defaults`,
--- because a key whose default is `nil` (`default_workspace`, `on_open`) has
--- no entry there.
M.OPTION_KEYS = {
  workspaces = true,
  default_workspace = true,
  backend = true,
  mdrq = true,
  rg = true,
  limit = true,
  cache = true,
  ui = true,
  keymaps = true,
  on_open = true,
}

---@type table
M.options = nil

local function fail(fmt, ...)
  error("mdresearch config: " .. string.format(fmt, ...), 0)
end

local function reject_unknown(given, allowed, where)
  for _, k in ipairs(util.keys(given)) do
    if allowed[k] == nil then
      fail("unknown key %q in %s (known: %s)", k, where, table.concat(util.keys(allowed), ", "))
    end
  end
end

local KEYMAP_SCOPES = { global = true, mask = true, results = true }
local FIELD_KEYS = { key = true, type = true, label = true, list = true, mode = true, width = true }
local COLUMN_KEYS = { key = true, width = true, label = true }
local WS_KEYS = {
  name = true,
  root = true,
  glob = true,
  exclude = true,
  follow = true,
  hidden = true,
  fields = true,
  columns = true,
  sort = true,
}

local function normalize_field(raw, wsname, idx)
  if type(raw) ~= "table" then
    fail("workspace %q field #%d must be a table", wsname, idx)
  end
  reject_unknown(raw, FIELD_KEYS, string.format("workspace %q field #%d", wsname, idx))
  local key = raw.key
  if type(key) ~= "string" or key == "" then
    fail("workspace %q field #%d needs a string `key`", wsname, idx)
  end
  local ftype = raw.type or "text"
  if not M.FIELD_TYPES[ftype] then
    fail("workspace %q field %q has unknown type %q (text|int|date|datetime)", wsname, key, tostring(ftype))
  end
  local mode = raw.mode or "any"
  if mode ~= "any" and mode ~= "all" then
    fail("workspace %q field %q: mode must be \"any\" or \"all\"", wsname, key)
  end
  return {
    key = key,
    type = ftype,
    label = raw.label or (key:sub(1, 1):upper() .. key:sub(2)),
    list = raw.list == true,
    mode = mode,
    width = raw.width,
  }
end

local function normalize_columns(raw, fields, wsname)
  local cols = {}
  if raw == nil then
    for _, f in ipairs(fields) do
      cols[#cols + 1] = { key = f.key, label = f.label, width = f.width }
    end
    cols[#cols + 1] = { key = "path", label = "Path" }
    return cols
  end
  if not util.is_list(raw) then
    fail("workspace %q: `columns` must be a list", wsname)
  end
  local by_key = {}
  for _, f in ipairs(fields) do
    by_key[f.key] = f
  end
  for i, c in ipairs(raw) do
    if type(c) == "string" then
      c = { key = c }
    end
    if type(c) ~= "table" then
      fail("workspace %q column #%d must be a string or a table", wsname, i)
    end
    reject_unknown(c, COLUMN_KEYS, string.format("workspace %q column #%d", wsname, i))
    if type(c.key) ~= "string" then
      fail("workspace %q column #%d needs a string `key`", wsname, i)
    end
    if c.key ~= "path" and c.key ~= "rel" and not by_key[c.key] then
      fail("workspace %q column %q is not a field of that workspace", wsname, c.key)
    end
    local f = by_key[c.key]
    cols[#cols + 1] = {
      key = c.key,
      label = c.label or (f and f.label) or (c.key:sub(1, 1):upper() .. c.key:sub(2)),
      width = c.width or (f and f.width),
    }
  end
  return cols
end

local function normalize_workspace(raw, idx)
  if type(raw) ~= "table" then
    fail("workspace #%d must be a table", idx)
  end
  reject_unknown(raw, WS_KEYS, string.format("workspace #%d", idx))
  local name = raw.name
  if type(name) ~= "string" or name == "" then
    fail("workspace #%d needs a string `name`", idx)
  end
  if type(raw.root) ~= "string" or raw.root == "" then
    fail("workspace %q needs a string `root`", name)
  end
  if raw.fields ~= nil and not util.is_list(raw.fields) then
    fail("workspace %q: `fields` must be a list", name)
  end

  local fields, by_key = {}, {}
  for i, f in ipairs(raw.fields or {}) do
    local nf = normalize_field(f, name, i)
    if by_key[nf.key] then
      fail("workspace %q declares field %q twice", name, nf.key)
    end
    fields[#fields + 1] = nf
    by_key[nf.key] = nf
  end

  local sort = raw.sort or { key = fields[1] and fields[1].key or "path" }
  if type(sort) ~= "table" or type(sort.key) ~= "string" then
    fail("workspace %q: `sort` must be { key = <string>, desc = <boolean> }", name)
  end
  if not by_key[sort.key] and sort.key ~= "path" and sort.key ~= "rel" then
    fail("workspace %q sorts by %q, which is not one of its fields", name, sort.key)
  end

  return {
    name = name,
    root = util.expand(raw.root),
    glob = raw.glob or "**/*.md",
    exclude = raw.exclude or {},
    follow = raw.follow == true,
    hidden = raw.hidden == true,
    fields = fields,
    by_key = by_key,
    columns = normalize_columns(raw.columns, fields, name),
    sort = { key = sort.key, desc = sort.desc == true },
  }
end

---Validate `keymaps`: known scopes, string left-hand sides, and actions that
---exist in the scope they are declared under. A typo there is a silent
---missing key otherwise, so it is a setup error.
---@param raw table
---@return table
local function normalize_keymaps(raw)
  if type(raw) ~= "table" then
    fail("`keymaps` must be a table of scopes (global|mask|results)")
  end
  reject_unknown(raw, KEYMAP_SCOPES, "keymaps")

  local keymaps = require("mdresearch.keymaps")
  local out = { global = {}, mask = {}, results = {} }
  for _, scope in ipairs(util.keys(KEYMAP_SCOPES)) do
    local maps = raw[scope]
    if maps ~= nil then
      if type(maps) ~= "table" or (util.is_list(maps) and next(maps) ~= nil) then
        fail("keymaps.%s must be a table of `lhs = action`", scope)
      end
      for lhs, spec in pairs(maps) do
        if type(lhs) ~= "string" or lhs == "" then
          fail("keymaps.%s: %s is not a left-hand side", scope, tostring(lhs))
        end
        local _, _, _, err = keymaps.resolve(scope, lhs, spec)
        if err then
          fail("%s", err)
        end
        out[scope][lhs] = spec
      end
    end
  end
  return out
end

---Validate and normalise user options.
---@param opts table|nil
---@return table
function M.normalize(opts)
  opts = opts or {}
  if type(opts) ~= "table" then
    fail("setup() expects a table")
  end
  reject_unknown(opts, M.OPTION_KEYS, "setup()")

  local cfg = util.deep_merge(M.defaults, opts)

  if not util.is_list(cfg.workspaces) or #cfg.workspaces == 0 then
    fail("at least one workspace is required")
  end
  if cfg.backend ~= "auto" and cfg.backend ~= "lua" and cfg.backend ~= "mdrq" then
    fail("backend must be \"auto\", \"lua\" or \"mdrq\" (got %q)", tostring(cfg.backend))
  end

  cfg.keymaps = normalize_keymaps(cfg.keymaps)

  local link_format = cfg.ui.results.link.format
  if not require("mdresearch.link").FORMATS[link_format] then
    fail("ui.results.link.format must be \"markdown\", \"wiki\" or \"path\" (got %q)", tostring(link_format))
  end

  local wss, seen = {}, {}
  for i, w in ipairs(cfg.workspaces) do
    local nw = normalize_workspace(w, i)
    if seen[nw.name] then
      fail("duplicate workspace name %q", nw.name)
    end
    seen[nw.name] = true
    wss[#wss + 1] = nw
  end
  cfg.workspaces = wss

  if cfg.default_workspace == nil then
    cfg.default_workspace = wss[1].name
  elseif not seen[cfg.default_workspace] then
    fail("default_workspace %q is not a declared workspace", tostring(cfg.default_workspace))
  end

  return cfg
end

function M.setup(opts)
  M.options = M.normalize(opts)
  return M.options
end

function M.get()
  if not M.options then
    error("mdresearch: setup() has not been called", 0)
  end
  return M.options
end

return M
