--- Quote-aware splitting of a search-mask field into values.
---
--- `foo bar "baz qux"`  ->  foo | bar | baz qux
--- A token that *starts* with a quote is flagged `quoted`; the parser then
--- treats it as a literal and does not look for an operator prefix, so
--- `="a b"` is an exact match on `a b` while `"=a b"` searches for `=a b`.
local M = {}

local QUOTES = { ['"'] = true, ["'"] = true }

---@param s string
---@return { text: string, quoted: boolean }[]
function M.tokens(s)
  local out = {}
  local i, n = 1, #s
  while i <= n do
    local c = s:sub(i, i)
    if c:match("%s") then
      i = i + 1
    else
      local buf, quoted = {}, false
      local started_quoted = QUOTES[c] or false
      while i <= n do
        c = s:sub(i, i)
        if quoted then
          if c == quoted then
            quoted = false
          else
            buf[#buf + 1] = c
          end
          i = i + 1
        elseif QUOTES[c] then
          quoted = c
          i = i + 1
        elseif c:match("%s") then
          break
        else
          buf[#buf + 1] = c
          i = i + 1
        end
      end
      local text = table.concat(buf)
      if text ~= "" then
        out[#out + 1] = { text = text, quoted = started_quoted }
      end
    end
  end
  return out
end

---Plain string list, for callers that do not care about quoting.
---@param s string
---@return string[]
function M.split(s)
  local out = {}
  for _, t in ipairs(M.tokens(s)) do
    out[#out + 1] = t.text
  end
  return out
end

return M
