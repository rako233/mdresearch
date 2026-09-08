local M = {}

---@param path string
---@return string
function M.expand(path)
  return vim.fs.normalize(vim.fn.expand(path))
end

--- Join path segments with "/", tolerating trailing separators.
function M.join(...)
  local parts = {}
  for _, p in ipairs({ ... }) do
    if p and p ~= "" then
      parts[#parts + 1] = (p:gsub("/+$", ""))
    end
  end
  return (table.concat(parts, "/"):gsub("//+", "/"))
end

--- Path of `file` relative to `root`, or `file` when it is outside.
function M.relative(file, root)
  root = root:gsub("/+$", "")
  if file:sub(1, #root + 1) == root .. "/" then
    return file:sub(#root + 2)
  end
  return file
end

function M.is_list(t)
  return type(t) == "table" and (next(t) == nil or t[1] ~= nil)
end

function M.contains(list, value)
  for _, v in ipairs(list) do
    if v == value then
      return true
    end
  end
  return false
end

function M.keys(t)
  local out = {}
  for k in pairs(t) do
    out[#out + 1] = k
  end
  table.sort(out)
  return out
end

--- Shallow-merge `override` into a deep copy of `base`.
--- List-valued keys are replaced wholesale, maps are merged recursively.
function M.deep_merge(base, override)
  local out = {}
  for k, v in pairs(base) do
    out[k] = type(v) == "table" and M.deep_merge(v, {}) or v
  end
  for k, v in pairs(override or {}) do
    if type(v) == "table" and type(out[k]) == "table" and not M.is_list(v) then
      out[k] = M.deep_merge(out[k], v)
    else
      out[k] = v
    end
  end
  return out
end

function M.trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Display width, clamped and ellipsised.
function M.fit(s, width)
  s = s or ""
  local w = vim.fn.strdisplaywidth(s)
  if w <= width then
    return s .. string.rep(" ", width - w)
  end
  if width <= 1 then
    return string.rep(" ", width)
  end
  -- strcharpart works on characters; shrink until it fits with the ellipsis.
  local chars = vim.fn.strchars(s)
  while chars > 0 do
    local cut = vim.fn.strcharpart(s, 0, chars)
    if vim.fn.strdisplaywidth(cut) + 1 <= width then
      local padded = cut .. "…"
      return padded .. string.rep(" ", width - vim.fn.strdisplaywidth(padded))
    end
    chars = chars - 1
  end
  return string.rep(" ", width)
end

function M.notify(msg, level)
  vim.notify("[mdresearch] " .. msg, level or vim.log.levels.INFO)
end

function M.err(msg)
  M.notify(msg, vim.log.levels.ERROR)
end

--- Turn a glob into a Lua pattern anchored at both ends.
--- Supports `**`, `*` and `?`; everything else is literal.
function M.glob_to_pattern(glob)
  local out, i = { "^" }, 1
  while i <= #glob do
    local c = glob:sub(i, i)
    if c == "*" then
      if glob:sub(i + 1, i + 1) == "*" then
        out[#out + 1] = ".*"
        i = i + 2
        if glob:sub(i, i) == "/" then
          i = i + 1
        end
      else
        out[#out + 1] = "[^/]*"
        i = i + 1
      end
    elseif c == "?" then
      out[#out + 1] = "[^/]"
      i = i + 1
    else
      out[#out + 1] = c:gsub("[%^%$%(%)%%%.%[%]%+%-]", "%%%1")
      i = i + 1
    end
  end
  out[#out + 1] = "$"
  return table.concat(out)
end

function M.matches_glob(path, glob)
  return path:match(M.glob_to_pattern(glob)) ~= nil
end

return M
