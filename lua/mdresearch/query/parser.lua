local lexer = require("mdresearch.query.lexer")
local util = require("mdresearch.util")

local M = {}

--------------------------------------------------------------------- dates --

local DAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

local function last_day(y, m)
  if m == 2 and ((y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0) then
    return 29
  end
  return DAYS[m]
end

---Encode a calendar date as a sortable integer, y*10000 + m*100 + d.
function M.ymd(y, m, d)
  return y * 10000 + m * 100 + d
end

---Calendar neighbours of an encoded date, so exclusive bounds stay real dates.
function M.next_ymd(v)
  local y, m, d = math.floor(v / 10000), math.floor(v % 10000 / 100), v % 100
  d = d + 1
  if d > last_day(y, m) then
    d, m = 1, m + 1
    if m > 12 then
      m, y = 1, y + 1
    end
  end
  return M.ymd(y, m, d)
end

function M.prev_ymd(v)
  local y, m, d = math.floor(v / 10000), math.floor(v % 10000 / 100), v % 100
  d = d - 1
  if d < 1 then
    m = m - 1
    if m < 1 then
      m, y = 12, y - 1
    end
    d = last_day(y, m)
  end
  return M.ymd(y, m, d)
end

---Parse an ISO date, allowing partial precision. Returns the closed range the
---token denotes: `2025` -> 2025-01-01 .. 2025-12-31.
---@param s string
---@return integer|nil from, integer|nil to
function M.parse_date_token(s)
  s = util.trim(s)
  local y, m, d = s:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  if y then
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if m < 1 or m > 12 or d < 1 or d > last_day(y, m) then
      return nil
    end
    return M.ymd(y, m, d), M.ymd(y, m, d)
  end
  y, m = s:match("^(%d%d%d%d)%-(%d%d)$")
  if y then
    y, m = tonumber(y), tonumber(m)
    if m < 1 or m > 12 then
      return nil
    end
    return M.ymd(y, m, 1), M.ymd(y, m, last_day(y, m))
  end
  y = s:match("^(%d%d%d%d)$")
  if y then
    y = tonumber(y)
    return M.ymd(y, 1, 1), M.ymd(y, 12, 31)
  end
  return nil
end

---Parse a stored frontmatter value into a comparable date integer.
---Accepts `YYYY-MM-DD`, `YYYY-MM-DDTHH:MM[:SS]`, `YYYY-MM-DD HH:MM[:SS]` and
---`YYYY-MM-DD-HH:MM`. Time is deliberately discarded: searching is date-only.
---@param v any
---@return integer|nil
function M.value_to_ymd(v)
  if type(v) == "number" then
    v = tostring(v)
  end
  if type(v) ~= "string" then
    return nil
  end
  local y, m, d = util.trim(v):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
  if not y then
    return nil
  end
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  if m < 1 or m > 12 or d < 1 or d > 31 then
    return nil
  end
  return M.ymd(y, m, d)
end

--------------------------------------------------------------------- terms --

local function strip_negation(text)
  if text:sub(1, 1) == "!" then
    return text:sub(2), true
  end
  return text, false
end

local function text_term(tok)
  if tok.quoted then
    return { op = "contains", value = tok.text:lower() }
  end
  local text, negate = strip_negation(tok.text)
  if text == "" then
    return nil
  end
  local re = text:match("^/(.*)/$")
  if re then
    return { op = "regex", value = re, negate = negate }
  end
  if text:sub(1, 1) == "=" then
    return { op = "exact", value = text:sub(2):lower(), negate = negate }
  end
  if text:sub(1, 1) == "#" then -- convenience: #tag == tag
    text = text:sub(2)
  end
  return { op = "contains", value = text:lower(), negate = negate }
end

---@return table|nil term, string|nil err
local function int_term(tok)
  local text, negate = strip_negation(tok.text)
  local a, b = text:match("^(-?%d+)%.%.(-?%d+)$")
  if a then
    return { op = "between", from = tonumber(a), to = tonumber(b), negate = negate }
  end
  local op, num = text:match("^([<>]=?)%s*(-?%d+)$")
  if op then
    num = tonumber(num)
    local map = { [">="] = { from = num }, [">"] = { from = num + 1 }, ["<="] = { to = num }, ["<"] = { to = num - 1 } }
    local r = map[op]
    return { op = "between", from = r.from, to = r.to, negate = negate }
  end
  local n = tonumber(text)
  if not n or n ~= math.floor(n) then
    return nil, string.format("%q is not an integer condition", tok.text)
  end
  return { op = "eq", value = n, negate = negate }
end

---@return table|nil term, string|nil err
local function date_term(tok)
  local text, negate = strip_negation(tok.text)
  local lower = text:lower()

  -- word forms
  local rest = lower:match("^after:(.*)$") or lower:match("^from:(.*)$")
  if rest then
    local from = M.parse_date_token(rest)
    if not from then
      return nil, string.format("%q is not an ISO date", rest)
    end
    return { op = "after", from = from, negate = negate }
  end
  rest = lower:match("^before:(.*)$") or lower:match("^until:(.*)$")
  if rest then
    local _, to = M.parse_date_token(rest)
    if not to then
      return nil, string.format("%q is not an ISO date", rest)
    end
    return { op = "before", to = to, negate = negate }
  end

  -- range
  local a, b = text:match("^(.-)%.%.(.*)$")
  if a and a ~= "" and b ~= "" then
    local from = M.parse_date_token(a)
    local _, to = M.parse_date_token(b)
    if not from or not to then
      return nil, string.format("%q is not an ISO date range", text)
    end
    return { op = "between", from = from, to = to, negate = negate }
  end

  -- comparison operators
  local op, val = text:match("^([<>]=?)%s*(.*)$")
  if op then
    local from, to = M.parse_date_token(val)
    if not from then
      return nil, string.format("%q is not an ISO date", val)
    end
    if op == ">=" then
      return { op = "after", from = from, negate = negate }
    elseif op == ">" then
      return { op = "after", from = M.next_ymd(to), negate = negate }
    elseif op == "<=" then
      return { op = "before", to = to, negate = negate }
    else
      return { op = "before", to = M.prev_ymd(from), negate = negate }
    end
  end

  local from, to = M.parse_date_token(text)
  if not from then
    return nil, string.format("%q is not an ISO date (yyyy, yyyy-mm or yyyy-mm-dd)", text)
  end
  return { op = "between", from = from, to = to, negate = negate }
end

--------------------------------------------------------------------- field --

local MODE_PREFIX = { any = "any", ["or"] = "any", all = "all", ["and"] = "all" }

---Split a leading `any:` / `all:` (aliases `or:` / `and:`) off the raw input.
---@param raw string
---@return string rest, "any"|"all"|nil mode
function M.split_mode(raw)
  local word, rest = raw:match("^%s*(%a+):%s*(.*)$")
  if word and MODE_PREFIX[word:lower()] then
    return rest, MODE_PREFIX[word:lower()]
  end
  return raw, nil
end

---Parse one mask field into a FieldFilter.
---@param spec table  field spec from the workspace config
---@param raw string  the user's input for that field
---@param mode "any"|"all"|nil  the mode toggled in the mask
---@return table|nil filter, string|nil err
function M.field(spec, raw, mode)
  raw = raw or ""
  local rest, inline_mode = M.split_mode(raw)
  if util.trim(rest) == "" then
    return nil, nil
  end

  local make = text_term
  if spec.type == "int" then
    make = int_term
  elseif spec.type == "date" or spec.type == "datetime" then
    make = date_term
  end

  local terms = {}
  for _, tok in ipairs(lexer.tokens(rest)) do
    if spec.type ~= "text" and tok.quoted then
      tok = { text = tok.text, quoted = false }
    end
    local term, err = make(tok)
    if err then
      return nil, string.format("%s: %s", spec.label, err)
    end
    if term then
      terms[#terms + 1] = term
    end
  end
  if #terms == 0 then
    return nil, nil
  end

  return {
    key = spec.key,
    type = spec.type,
    list = spec.list,
    mode = inline_mode or mode or spec.mode or "any",
    terms = terms,
  }
end

---Parse the free-text field. Terms are always plain literals.
---@param raw string
---@param mode "any"|"all"|nil
---@return table|nil
function M.fulltext(raw, mode)
  raw = raw or ""
  local rest, inline_mode = M.split_mode(raw)
  if util.trim(rest) == "" then
    return nil
  end
  local terms = {}
  for _, tok in ipairs(lexer.tokens(rest)) do
    local text, negate = tok.text, false
    if not tok.quoted then
      text, negate = strip_negation(text)
    end
    if text ~= "" then
      terms[#terms + 1] = { op = "contains", value = text, negate = negate }
    end
  end
  if #terms == 0 then
    return nil
  end
  return { key = "__fulltext", type = "text", list = false, mode = inline_mode or mode or "all", terms = terms }
end

return M
