local config = require("mdresearch.config")
local state = require("mdresearch.state")
local util = require("mdresearch.util")

local M = {}

M.PROTOCOL = 1

local resolved = nil ---@type { name: string, reason: string, cmd: string|nil }|nil
local inflight = nil

---Where a locally built mdrq would live, relative to this file.
local function bundled_mdrq()
  local here = debug.getinfo(1, "S").source:sub(2)
  local root = vim.fn.fnamemodify(here, ":p:h:h:h:h")
  for _, profile in ipairs({ "release", "debug" }) do
    local p = vim.fs.joinpath(root, "rust", "mdrq", "target", profile, "mdrq")
    if vim.uv.fs_stat(p) then
      return p
    end
  end
  return nil
end

---@return string|nil path
function M.find_mdrq()
  local cfg = config.get()
  if cfg.mdrq.cmd then
    return vim.fn.executable(cfg.mdrq.cmd) == 1 and cfg.mdrq.cmd or nil
  end
  if vim.fn.executable("mdrq") == 1 then
    return "mdrq"
  end
  return bundled_mdrq()
end

---Decide which backend to use. Cached for the session; `reset()` clears it.
---@return { name: string, reason: string, cmd: string|nil }
function M.pick()
  if resolved then
    return resolved
  end
  local cfg = config.get()

  if cfg.backend == "lua" then
    resolved = { name = "lua", reason = "backend = \"lua\"" }
    return resolved
  end

  local cmd = M.find_mdrq()
  if cmd then
    local res = vim.system({ cmd, "--protocol" }, { text = true }):wait()
    local got = tonumber(util.trim(res.stdout or ""))
    if res.code == 0 and got == M.PROTOCOL then
      resolved = { name = "mdrq", reason = "mdrq protocol " .. got, cmd = cmd }
      return resolved
    end
    if cfg.backend == "mdrq" then
      error(string.format("mdresearch: %s speaks protocol %s, this plugin needs %d", cmd, tostring(got), M.PROTOCOL), 0)
    end
  end

  if cfg.backend == "mdrq" then
    error("mdresearch: backend = \"mdrq\" but no usable mdrq binary was found", 0)
  end

  resolved = { name = "lua", reason = cmd and "mdrq unusable" or "no mdrq binary found" }
  return resolved
end

function M.reset()
  resolved = nil
  require("mdresearch.engine.rg").reset()
end

function M.cancel()
  if inflight then
    pcall(function()
      inflight:kill(15)
    end)
    inflight = nil
  end
end

---Run a query. Always asynchronous; `cb` runs on the main loop.
---@param ws table
---@param q table
---@param opts table|nil  { backend = "lua"|"mdrq", prefilter = boolean }
---@param cb fun(rows: table[]|nil, err: string|nil, meta: table|nil)
function M.run(ws, q, opts, cb)
  opts = opts or {}
  local name = opts.backend or M.pick().name
  state.backend = name
  local impl = name == "mdrq" and require("mdresearch.engine.mdrq") or require("mdresearch.engine.lua")
  local wrapped = function(rows, err, meta)
    vim.schedule(function()
      cb(rows, err, meta)
    end)
  end
  local ok, res = pcall(impl.run, ws, q, opts, wrapped)
  if not ok then
    wrapped(nil, tostring(res))
    return
  end
  inflight = res
end

---Synchronous wrapper, for tests and scripted use.
---@return table[]|nil rows, string|nil err
function M.run_sync(ws, q, opts, timeout)
  local done, rows, err = false, nil, nil
  M.run(ws, q, opts, function(r, e)
    rows, err, done = r, e, true
  end)
  vim.wait(timeout or 15000, function()
    return done
  end, 10)
  if not done then
    return nil, "timed out"
  end
  return rows, err
end

return M
