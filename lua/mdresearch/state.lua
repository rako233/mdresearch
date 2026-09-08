--- Session state: current workspace, last query, last result set.
local M = {
  workspace = nil, ---@type string|nil
  query = nil, ---@type table|nil
  raw = nil, ---@type table|nil  last mask input, keyed by field
  modes = nil, ---@type table|nil  last any/all choice, keyed by field
  rows = nil, ---@type table[]|nil
  results_buf = nil, ---@type integer|nil
  mask_buf = nil, ---@type integer|nil
  backend = nil, ---@type string|nil
}

local function state_file()
  return vim.fs.joinpath(vim.fn.stdpath("state"), "mdresearch.json")
end

function M.persist()
  local ok = pcall(function()
    vim.fn.mkdir(vim.fn.stdpath("state"), "p")
    local fd = assert(io.open(state_file(), "w"))
    fd:write(vim.json.encode({ workspace = M.workspace, raw = M.raw, modes = M.modes }))
    fd:close()
  end)
  return ok
end

function M.restore()
  local fd = io.open(state_file(), "r")
  if not fd then
    return
  end
  local body = fd:read("*a")
  fd:close()
  local ok, data = pcall(vim.json.decode, body)
  if ok and type(data) == "table" then
    M.workspace = data.workspace or M.workspace
    M.raw = data.raw
    M.modes = data.modes
  end
end

function M.reset()
  M.query, M.raw, M.modes, M.rows = nil, nil, nil, nil
end

return M
