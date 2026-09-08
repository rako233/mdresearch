local config = require("mdresearch.config")
local state = require("mdresearch.state")
local util = require("mdresearch.util")

local M = {}

---@return table[]
function M.list()
  return config.get().workspaces
end

---@param name string
---@return table|nil
function M.get(name)
  for _, w in ipairs(M.list()) do
    if w.name == name then
      return w
    end
  end
  return nil
end

---@return table
function M.current()
  local cfg = config.get()
  return M.get(state.workspace) or M.get(cfg.default_workspace) or cfg.workspaces[1]
end

---Fire the public User event so users can hook workspace changes.
local function announce(ws)
  vim.api.nvim_exec_autocmds("User", {
    pattern = "MdResearchWorkspaceChanged",
    data = { workspace = ws.name, root = ws.root },
  })
end

---@param name string
---@return boolean ok
function M.switch(name)
  local ws = M.get(name)
  if not ws then
    util.err(string.format("no workspace named %q", tostring(name)))
    return false
  end
  if state.workspace ~= ws.name then
    state.workspace = ws.name
    state.reset()
    announce(ws)
  end
  util.notify("workspace: " .. ws.name .. "  (" .. ws.root .. ")")
  return true
end

---@param delta integer
function M.cycle(delta)
  local list = M.list()
  local cur = M.current()
  local idx = 1
  for i, w in ipairs(list) do
    if w.name == cur.name then
      idx = i
      break
    end
  end
  local nxt = ((idx - 1 + delta) % #list) + 1
  return M.switch(list[nxt].name)
end

function M.pick()
  local list = M.list()
  vim.ui.select(list, {
    prompt = "mdresearch workspace",
    format_item = function(w)
      return string.format("%-16s %s", w.name, w.root)
    end,
  }, function(choice)
    if choice then
      M.switch(choice.name)
    end
  end)
end

---Innermost workspace whose root contains `path`.
---@param path string|nil
---@return table|nil
function M.detect(path)
  path = util.expand(path or vim.fn.getcwd())
  local best
  for _, w in ipairs(M.list()) do
    if path == w.root or path:sub(1, #w.root + 1) == w.root .. "/" then
      if not best or #w.root > #best.root then
        best = w
      end
    end
  end
  return best
end

---@param ws table
---@param key string
function M.field(ws, key)
  return ws.by_key[key]
end

return M
