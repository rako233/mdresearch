local parser = require("mdresearch.query.parser")

local M = {}

---Flatten a frontmatter value into the list of scalars to match against.
---A scalar becomes a one-element list, so list and non-list fields share code.
---@param v any
---@return any[]
function M.items(v)
  if v == nil then
    return {}
  end
  if type(v) == "table" then
    local out = {}
    for _, item in ipairs(v) do
      if type(item) == "table" then
        for _, sub in ipairs(M.items(item)) do
          out[#out + 1] = sub
        end
      elseif item ~= nil then
        out[#out + 1] = item
      end
    end
    return out
  end
  return { v }
end

--------------------------------------------------------------- term matching

local function match_text(term, item)
  local s = tostring(item):lower()
  if term.op == "exact" then
    return s == term.value
  elseif term.op == "regex" then
    local ok, found = pcall(string.find, s, term.value)
    return ok and found ~= nil
  end
  return s:find(term.value, 1, true) ~= nil
end

local function match_int(term, item)
  local n = tonumber(item)
  if not n then
    return false
  end
  if term.op == "eq" then
    return n == term.value
  end
  if term.from and n < term.from then
    return false
  end
  if term.to and n > term.to then
    return false
  end
  return true
end

local function match_date(term, item)
  local d = parser.value_to_ymd(item)
  if not d then
    return false
  end
  if term.from and d < term.from then
    return false
  end
  if term.to and d > term.to then
    return false
  end
  return true
end

local MATCHERS = { text = match_text, int = match_int, date = match_date, datetime = match_date }

---Is `term` satisfied by the flattened field value?
---@param ftype string
---@param term table
---@param items any[]
---@return boolean
function M.term(ftype, term, items)
  local matcher = MATCHERS[ftype] or match_text
  local hit = false
  for _, item in ipairs(items) do
    if matcher(term, item) then
      hit = true
      break
    end
  end
  if term.negate then
    return not hit
  end
  return hit
end

---Evaluate a whole FieldFilter against a raw frontmatter value.
---@param filter table
---@param value any
---@return boolean
function M.field(filter, value)
  local items = M.items(value)
  if filter.mode == "all" then
    for _, term in ipairs(filter.terms) do
      if not M.term(filter.type, term, items) then
        return false
      end
    end
    return true
  end
  for _, term in ipairs(filter.terms) do
    if M.term(filter.type, term, items) then
      return true
    end
  end
  return false
end

return M
