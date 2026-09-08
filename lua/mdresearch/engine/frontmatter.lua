--- YAML-frontmatter reader.
---
--- Deliberately a *subset* of YAML — the shapes that appear in note
--- frontmatter — because a full parser is not worth the dependency:
---
---   key: scalar          key: [a, b, "c d"]        key: "quoted: value"
---   key:                 key: |                    key: #tag1 #tag2
---     - a                  block text
---     - "b c"            nested:
---                          sub: value
---
--- Anything it cannot make sense of yields `nil` for that file, which the
--- engines treat as "not a match" rather than as an error.
local M = {}

local MAX_BYTES = 64 * 1024

---@type table<string, { mtime: number, size: number, fields: table|nil }>
local cache = {}

------------------------------------------------------------------- scalars --

local function unquote(s)
  local q = s:sub(1, 1)
  if (q == '"' or q == "'") and s:sub(-1) == q and #s >= 2 then
    return s:sub(2, -2)
  end
  return s
end

local function is_tag_list(s)
  if s:sub(1, 1) ~= "#" then
    return false
  end
  for word in s:gmatch("%S+") do
    if word:sub(1, 1) ~= "#" then
      return false
    end
  end
  return true
end

local function strip_comment(s)
  if is_tag_list(s) then
    return s
  end
  local out, quote = {}, nil
  local i = 1
  while i <= #s do
    local c = s:sub(i, i)
    if quote then
      if c == quote then
        quote = nil
      end
      out[#out + 1] = c
    elseif c == '"' or c == "'" then
      quote = c
      out[#out + 1] = c
    elseif c == "#" and (i == 1 or s:sub(i - 1, i - 1):match("%s")) then
      break
    else
      out[#out + 1] = c
    end
    i = i + 1
  end
  return (table.concat(out):gsub("%s+$", ""))
end

local function coerce(s)
  if s == "" then
    return ""
  end
  local n = s:match("^-?%d+$")
  if n then
    return tonumber(n)
  end
  return s
end

--- Split a `[a, b, "c d"]` flow sequence.
local function flow_seq(body)
  local out, buf, quote = {}, {}, nil
  local function flush()
    local v = table.concat(buf):gsub("^%s+", ""):gsub("%s+$", "")
    buf = {}
    if v ~= "" then
      out[#out + 1] = coerce(unquote(v))
    end
  end
  for i = 1, #body do
    local c = body:sub(i, i)
    if quote then
      if c == quote then
        quote = nil
      else
        buf[#buf + 1] = c
      end
    elseif c == '"' or c == "'" then
      quote = c
    elseif c == "," then
      flush()
    else
      buf[#buf + 1] = c
    end
  end
  flush()
  return out
end

---Turn the text right of `key:` into a value.
local function scalar(raw)
  raw = raw:gsub("^%s+", ""):gsub("%s+$", "")
  if raw == "" then
    return nil
  end
  if raw:sub(1, 1) == "[" and raw:sub(-1) == "]" then
    return flow_seq(raw:sub(2, -2))
  end
  raw = strip_comment(raw)
  if is_tag_list(raw) then
    local out = {}
    for word in raw:gmatch("#(%S+)") do
      out[#out + 1] = word
    end
    return out
  end
  return coerce(unquote(raw))
end

-------------------------------------------------------------------- blocks --

local function indent_of(line)
  local sp = line:match("^(%s*)")
  return #sp
end

local function is_blank(line)
  return line == nil or line:match("^%s*$") ~= nil
end

local parse_block

---Collect a `|` / `>` block scalar starting at line `i`.
local function block_scalar(lines, i, base_indent, fold)
  local parts = {}
  while i <= #lines do
    local line = lines[i]
    if is_blank(line) then
      parts[#parts + 1] = ""
      i = i + 1
    elseif indent_of(line) > base_indent then
      parts[#parts + 1] = line:sub(base_indent + 2):gsub("^%s+", "")
      i = i + 1
    else
      break
    end
  end
  while #parts > 0 and parts[#parts] == "" do
    table.remove(parts)
  end
  return table.concat(parts, fold and " " or "\n"), i
end

---Parse a sequence of `- item` lines at `indent`.
local function parse_seq(lines, i, indent)
  local out = {}
  while i <= #lines do
    local line = lines[i]
    if is_blank(line) then
      i = i + 1
    elseif indent_of(line) ~= indent or not line:match("^%s*%-%s") and not line:match("^%s*%-$") then
      break
    else
      local rest = line:match("^%s*%-%s*(.*)$")
      if rest == "" then
        local child, ni = parse_block(lines, i + 1, indent + 2)
        out[#out + 1] = child
        i = ni
      else
        out[#out + 1] = scalar(rest)
        i = i + 1
      end
    end
  end
  return out, i
end

---Parse a mapping (or sequence) block at `indent`. Returns value, next index.
---@return table|nil, integer
parse_block = function(lines, i, indent)
  -- skip blanks and comments
  while i <= #lines and (is_blank(lines[i]) or lines[i]:match("^%s*#")) do
    i = i + 1
  end
  if i > #lines then
    return {}, i
  end
  local first = lines[i]
  local ind = indent_of(first)
  if ind < indent then
    return {}, i
  end
  if first:match("^%s*%-%s") or first:match("^%s*%-$") then
    return parse_seq(lines, i, ind)
  end

  local map = {}
  while i <= #lines do
    local line = lines[i]
    if is_blank(line) or line:match("^%s*#") then
      i = i + 1
    elseif indent_of(line) < ind then
      break
    elseif indent_of(line) > ind then
      i = i + 1 -- stray deeper line; already consumed by a child otherwise
    else
      local key, rest = line:match("^%s*([%w_%-%.%$]+)%s*:%s?(.*)$")
      if not key then
        local qkey, qrest = line:match("^%s*[\"']([^\"']+)[\"']%s*:%s?(.*)$")
        key, rest = qkey, qrest
      end
      if not key then
        break
      end
      rest = rest or ""
      local trimmed = rest:gsub("^%s+", ""):gsub("%s+$", "")
      if trimmed == "|" or trimmed == ">" or trimmed == "|-" or trimmed == ">-" then
        local text, ni = block_scalar(lines, i + 1, ind, trimmed:sub(1, 1) == ">")
        map[key] = text
        i = ni
      elseif trimmed == "" then
        -- child block: a deeper mapping, or a sequence at this indent or deeper
        local j = i + 1
        while j <= #lines and (is_blank(lines[j]) or lines[j]:match("^%s*#")) do
          j = j + 1
        end
        local nxt = lines[j]
        if nxt and (indent_of(nxt) > ind or (indent_of(nxt) == ind and nxt:match("^%s*%-%s?"))) then
          local child, ni = parse_block(lines, j, indent_of(nxt))
          map[key] = child
          i = ni
        else
          map[key] = ""
          i = i + 1
        end
      else
        map[key] = scalar(rest)
        i = i + 1
      end
    end
  end
  return map, i
end

--------------------------------------------------------------------- entry --

---Parse a full frontmatter document (the text *between* the `---` markers).
---@param text string
---@return table
function M.parse(text)
  local lines = vim.split(text, "\n", { plain = true })
  local ok, map = pcall(parse_block, lines, 1, 0)
  if not ok or type(map) ~= "table" then
    return {}
  end
  return map
end

---Split a file's content into frontmatter text and the byte offset of the body.
---@param content string
---@return string|nil
function M.extract(content)
  content = content:gsub("^\239\187\191", "") -- BOM
  if content:sub(1, 3) ~= "---" then
    return nil
  end
  local first_nl = content:find("\n")
  if not first_nl then
    return nil
  end
  if content:sub(1, first_nl - 1):gsub("%s+$", "") ~= "---" then
    return nil
  end
  local s = first_nl + 1
  local from = s
  while true do
    local nl = content:find("\n", from, true)
    local line = content:sub(from, (nl or (#content + 1)) - 1):gsub("\r$", "")
    local t = line:gsub("%s+$", "")
    if t == "---" or t == "..." then
      return content:sub(s, from - 2)
    end
    if not nl then
      return nil -- unterminated frontmatter
    end
    from = nl + 1
  end
end

local function read_head(path)
  local fd = io.open(path, "rb")
  if not fd then
    return nil
  end
  local data = fd:read(MAX_BYTES)
  fd:close()
  return data
end

---Read and parse a file's frontmatter, memoised on (mtime, size).
---@param path string
---@return table|nil
function M.read(path)
  local st = vim.uv.fs_stat(path)
  if not st then
    cache[path] = nil
    return nil
  end
  local mtime = st.mtime.sec * 1e9 + st.mtime.nsec
  local hit = cache[path]
  if hit and hit.mtime == mtime and hit.size == st.size then
    return hit.fields
  end
  local content = read_head(path)
  local fields = nil
  if content then
    local fm = M.extract(content)
    if fm then
      fields = M.parse(fm)
    end
  end
  cache[path] = { mtime = mtime, size = st.size, fields = fields }
  return fields
end

---@param path string|nil  nil clears everything
function M.invalidate(path)
  if path then
    cache[vim.fs.normalize(path)] = nil
    cache[path] = nil
  else
    cache = {}
  end
end

function M.cache_size()
  return vim.tbl_count(cache)
end

return M
