--- Client for the Rust backend (`rust/mdrq`).
---
--- The whole exchange is one JSON request on stdin and JSON Lines on stdout;
--- see rust/mdrq/README.md for the schema. Rows come back with their field
--- values already extracted, so the table needs no second read.
local config = require("mdresearch.config")
local engine = require("mdresearch.engine")
local util = require("mdresearch.util")

local M = {}

---Empty lists must not be encoded, because `vim.json.encode({})` produces an
---object and serde would reject it. Absent keys fall back to serde defaults.
local function put_list(t, key, list)
  if list and #list > 0 then
    t[key] = list
  end
end

---@param ws table
---@param q table
---@return table
function M.request(ws, q)
  local cfg = config.get()
  local fields = {}
  for _, f in ipairs(ws.fields) do
    fields[#fields + 1] = { key = f.key, type = f.type, list = f.list }
  end
  local filters = {}
  for _, key in ipairs(q.order) do
    filters[#filters + 1] = q.fields[key]
  end

  local req = {
    protocol = engine.PROTOCOL,
    root = ws.root,
    glob = ws.glob,
    hidden = ws.hidden,
    follow = ws.follow,
    limit = cfg.limit,
    sort = { key = ws.sort.key, desc = ws.sort.desc },
  }
  put_list(req, "exclude", ws.exclude)
  put_list(req, "fields", fields)
  put_list(req, "filters", filters)
  if q.fulltext then
    req.fulltext = q.fulltext
  end
  return req
end

---@param ws table
---@param q table
---@param opts table|nil
---@param cb fun(rows: table[]|nil, err: string|nil, meta: table|nil)
function M.run(ws, q, opts, cb)
  local picked = engine.pick()
  local cmd = picked.cmd or engine.find_mdrq()
  if not cmd then
    cb(nil, "mdrq binary not found; run scripts/build-mdrq.sh")
    return nil
  end
  local payload = vim.json.encode(M.request(ws, q))

  return vim.system({ cmd, "--stdin" }, { text = true, stdin = payload }, function(res)
    if res.code ~= 0 then
      cb(nil, util.trim(res.stderr or ("mdrq exited " .. res.code)))
      return
    end
    local rows, meta = {}, { truncated = false }
    for line in (res.stdout or ""):gmatch("[^\n]+") do
      local ok, row = pcall(vim.json.decode, line)
      if ok and type(row) == "table" then
        if row.__meta then
          meta.truncated = row.truncated == true
          meta.scanned = row.scanned
        else
          row.fields = row.fields or {}
          rows[#rows + 1] = row
        end
      end
    end
    cb(rows, nil, meta)
  end)
end

return M
