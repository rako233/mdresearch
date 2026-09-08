--- The search mask.
---
--- One line per standard tag plus a free-text line:
---
---     Title    [any] │
---     Tags     [all] │ linux server
---     Date     [any] │ >=2025-01
---     Text     [all] │ docker
---
--- `build` and `read` are pure and inverse to each other, so a query can be
--- round-tripped through the buffer without going near a window.
---
--- Every action takes an optional `buf` and works on the mask's own window,
--- so `:MdResearchSubmit` reaches the mask from anywhere — nothing here
--- assumes the cursor is in the mask.
local config = require("mdresearch.config")
local highlight = require("mdresearch.ui.highlight")
local query_mod = require("mdresearch.query")
local util = require("mdresearch.util")

local M = {}

M.SEP = "│ "
M.FULLTEXT = "__fulltext"

local NS = vim.api.nvim_create_namespace("mdresearch.mask")

---@type table<integer, table>
local masks = {}

---The rows of the mask, in order.
---@param ws table
---@return { key: string, label: string, type: string }[]
function M.rows(ws)
  local rows = {}
  for _, f in ipairs(ws.fields) do
    rows[#rows + 1] = { key = f.key, label = f.label, type = f.type }
  end
  rows[#rows + 1] = { key = M.FULLTEXT, label = "Text", type = "text" }
  return rows
end

---Render the mask.
---@param ws table
---@param prefill table<string,string>|nil
---@param modes table<string,string>|nil
---@return { lines: string[], rows: table[], label_width: integer }
function M.build(ws, prefill, modes)
  prefill, modes = prefill or {}, modes or {}
  local rows = M.rows(ws)
  local label_width = 0
  for _, r in ipairs(rows) do
    label_width = math.max(label_width, vim.fn.strdisplaywidth(r.label))
  end

  local lines = {}
  for _, r in ipairs(rows) do
    local spec = ws.by_key[r.key]
    local mode = modes[r.key] or (spec and spec.mode) or (r.key == M.FULLTEXT and "all") or "any"
    lines[#lines + 1] = string.format(
      "%s [%s] %s%s",
      util.fit(r.label, label_width),
      mode,
      M.SEP,
      prefill[r.key] or ""
    )
  end
  return { lines = lines, rows = rows, label_width = label_width }
end

---Read the mask back into raw input and modes.
---@param lines string[]
---@param rows table[]
---@return table<string,string> raw, table<string,string> modes
function M.read(lines, rows)
  local raw, modes = {}, {}
  for i, r in ipairs(rows) do
    local line = lines[i] or ""
    local mode = line:match("%[(%a%a%a)%]")
    modes[r.key] = (mode == "all") and "all" or "any"
    local value = line:match(M.SEP .. "(.*)$")
    raw[r.key] = util.trim(value or "")
  end
  return raw, modes
end

---Byte column where the value starts on `line`.
---@param line string
---@return integer
function M.value_col(line)
  local s, e = line:find(M.SEP, 1, true)
  if not s then
    return 0
  end
  return e
end

--------------------------------------------------------------------- lookup --

---The mask to act on: the one in `buf`, else the one in the current buffer,
---else the only open one.
---@param buf integer|nil
---@return integer|nil buf, table|nil mask
function M.find(buf)
  -- A mask buffer is `bufhidden=wipe`, so it can go away without our
  -- BufWipeout autocmd having run yet. Never hand back a dead one.
  for b in pairs(masks) do
    if not vim.api.nvim_buf_is_valid(b) then
      masks[b] = nil
    end
  end
  if buf then
    if masks[buf] then
      return buf, masks[buf]
    end
    return nil, nil
  end
  local cur = vim.api.nvim_get_current_buf()
  if masks[cur] then
    return cur, masks[cur]
  end
  local only_buf, only, n = nil, nil, 0
  for b, m in pairs(masks) do
    only_buf, only, n = b, m, n + 1
  end
  if n == 1 then
    return only_buf, only
  end
  return nil, nil
end

---@param buf integer|nil
---@return boolean
function M.is_open(buf)
  return (M.find(buf)) ~= nil
end

---@param buf integer|nil
---@return table|nil
function M.mask(buf)
  local _, mask = M.find(buf)
  return mask
end

---The window showing `buf`, or nil.
---@param buf integer
---@param mask table
---@return integer|nil
local function mask_win(buf, mask)
  if mask.win and vim.api.nvim_win_is_valid(mask.win) then
    return mask.win
  end
  local wins = vim.fn.win_findbuf(buf)
  return wins[1]
end

---Row index of `field`: a 1-based number, a field key, a label, or `text`
---/`fulltext` for the free-text row.
---@param mask table
---@param field string|integer
---@return integer|nil index, string|nil err
function M.field_index(mask, field)
  if type(field) == "number" then
    if field < 1 or field > #mask.rows then
      return nil, string.format("no field #%d in the mask", field)
    end
    return field
  end
  local want = tostring(field)
  if want == "text" or want == "fulltext" then
    want = M.FULLTEXT
  end
  local lower = want:lower()
  for i, r in ipairs(mask.rows) do
    if r.key == want or r.key:lower() == lower or r.label:lower() == lower then
      return i
    end
  end
  return nil, string.format("no field %q in the mask", tostring(field))
end

---The row an action applies to: `field` when given, else the cursor line.
---@param buf integer
---@param mask table
---@param field string|integer|nil
---@return integer|nil lnum, string|nil err
local function target_row(buf, mask, field)
  if field ~= nil and field ~= "" then
    return M.field_index(mask, field)
  end
  local win = mask_win(buf, mask)
  local lnum = win and vim.api.nvim_win_get_cursor(win)[1] or 1
  return math.min(math.max(lnum, 1), #mask.rows)
end

local function line_at(buf, lnum)
  return vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ""
end

--------------------------------------------------------------------- render --

--- One hint per mask action: the mapping the user chose for it, or the
--- command that does the same thing when they mapped nothing.
local HINTS = {
  { action = "mask.submit", label = "search", cmd = ":MdResearchSubmit" },
  { action = "mask.toggle_mode", label = "any/all", cmd = ":MdResearchToggleMode" },
  { action = "mask.clear_field", label = "clear", cmd = ":MdResearchClearField" },
  { action = "mask.cancel", label = "close", cmd = ":MdResearchClose" },
}

---@return string
function M.hint()
  local bound = {}
  local km = config.get().keymaps.mask or {}
  for _, lhs in ipairs(util.keys(km)) do
    local spec = km[lhs]
    local action = type(spec) == "table" and spec[1] or spec
    if type(action) == "string" and not bound[action] then
      bound[action] = lhs
    end
  end
  local parts = {}
  for _, h in ipairs(HINTS) do
    parts[#parts + 1] = string.format("%s %s", bound[h.action] or h.cmd, h.label)
  end
  return "  " .. table.concat(parts, "   ")
end

local function apply_highlights(buf, mask)
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, line in ipairs(lines) do
    local lb = #util.fit(mask.rows[i] and mask.rows[i].label or "", mask.label_width)
    pcall(vim.api.nvim_buf_set_extmark, buf, NS, i - 1, 0, { end_col = lb, hl_group = "MdResearchLabel" })
    local s, e = line:find("%[%a%a%a%]")
    if s then
      local all = line:sub(s + 1, e - 1) == "all"
      pcall(vim.api.nvim_buf_set_extmark, buf, NS, i - 1, s - 1, {
        end_col = e,
        hl_group = all and "MdResearchModeAll" or "MdResearchMode",
      })
    end
  end
  if lines[#lines] and config.get().ui.mask.hint then
    pcall(vim.api.nvim_buf_set_extmark, buf, NS, #lines - 1, 0, {
      virt_lines = {
        { { "", "MdResearchHint" } },
        { { M.hint(), "MdResearchHint" } },
      },
    })
  end
end

-------------------------------------------------------------------- actions --

---Flip any/all on one field.
---@param opts { buf?: integer, field?: string|integer }|nil
---@return boolean ok, string|nil err
function M.toggle_mode(opts)
  opts = opts or {}
  local buf, mask = M.find(opts.buf)
  if not mask then
    return false, "no search mask is open"
  end
  local lnum, err = target_row(buf, mask, opts.field)
  if not lnum then
    return false, err
  end
  local line = line_at(buf, lnum)
  local new = line:gsub("%[any%]", "\1"):gsub("%[all%]", "[any]"):gsub("\1", "[all]")
  vim.api.nvim_buf_set_lines(buf, lnum - 1, lnum, false, { new })
  apply_highlights(buf, mask)
  return true
end

---Empty one field, or every field with `all = true`.
---@param opts { buf?: integer, field?: string|integer, all?: boolean }|nil
---@return boolean ok, string|nil err
function M.clear_field(opts)
  opts = opts or {}
  local buf, mask = M.find(opts.buf)
  if not mask then
    return false, "no search mask is open"
  end
  local from, to
  if opts.all then
    from, to = 1, #mask.rows
  else
    local lnum, err = target_row(buf, mask, opts.field)
    if not lnum then
      return false, err
    end
    from, to = lnum, lnum
  end
  for lnum = from, to do
    local line = line_at(buf, lnum)
    vim.api.nvim_buf_set_lines(buf, lnum - 1, lnum, false, { line:sub(1, M.value_col(line)) })
  end
  local win = mask_win(buf, mask)
  if win then
    local line = line_at(buf, from)
    pcall(vim.api.nvim_win_set_cursor, win, { from, M.value_col(line) })
  end
  return true
end

---Write `value` into one field.
---@param field string|integer
---@param value string
---@param opts { buf?: integer }|nil
---@return boolean ok, string|nil err
function M.set_field(field, value, opts)
  opts = opts or {}
  local buf, mask = M.find(opts.buf)
  if not mask then
    return false, "no search mask is open"
  end
  local lnum, err = M.field_index(mask, field)
  if not lnum then
    return false, err
  end
  local line = line_at(buf, lnum)
  vim.api.nvim_buf_set_lines(buf, lnum - 1, lnum, false, {
    line:sub(1, M.value_col(line)) .. (value or ""),
  })
  return true
end

---Put the cursor on a field: `"next"`, `"prev"`, `"first"`, `"last"`, a
---1-based index, or a field key.
---@param target string|integer|nil
---@param opts { buf?: integer }|nil
---@return boolean ok, string|nil err
function M.focus_field(target, opts)
  opts = opts or {}
  local buf, mask = M.find(opts.buf)
  if not mask then
    return false, "no search mask is open"
  end
  local win = mask_win(buf, mask)
  if not win then
    return false, "the search mask has no window"
  end
  local n = #mask.rows
  local cur = vim.api.nvim_win_get_cursor(win)[1]
  local lnum
  if target == nil or target == "next" then
    lnum = cur % n + 1
  elseif target == "prev" then
    lnum = (cur - 2) % n + 1
  elseif target == "first" then
    lnum = 1
  elseif target == "last" then
    lnum = n
  else
    local idx, err = M.field_index(mask, tonumber(target) or target)
    if not idx then
      return false, err
    end
    lnum = idx
  end
  pcall(vim.api.nvim_win_set_cursor, win, { lnum, M.value_col(line_at(buf, lnum)) })
  return true
end

---Keep the cursor out of the label and mode columns.
---@param opts { buf?: integer }|nil
function M.guard_cursor(opts)
  opts = opts or {}
  local buf, mask = M.find(opts.buf)
  if not mask then
    return
  end
  local win = mask_win(buf, mask)
  if not win then
    return
  end
  local pos = vim.api.nvim_win_get_cursor(win)
  local col = M.value_col(line_at(buf, pos[1]))
  if pos[2] < col then
    pcall(vim.api.nvim_win_set_cursor, win, { pos[1], col })
  end
end

---Read the mask without submitting it.
---@param opts { buf?: integer }|nil
---@return table|nil raw, table|nil modes
function M.get(opts)
  opts = opts or {}
  local buf, mask = M.find(opts.buf)
  if not mask then
    return nil, nil
  end
  return M.read(vim.api.nvim_buf_get_lines(buf, 0, -1, false), mask.rows)
end

---Run the search the mask describes and close it.
---@param opts { buf?: integer }|nil
---@return boolean ok, string|nil err
function M.submit(opts)
  opts = opts or {}
  local buf, mask = M.find(opts.buf)
  if not mask then
    return false, "no search mask is open"
  end
  if mask.win == vim.api.nvim_get_current_win() and vim.fn.mode():find("i") then
    vim.cmd("stopinsert")
  end
  local raw, modes = M.read(vim.api.nvim_buf_get_lines(buf, 0, -1, false), mask.rows)
  local on_submit = mask.on_submit
  M.close({ buf = buf })
  if on_submit then
    on_submit(raw, modes)
  end
  return true
end

---@param opts { buf?: integer }|nil
---@return boolean ok, string|nil err
function M.close(opts)
  opts = opts or {}
  local buf, mask = M.find(opts.buf)
  if not mask then
    return false, "no search mask is open"
  end
  masks[buf] = nil
  if mask.win and vim.api.nvim_win_is_valid(mask.win) then
    pcall(vim.api.nvim_win_close, mask.win, true)
  end
  if vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
  return true
end

function M.forget(buf)
  masks[buf] = nil
end

---@param ws table
---@param prefill table|nil
---@param modes table|nil
---@param on_submit fun(raw: table, modes: table)
---@return integer buf
function M.open(ws, prefill, modes, on_submit)
  local cfg = config.get()
  highlight.setup()
  local mask = M.build(ws, prefill, modes)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, mask.lines)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "mdresearch-mask"

  local ui = cfg.ui.mask
  local width = ui.width <= 1 and math.floor(vim.o.columns * ui.width) or ui.width
  width = math.max(width, 40)
  local height = #mask.lines
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(1, math.floor((vim.o.lines - height) / 2) - 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = ui.border,
    title = (ui.title or " mdresearch ") .. "· " .. ws.name .. " ",
    title_pos = "center",
  })
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true

  mask.win = win
  mask.on_submit = on_submit
  mask.ws = ws
  masks[buf] = mask

  apply_highlights(buf, mask)
  pcall(vim.api.nvim_win_set_cursor, win, { 1, M.value_col(mask.lines[1]) })
  if cfg.ui.mask.insert then
    vim.cmd("startinsert!")
  end
  return buf
end

M.describe = query_mod.describe

return M
