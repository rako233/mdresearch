--- Minimal describe/it/expect harness. No external dependency: the tests run
--- inside the Neovim that ships with the user's setup.
local M = { suites = {}, failures = {}, passed = 0, total = 0, notifications = {} }

local function fmt(v, depth)
  depth = depth or 0
  if type(v) == "string" then
    return string.format("%q", v)
  end
  if type(v) ~= "table" or depth > 4 then
    return tostring(v)
  end
  local keys = {}
  for k in pairs(v) do
    keys[#keys + 1] = k
  end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)
  local parts = {}
  for _, k in ipairs(keys) do
    parts[#parts + 1] = string.format("%s=%s", tostring(k), fmt(v[k], depth + 1))
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end
M.fmt = fmt

local function deep_eq(a, b)
  if a == b then
    return true
  end
  if type(a) ~= "table" or type(b) ~= "table" then
    return false
  end
  for k, v in pairs(a) do
    if not deep_eq(v, b[k]) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end
M.deep_eq = deep_eq

local ctx = { name = "", failed = nil }

local function make_expect(got)
  local E = {}

  function E.eq(want)
    if not deep_eq(got, want) then
      error(string.format("expected %s, got %s", fmt(want), fmt(got)), 2)
    end
  end

  function E.ne(want)
    if deep_eq(got, want) then
      error(string.format("expected something other than %s", fmt(want)), 2)
    end
  end

  function E.truthy()
    if not got then
      error(string.format("expected a truthy value, got %s", fmt(got)), 2)
    end
  end

  function E.falsy()
    if got then
      error(string.format("expected a falsy value, got %s", fmt(got)), 2)
    end
  end

  function E.contains(needle)
    if type(got) == "string" then
      if not got:find(needle, 1, true) then
        error(string.format("expected %s to contain %s", fmt(got), fmt(needle)), 2)
      end
      return
    end
    for _, v in ipairs(got or {}) do
      if deep_eq(v, needle) then
        return
      end
    end
    error(string.format("expected %s to contain %s", fmt(got), fmt(needle)), 2)
  end

  function E.excludes(needle)
    local ok = pcall(E.contains, needle)
    if ok then
      error(string.format("expected %s not to contain %s", fmt(got), fmt(needle)), 2)
    end
  end

  return E
end

function M.expect(got)
  return make_expect(got)
end

function M.describe(name, fn)
  local prev = ctx.name
  ctx.name = prev == "" and name or (prev .. " › " .. name)
  fn()
  ctx.name = prev
end

function M.it(name, fn)
  M.total = M.total + 1
  local label = ctx.name .. " › " .. name
  local ok, err = pcall(fn)
  if ok then
    M.passed = M.passed + 1
    io.write(".")
  else
    io.write("F")
    M.failures[#M.failures + 1] = { name = label, err = tostring(err) }
  end
end

function M.install()
  _G.describe, _G.it, _G.expect = M.describe, M.it, M.expect
end

function M.report()
  io.write("\n\n")
  for _, f in ipairs(M.failures) do
    io.write(string.format("FAIL  %s\n      %s\n\n", f.name, f.err))
  end
  io.write(string.format("%d/%d passed, %d failed\n", M.passed, M.total, #M.failures))
  return #M.failures == 0
end

return M
