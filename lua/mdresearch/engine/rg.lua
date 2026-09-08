--- ripgrep helpers plus a dependency-free fallback walk.
---
--- Two questions only: "which files are in this workspace" and "which of them
--- contain this literal". Everything else is decided in Lua, so ripgrep is an
--- accelerator here, never the semantics.
local config = require("mdresearch.config")
local util = require("mdresearch.util")

local M = {}

local checked, ok_cache = false, false

function M.available()
  if not checked then
    checked = true
    ok_cache = vim.fn.executable(config.get().rg.cmd) == 1
  end
  return ok_cache
end

function M.reset()
  checked = false
end

local function base_args(ws)
  local cfg = config.get()
  local args = { cfg.rg.cmd }
  vim.list_extend(args, cfg.rg.args or {})
  args[#args + 1] = "--glob=" .. ws.glob
  for _, ex in ipairs(ws.exclude or {}) do
    args[#args + 1] = "--glob=!" .. ex
  end
  if ws.hidden then
    args[#args + 1] = "--hidden"
  end
  if ws.follow then
    args[#args + 1] = "--follow"
  end
  return args
end

---@param args string[]
---@param cb fun(paths: string[]|nil, err: string|nil)
--- Ripgrep matches `--glob` against the path *relative to its working
--- directory*, so every invocation runs with cwd = ws.root and searches ".".
--- That makes the workspace globs mean what the config says they mean, and it
--- makes the emitted paths root-relative, which is what the rows want anyway.
---@param ws table
---@param args string[]
---@param cb fun(paths: string[]|nil, err: string|nil)
local function run(ws, args, cb)
  return vim.system(args, { text = true, cwd = ws.root }, function(res)
    -- rg exits 1 when nothing matched, which is not an error for us.
    if res.code > 1 then
      cb(nil, util.trim(res.stderr or ("rg exited " .. res.code)))
      return
    end
    local paths = {}
    for line in (res.stdout or ""):gmatch("[^\n]+") do
      paths[#paths + 1] = util.join(ws.root, (line:gsub("^%./", "")))
    end
    cb(paths, nil)
  end)
end
M.run = run

---Every file of the workspace.
---@param ws table
---@param cb fun(paths: string[]|nil, err: string|nil)
function M.files(ws, cb)
  if not M.available() then
    vim.schedule(function()
      cb(M.walk(ws), nil)
    end)
    return nil
  end
  local args = base_args(ws)
  args[#args + 1] = "--files"
  args[#args + 1] = "."
  return run(ws, args, cb)
end

---Files of the workspace containing `literal`, case-insensitively.
---@param ws table
---@param literal string
---@param cb fun(paths: string[]|nil, err: string|nil)
function M.matching(ws, literal, cb)
  local args = base_args(ws)
  vim.list_extend(
    args,
    { "--files-with-matches", "--fixed-strings", "--ignore-case", "--no-messages", "--", literal, "." }
  )
  return run(ws, args, cb)
end

---Fallback enumeration when ripgrep is unavailable.
---@param ws table
---@return string[]
function M.walk(ws)
  local out = {}
  local pattern = util.glob_to_pattern(ws.glob)
  local excludes = {}
  for _, ex in ipairs(ws.exclude or {}) do
    excludes[#excludes + 1] = util.glob_to_pattern(ex)
  end

  local function visit(dir, rel)
    local handle = vim.uv.fs_scandir(dir)
    if not handle then
      return
    end
    while true do
      local name, kind = vim.uv.fs_scandir_next(handle)
      if not name then
        return
      end
      local child_rel = rel == "" and name or (rel .. "/" .. name)
      if not (name:sub(1, 1) == "." and not ws.hidden) then
        if kind == "directory" then
          visit(dir .. "/" .. name, child_rel)
        elseif kind == "file" or (kind == "link" and ws.follow) then
          local skip = false
          for _, ex in ipairs(excludes) do
            if child_rel:match(ex) then
              skip = true
              break
            end
          end
          if not skip and child_rel:match(pattern) then
            out[#out + 1] = dir .. "/" .. name
          end
        end
      end
    end
  end

  visit(ws.root, "")
  table.sort(out)
  return out
end

---Fallback content test when ripgrep is unavailable.
---@param path string
---@param literal string
---@return boolean
function M.file_contains(path, literal)
  local fd = io.open(path, "rb")
  if not fd then
    return false
  end
  local needle = literal:lower()
  local found = false
  local carry = ""
  while true do
    local chunk = fd:read(64 * 1024)
    if not chunk then
      break
    end
    local hay = (carry .. chunk):lower()
    if hay:find(needle, 1, true) then
      found = true
      break
    end
    carry = chunk:sub(-#needle)
  end
  fd:close()
  return found
end

return M
