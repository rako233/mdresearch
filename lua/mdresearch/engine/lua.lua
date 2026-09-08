--- Reference backend: ripgrep narrows the candidates, Lua decides.
---
--- The narrowing is a strict superset filter — ripgrep is asked only for
--- literals that must appear *somewhere* in a matching file — so the answer
--- is identical with or without it. `opts.prefilter = false` proves that.
local config = require("mdresearch.config")
local fm = require("mdresearch.engine.frontmatter")
local query_mod = require("mdresearch.query")
local rg = require("mdresearch.engine.rg")
local util = require("mdresearch.util")

local M = {}

local function to_set(list)
  local set = {}
  for _, v in ipairs(list) do
    set[v] = true
  end
  return set
end

--------------------------------------------------------------------- sorting

local function sort_key(ws, row)
  local spec = ws.by_key[ws.sort.key]
  local v = row.fields[ws.sort.key]
  if type(v) == "table" then
    v = v[1]
  end
  if spec and (spec.type == "date" or spec.type == "datetime") then
    return require("mdresearch.query.parser").value_to_ymd(v) or -1
  end
  if spec and spec.type == "int" then
    return tonumber(v) or -math.huge
  end
  if v == nil then
    return ""
  end
  return tostring(v):lower()
end

local function sort_rows(ws, rows)
  local keys = {}
  for _, r in ipairs(rows) do
    keys[r.path] = sort_key(ws, r)
  end
  table.sort(rows, function(a, b)
    local ka, kb = keys[a.path], keys[b.path]
    if type(ka) ~= type(kb) then
      ka, kb = tostring(ka), tostring(kb)
    end
    if ka == kb then
      return a.path < b.path
    end
    if ws.sort.desc then
      return ka > kb
    end
    return ka < kb
  end)
  return rows
end

--------------------------------------------------------------- async helpers

---Run `fn(item, done)` for each item in sequence, then `finish()`.
local function series(items, fn, finish)
  local i = 0
  local function step()
    i = i + 1
    if i > #items then
      finish()
      return
    end
    fn(items[i], step)
  end
  step()
end

------------------------------------------------------------------- full text

local function apply_fulltext(ws, filter, paths, cb)
  local sets, err = {}, nil
  series(filter.terms, function(term, done)
    if rg.available() then
      rg.matching(ws, term.value, function(hits, e)
        if e then
          err = e
        end
        sets[#sets + 1] = { term = term, set = to_set(hits or {}) }
        done()
      end)
    else
      local set = {}
      for _, p in ipairs(paths) do
        if rg.file_contains(p, term.value) then
          set[p] = true
        end
      end
      sets[#sets + 1] = { term = term, set = set }
      vim.schedule(done)
    end
  end, function()
    if err then
      cb(nil, err)
      return
    end
    local out = {}
    for _, p in ipairs(paths) do
      local keep
      if filter.mode == "all" then
        keep = true
        for _, s in ipairs(sets) do
          local hit = s.set[p] == true
          if s.term.negate then
            hit = not hit
          end
          if not hit then
            keep = false
            break
          end
        end
      else
        keep = false
        for _, s in ipairs(sets) do
          local hit = s.set[p] == true
          if s.term.negate then
            hit = not hit
          end
          if hit then
            keep = true
            break
          end
        end
      end
      if keep then
        out[#out + 1] = p
      end
    end
    cb(out, nil)
  end)
end

----------------------------------------------------------------------- entry

---@param ws table
---@param q table
---@param opts table|nil { prefilter = boolean }
---@param cb fun(rows: table[]|nil, err: string|nil)
function M.run(ws, q, opts, cb)
  opts = opts or {}
  local cfg = config.get()
  local use_prefilter = opts.prefilter ~= false and rg.available()

  rg.files(ws, function(all, err)
    if err then
      cb(nil, err)
      return
    end
    all = all or {}

    local function narrowed(candidates)
      local hits = {}
      for _, path in ipairs(candidates) do
        local fields = fm.read(path)
        if fields and query_mod.match(q, fields) then
          hits[#hits + 1] = path
        end
      end

      local function finish(paths)
        local rows = {}
        for _, path in ipairs(paths) do
          -- Only the declared fields travel with a row: that is the documented
          -- contract, and it is what keeps the two backends interchangeable.
          local parsed, fields = fm.read(path) or {}, {}
          for _, spec in ipairs(ws.fields) do
            if parsed[spec.key] ~= nil then
              fields[spec.key] = parsed[spec.key]
            end
          end
          rows[#rows + 1] = { path = path, rel = util.relative(path, ws.root), fields = fields }
        end
        sort_rows(ws, rows)
        local truncated = false
        if #rows > cfg.limit then
          truncated = true
          for i = #rows, cfg.limit + 1, -1 do
            rows[i] = nil
          end
        end
        cb(rows, nil, { truncated = truncated })
      end

      if q.fulltext then
        apply_fulltext(ws, q.fulltext, hits, function(paths, e)
          if e then
            cb(nil, e)
          else
            finish(paths)
          end
        end)
      else
        finish(hits)
      end
    end

    local literals = use_prefilter and query_mod.literals(q) or {}
    if #literals == 0 then
      vim.schedule(function()
        narrowed(all)
      end)
      return
    end

    local keep = to_set(all)
    local ferr
    series(literals, function(literal, done)
      rg.matching(ws, literal, function(paths, e)
        if e then
          ferr = e
          done()
          return
        end
        local found = to_set(paths or {})
        for p in pairs(keep) do
          if not found[p] then
            keep[p] = nil
          end
        end
        done()
      end)
    end, function()
      if ferr then
        cb(nil, ferr)
        return
      end
      local candidates = {}
      for _, p in ipairs(all) do
        if keep[p] then
          candidates[#candidates + 1] = p
        end
      end
      narrowed(candidates)
    end)
  end)
end

return M
