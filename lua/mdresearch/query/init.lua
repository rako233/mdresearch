local parser = require("mdresearch.query.parser")
local predicate = require("mdresearch.query.predicate")

local M = {}
M.parser = parser
M.predicate = predicate
M.lexer = require("mdresearch.query.lexer")

---@param ws table
---@return table
function M.new(ws)
  return { workspace = ws.name, fields = {}, order = {}, fulltext = nil }
end

---Build a Query from mask input.
---@param ws table
---@param raw table<string,string>   field key -> input ("__fulltext" for free text)
---@param modes table<string,string>|nil  field key -> "any"|"all"
---@return table|nil query, string|nil err
function M.parse(ws, raw, modes)
  raw, modes = raw or {}, modes or {}
  local q = M.new(ws)
  for _, spec in ipairs(ws.fields) do
    local filter, err = parser.field(spec, raw[spec.key], modes[spec.key])
    if err then
      return nil, err
    end
    if filter then
      q.fields[spec.key] = filter
      q.order[#q.order + 1] = spec.key
    end
  end
  q.fulltext = parser.fulltext(raw.__fulltext, modes.__fulltext)
  return q
end

---@param q table
function M.is_empty(q)
  return next(q.fields) == nil and q.fulltext == nil
end

---Match parsed frontmatter against the metadata part of the query.
---The full-text part is not evaluated here; the engines handle it.
---@param q table
---@param fields table  raw frontmatter values
---@return boolean
function M.match(q, fields)
  for _, key in ipairs(q.order) do
    if not predicate.field(q.fields[key], fields[key]) then
      return false
    end
  end
  return true
end

---Literals that must appear somewhere in every matching file.
---Used only to narrow candidates before the real predicate runs, so it must
---never include a term whose absence could still match (negation, regex,
---or one alternative of an OR).
---@param q table
---@return string[]
function M.literals(q)
  local out, seen = {}, {}
  local function add(v)
    if type(v) == "string" and #v >= 2 and not seen[v] then
      seen[v] = true
      out[#out + 1] = v
    end
  end
  for _, key in ipairs(q.order) do
    local f = q.fields[key]
    if f.type == "text" then
      if f.mode == "all" then
        for _, t in ipairs(f.terms) do
          if not t.negate and (t.op == "contains" or t.op == "exact") then
            add(t.value)
          end
        end
      elseif #f.terms == 1 then
        local t = f.terms[1]
        if not t.negate and (t.op == "contains" or t.op == "exact") then
          add(t.value)
        end
      end
    end
  end
  return out
end

---One-line human summary, used in the results header.
---@param q table
---@return string
function M.describe(q)
  local parts = {}
  for _, key in ipairs(q.order) do
    local f = q.fields[key]
    local vals = {}
    for _, t in ipairs(f.terms) do
      local v
      if t.op == "between" or t.op == "after" or t.op == "before" then
        local from = t.from and tostring(t.from) or ""
        local to = t.to and tostring(t.to) or ""
        v = (from ~= "" and from or "*") .. ".." .. (to ~= "" and to or "*")
        if t.op == "between" and t.from == t.to then
          v = from
        end
      else
        v = tostring(t.value)
      end
      vals[#vals + 1] = (t.negate and "!" or "") .. v
    end
    parts[#parts + 1] = string.format("%s %s(%s)", key, f.mode == "all" and "all" or "any", table.concat(vals, " "))
  end
  if q.fulltext then
    local vals = {}
    for _, t in ipairs(q.fulltext.terms) do
      vals[#vals + 1] = (t.negate and "!" or "") .. t.value
    end
    parts[#parts + 1] = string.format("text %s(%s)", q.fulltext.mode, table.concat(vals, " "))
  end
  if #parts == 0 then
    return "all files"
  end
  return table.concat(parts, "  ")
end

return M
