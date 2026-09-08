--- The result table buffer.
---
--- One line per file; the line -> row mapping is kept in a Lua table rather
--- than parsed back out of the text, so column truncation can never corrupt
--- a path.
---
--- Every action takes an optional `buf` and an optional row `index`, so the
--- commands reach the table from any window and can name a row outright.
local config = require("mdresearch.config")
local highlight = require("mdresearch.ui.highlight")
local query_mod = require("mdresearch.query")
local state = require("mdresearch.state")
local tbl = require("mdresearch.ui.table")
local util = require("mdresearch.util")

local M = {}

local NS = vim.api.nvim_create_namespace("mdresearch.results")

---@type table<integer, { rows: table[], first_row: integer, ws: table, query: table }>
local views = {}

---@param buf integer|nil
---@return table|nil
function M.view(buf)
  return views[buf or vim.api.nvim_get_current_buf()]
end

---The table to act on: the one in `buf`, else the one in the current buffer,
---else the last one opened.
---@param buf integer|nil
---@return integer|nil buf, table|nil view
function M.find(buf)
  local function alive(b)
    return b and views[b] ~= nil and vim.api.nvim_buf_is_valid(b)
  end
  if buf then
    return alive(buf) and buf or nil, alive(buf) and views[buf] or nil
  end
  local cur = vim.api.nvim_get_current_buf()
  if alive(cur) then
    return cur, views[cur]
  end
  if alive(state.results_buf) then
    return state.results_buf, views[state.results_buf]
  end
  return nil, nil
end

---@param buf integer
---@return integer|nil
local function view_win(buf)
  local wins = vim.fn.win_findbuf(buf)
  return wins[1]
end

---True while a window is showing a result table. A table that exists but is
---hidden is still reachable through |M.find|, and |M.reopen| brings it back.
---@param buf integer|nil
---@return boolean
function M.is_open(buf)
  local b, view = M.find(buf)
  return view ~= nil and view_win(b) ~= nil
end

---The row under the cursor, or nil when the cursor is on the header.
---@param buf integer|nil
---@return table|nil
function M.row_under_cursor(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local view = views[buf]
  if not view then
    return nil
  end
  local win = view_win(buf)
  local lnum = win and vim.api.nvim_win_get_cursor(win)[1] or 0
  return view.rows[lnum - view.first_row]
end

---The rows of the current table.
---@param buf integer|nil
---@return table[]
function M.rows(buf)
  local _, view = M.find(buf)
  return view and view.rows or {}
end

---Row `index` (1-based), or the row under the cursor when `index` is nil.
---@param index integer|nil
---@param buf integer|nil
---@return table|nil row, string|nil err
function M.row(index, buf)
  local b, view = M.find(buf)
  if not view then
    return nil, "no result table is open"
  end
  if index == nil then
    local row = M.row_under_cursor(b)
    if not row then
      return nil, "no file on this line"
    end
    return row
  end
  local row = view.rows[index]
  if not row then
    return nil, string.format("no row #%d in the table (%d rows)", index, #view.rows)
  end
  return row
end

local function open_window(cfg)
  local ui = cfg.ui.results
  if ui.style == "tab" then
    vim.cmd("tabnew")
    return vim.api.nvim_get_current_win()
  end
  if ui.style == "float" then
    local width = math.floor(vim.o.columns * 0.9)
    local height = math.floor(vim.o.lines * (ui.size or 0.6))
    local buf = vim.api.nvim_create_buf(false, true)
    return vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = width,
      height = height,
      row = math.floor((vim.o.lines - height) / 2),
      col = math.floor((vim.o.columns - width) / 2),
      style = "minimal",
      border = "rounded",
      title = " mdresearch ",
    })
  end
  local size = ui.size or 0.45
  local height = size <= 1 and math.floor(vim.o.lines * size) or size
  vim.cmd(string.format("%s %dsplit", ui.position or "botright", height))
  return vim.api.nvim_get_current_win()
end

