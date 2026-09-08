--- Keymaps you declare — the plugin ships none.
---
--- `keymaps` in `setup()` is `lhs -> action`, per scope:
---
---     keymaps = {
---       global  = { ["<leader>ms"] = "open" },
---       mask    = { ["<CR>"] = "mask.submit" },
---       results = { ["<CR>"] = "results.open", ["gq"] = function() ... end },
---     }
---
--- An action is a name from `mdresearch.actions`, a function, or
--- `{ action, mode = "n"|{...}, desc = "..." }`. `global` maps are set once at
--- `setup()`; `mask` and `results` maps are buffer-local, set when such a
--- buffer opens.
local M = {}

--- Extra specs added at runtime through `require("mdresearch").keymaps{...}`,
--- merged over the configured ones.
---@type table<string, table>
M.extra = { global = {}, mask = {}, results = {} }

M.SCOPES = { global = true, mask = true, results = true }

---Turn one `lhs -> action` entry into arguments for `vim.keymap.set`.
---@param scope string
---@param lhs string
---@param spec string|function|table
---@return string[]|nil modes, function|nil rhs, string|nil desc, string|nil err
function M.resolve(scope, lhs, spec)
  local actions = require("mdresearch.actions")
  local target, modes, desc = spec, nil, nil
  if type(spec) == "table" then
    target = spec[1] or spec.action
    modes = spec.mode or spec.modes
    desc = spec.desc
  end
  if type(modes) == "string" then
    modes = { modes }
  end

  if type(target) == "function" then
    return modes or { "n" }, target, desc or ("mdresearch: " .. lhs)
  end
  if type(target) ~= "string" then
    return nil, nil, nil, string.format("keymaps.%s[%q] must be an action name, a function, or a table", scope, lhs)
  end
  local action = actions.get(target)
  if not action then
    return nil,
      nil,
      nil,
      string.format(
        "keymaps.%s[%q]: unknown action %q (known: %s)",
        scope,
        lhs,
        target,
        table.concat(actions.names(), ", ")
      )
  end
  if action.scope ~= scope then
    return nil,
      nil,
      nil,
      string.format("keymaps.%s[%q]: action %q belongs to scope %q", scope, lhs, target, action.scope)
  end
  return modes or action.modes, action.fn, desc or ("mdresearch: " .. action.desc)
end

---@param scope "global"|"mask"|"results"
---@return table<string, any>
local function spec_for(scope)
  local cfg = require("mdresearch.config").get()
  return vim.tbl_extend("force", cfg.keymaps[scope] or {}, M.extra[scope] or {})
end

---@param scope "global"|"mask"|"results"
---@param buf integer|nil
local function set_scope(scope, buf)
  local util = require("mdresearch.util")
  local spec = spec_for(scope)
  for _, lhs in ipairs(util.keys(spec)) do
    local modes, rhs, desc, err = M.resolve(scope, lhs, spec[lhs])
    if err then
      util.err(err)
    else
      vim.keymap.set(modes, lhs, rhs, {
        buffer = buf,
        nowait = buf ~= nil,
        silent = true,
        desc = desc,
      })
    end
  end
end

---Set the configured global maps. Called by `setup()`.
function M.global()
  set_scope("global", nil)
end

---@param buf integer
function M.mask(buf)
  set_scope("mask", buf)
end

---@param buf integer
function M.results(buf)
  set_scope("results", buf)
end

---Add maps after `setup()`. Global ones take effect at once; `mask` and
---`results` ones apply to the next such buffer, and to an open one right away.
---@param spec { global?: table, mask?: table, results?: table }
function M.apply(spec)
  local util = require("mdresearch.util")
  for scope, maps in pairs(spec or {}) do
    if not M.SCOPES[scope] then
      util.err(string.format("keymaps: unknown scope %q (global|mask|results)", tostring(scope)))
    else
      M.extra[scope] = vim.tbl_extend("force", M.extra[scope] or {}, maps)
    end
  end
  if spec.global then
    set_scope("global", nil)
  end
  if spec.mask then
    local buf = select(1, require("mdresearch.ui.mask").find())
    if buf then
      set_scope("mask", buf)
    end
  end
  if spec.results then
    local buf = select(1, require("mdresearch.ui.results").find())
    if buf then
      set_scope("results", buf)
    end
  end
end

return M
