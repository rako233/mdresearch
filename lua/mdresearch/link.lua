--- Link text for a result row.
---
--- Pure functions over a row: nothing here touches a buffer or a register,
--- so every format is testable on its own and `ui.results` stays a shell
--- around it. The target is always the row's workspace-relative path, so a
--- link pasted into a note in the same vault resolves.
local M = {}

M.FORMATS = { markdown = true, wiki = true, path = true }

--- Defaults for a bare `render(row)`, matching `ui.results.link`.
M.DEFAULT_FORMAT = "markdown"
M.DEFAULT_LABEL = "title"

---@param rel string
---@return string
local function strip_ext(rel)
  return (rel:gsub("%.[^./]+$", ""))
end

---The text in front of a link: the named field, else the file stem. A list
---value uses its first item, which is what a multi-value `title` would mean.
---@param row table
---@param key string|false|nil  field key, or false for the file stem
---@return string
function M.label(row, key)
  local v
  if key and row.fields then
    v = row.fields[key]
  end
  if type(v) == "table" then
    v = v[1]
  end
  if v ~= nil and v ~= "" then
    return tostring(v)
  end
  return vim.fs.basename(strip_ext(row.rel))
end

--- A Markdown target stops at the first space, and a bare paren closes the
--- link early. Angle brackets are CommonMark's own escape for both, and
--- inside them only `<` and `>` themselves still need a backslash. Nothing
--- is dropped: a mangled path is worse than an ugly one.
---@param target string
---@return string
local function md_target(target)
  if target:find("[%s()<>]") then
    return "<" .. target:gsub("([<>])", "\\%1") .. ">"
  end
  return target
end

---@param s string
---@return string
local function md_label(s)
  return (s:gsub("([%[%]])", "\\%1"))
end

---Render a row as a link relative to its workspace root.
---@param row table  { rel = string, fields = table }
---@param opts { format?: string, label?: string|false, ext?: boolean }|nil
---@return string|nil link, string|nil err
function M.render(row, opts)
  opts = opts or {}
  local format = opts.format or M.DEFAULT_FORMAT
  if not M.FORMATS[format] then
    return nil, string.format("unknown link format %q (markdown|wiki|path)", tostring(format))
  end

  local target = row.rel
  if opts.ext == false then
    target = strip_ext(target)
  end

  if format == "path" then
    return target
  end
  if format == "wiki" then
    return "[[" .. target .. "]]"
  end
  local key = opts.label
  if key == nil then
    key = M.DEFAULT_LABEL
  end
  return string.format("[%s](%s)", md_label(M.label(row, key)), md_target(target))
end

return M