---@param ws table
---@param q table
---@param rows table[]
---@param meta table|nil
---@return integer buf
function M.open(ws, q, rows, meta)
  local cfg = config.get()
  highlight.setup()

  -- Where <CR> on a row should load the file: the window the search came
  -- from, never a result window.
  local origin = not views[vim.api.nvim_get_current_buf()] and vim.api.nvim_get_current_win() or nil

  -- Reuse the previous table buffer even when its window is gone, so
  -- reopening does not fight the old buffer for its name.
  local reuse = state.results_buf
  if reuse and not (vim.api.nvim_buf_is_valid(reuse) and views[reuse]) then
    reuse = nil
  end

  local win
  if reuse then
    local wins = vim.fn.win_findbuf(reuse)
    if #wins > 0 then
      win = wins[1]
      vim.api.nvim_set_current_win(win)
    end
  end
  if not win then
    win = open_window(cfg)
  end

  local buf = reuse or vim.api.nvim_get_current_buf()
  if not views[buf] then
    buf = vim.api.nvim_create_buf(false, true)
  end
  if vim.api.nvim_win_get_buf(win) ~= buf then
    vim.api.nvim_win_set_buf(win, buf)
  end

  local width = vim.api.nvim_win_get_width(win) - 1
  local rendered = tbl.render(ws.columns, rows, {
    max_width = width,
    header = cfg.ui.results.show_header,
  })

  local lines = vim.deepcopy(rendered.lines)
  local first_row = rendered.first_row
  if cfg.ui.results.show_count then
    local count = string.format(
      "%d %s  ·  %s  ·  %s%s",
      #rows,
      #rows == 1 and "file" or "files",
      ws.name,
      query_mod.describe(q),
      meta and meta.truncated and "  (truncated)" or ""
    )
    table.insert(lines, 1, count)
    table.insert(lines, 2, "")
    first_row = first_row + 2
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "mdresearch-results"
  local name = "mdresearch://results/" .. ws.name
  if vim.api.nvim_buf_get_name(buf) ~= name then
    pcall(vim.api.nvim_buf_set_name, buf, name)
  end
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"

  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  if cfg.ui.results.show_count then
    vim.api.nvim_buf_set_extmark(buf, NS, 0, 0, { end_col = #lines[1], hl_group = "MdResearchCount" })
  end
  local offset = first_row - rendered.first_row
  for _, span in ipairs(rendered.spans) do
    local line = span.line + offset
    if lines[line + 1] then
      pcall(vim.api.nvim_buf_set_extmark, buf, NS, line, span.from, {
        end_col = span.to < 0 and #lines[line + 1] or math.min(span.to, #lines[line + 1]),
        hl_group = span.hl,
      })
    end
  end

  views[buf] = {
    rows = rows,
    first_row = first_row,
    ws = ws,
    query = q,
    origin = origin or (views[buf] and views[buf].origin),
  }
  state.results_buf = buf
  state.rows = rows

  if #rows > 0 then
    pcall(vim.api.nvim_win_set_cursor, win, { first_row + 1, 0 })
  end

  vim.api.nvim_exec_autocmds("User", {
    pattern = "MdResearchResults",
    data = { count = #rows, workspace = ws.name },
  })
  return buf
end

---Load the file of a row.
---@param how "edit"|"split"|"vsplit"|"tabedit"|nil
---@param opts { buf?: integer, index?: integer }|nil
---@return boolean ok, string|nil err
function M.open_row(how, opts)
  opts = opts or {}
  local buf, view = M.find(opts.buf)
  if not view then
    return false, "no result table is open"
  end
  local row, err = M.row(opts.index, buf)
  if not row then
    return false, err
  end
  local cfg = config.get()
  if cfg.on_open then
    local ok, err = pcall(cfg.on_open, row.path, row)
    if not ok then
      util.err("on_open: " .. tostring(err))
    end
  end

  how = how or "edit"
  if how == "edit" then
    local target = view and view.origin
    if target and vim.api.nvim_win_is_valid(target) and target ~= vim.api.nvim_get_current_win() then
      vim.api.nvim_set_current_win(target)
    elseif views[vim.api.nvim_get_current_buf()] then
      vim.cmd("wincmd p")
    end
  end
  vim.cmd(string.format("%s %s", how == "edit" and "edit" or how, vim.fn.fnameescape(row.path)))
  return true
end

---Peek at the head of a row's file in a float.
---@param opts { buf?: integer, index?: integer }|nil
---@return boolean ok, string|nil err
function M.preview_row(opts)
  opts = opts or {}
  local buf = (M.find(opts.buf))
  local row, err = M.row(opts.index, buf)
  if not row then
    return false, err
  end
  local lines = {}
  local fd = io.open(row.path, "r")
  if fd then
    for _ = 1, 40 do
      local line = fd:read("*l")
      if not line then
        break
      end
      lines[#lines + 1] = line
    end
    fd:close()
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "markdown"
  local width = math.min(90, vim.o.columns - 8)
  local height = math.min(#lines + 2, vim.o.lines - 8)
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    width = width,
    height = math.max(height, 3),
    row = 2,
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " " .. row.rel .. " ",
  })
  vim.api.nvim_create_autocmd({ "CursorMoved", "BufLeave" }, {
    buffer = vim.api.nvim_get_current_buf(),
    once = true,
    callback = function()
      pcall(vim.api.nvim_win_close, win, true)
    end,
  })
  return true
end

---@param opts { buf?: integer }|nil
---@return boolean ok, string|nil err
function M.close(opts)
  opts = opts or {}
  local buf, view = M.find(opts.buf)
  if not view then
    return false, "no result table is open"
  end
  local wins = vim.fn.win_findbuf(buf)
  if #wins == 0 then
    return true
  end
  if #wins > 1 or #vim.api.nvim_tabpage_list_wins(0) > 1 then
    pcall(vim.api.nvim_win_close, wins[1], true)
  end
  return true
end

function M.forget(buf)
  views[buf] = nil
end

---Reopen the last result set, if it is still around.
function M.reopen()
  if state.results_buf and vim.api.nvim_buf_is_valid(state.results_buf) then
    local view = views[state.results_buf]
    if view then
      M.open(view.ws, view.query, view.rows)
      return true
    end
  end
  return false
end

return M
