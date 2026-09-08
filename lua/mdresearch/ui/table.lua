--- Column layout for the result buffer.
---
--- Pure functions over data: it never touches a buffer, so it is testable
--- on its own and the result view stays a thin shell around it.
local util = require("mdresearch.util")

local M = {}

M.SEP = " │ "
M.MIN_WIDTH = 6

---Flatten a frontmatter value into one display string.
---@param v any
---@return string
function M.format_value(v)
  if v == nil then
    return ""
  end
  if type(v) == "table" then
    local parts = {}
    for _, item in ipairs(v) do
      parts[#parts + 1] = M.format_value(item)
    end
    return table.concat(parts, ", ")
  end
  if type(v) == "number" and v == math.floor(v) then
    return string.format("%d", v)
  end
  if type(v) == "boolean" then
    return tostring(v)
  end
  return (tostring(v):gsub("[\r\n]+", " "))
end

---The text of one cell.
---@param row table
---@param col table
---@return string
function M.cell(row, col)
  if col.key == "path" then
    return row.rel or row.path or ""
  end
  if col.key == "rel" then
    return row.rel or ""
  end
  return M.format_value((row.fields or {})[col.key])
end

---Decide a display width for every column.
---@param columns table[]
---@param rows table[]
---@param max_width integer|nil  total width available
---@return integer[]
function M.layout(columns, rows, max_width)
  local widths = {}
  for i, col in ipairs(columns) do
    local w = vim.fn.strdisplaywidth(col.label or col.key)
    for _, row in ipairs(rows) do
      local cw = vim.fn.strdisplaywidth(M.cell(row, col))
      if cw > w then
        w = cw
      end
    end
    if col.width and w > col.width then
      w = col.width
    end
    widths[i] = math.max(w, M.MIN_WIDTH)
  end

  if not max_width or max_width <= 0 then
    return widths
  end

  local sep = vim.fn.strdisplaywidth(M.SEP) * (#columns - 1)
  local function total()
    local t = sep
    for _, w in ipairs(widths) do
      t = t + w
    end
    return t
  end

  -- Shrink the widest column repeatedly; a narrow column never pays for a
  -- wide neighbour, and nothing goes below MIN_WIDTH.
  local guard = 0
  while total() > max_width and guard < 10000 do
    guard = guard + 1
    local widest, idx = 0, nil
    for i, w in ipairs(widths) do
      if w > widest and w > M.MIN_WIDTH then
        widest, idx = w, i
      end
    end
    if not idx then
      break
    end
    widths[idx] = widths[idx] - 1
  end
  return widths
end

---@param columns table[]
---@param rows table[]
---@param opts table|nil  { max_width, header = true }
---@return { lines: string[], spans: table[], first_row: integer, widths: integer[] }
function M.render(columns, rows, opts)
  opts = opts or {}
  local widths = M.layout(columns, rows, opts.max_width)
  local lines, spans = {}, {}

  local function compose(cells, hl)
    local parts, cols, byte = {}, {}, 0
    for i, text in ipairs(cells) do
      if i > 1 then
        parts[#parts + 1] = M.SEP
        byte = byte + #M.SEP
      end
      local padded = util.fit(text, widths[i])
      cols[#cols + 1] = { from = byte, to = byte + #padded }
      parts[#parts + 1] = padded
      byte = byte + #padded
    end
    local line = table.concat(parts)
    lines[#lines + 1] = line
    if hl then
      for i, c in ipairs(cols) do
        spans[#spans + 1] = { line = #lines - 1, from = c.from, to = c.to, hl = hl(i) }
      end
    end
    return line
  end

  local first_row = 0
  if opts.header ~= false then
    local labels = {}
    for _, col in ipairs(columns) do
      labels[#labels + 1] = col.label or col.key
    end
    compose(labels, function()
      return "MdResearchHeader"
    end)
    local rule = {}
    for i = 1, #columns do
      rule[i] = string.rep("─", widths[i])
    end
    lines[#lines + 1] = table.concat(rule, "─┼─")
    spans[#spans + 1] = { line = #lines - 1, from = 0, to = -1, hl = "MdResearchRule" }
    first_row = 2
  end

  for _, row in ipairs(rows) do
    local cells = {}
    for i, col in ipairs(columns) do
      cells[i] = M.cell(row, col)
    end
    compose(cells, function(i)
      return i == 1 and "MdResearchTitle" or "MdResearchCell"
    end)
  end

  return { lines = lines, spans = spans, first_row = first_row, widths = widths }
end

return M
