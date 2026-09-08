local M = {}

local function ok(msg)
  (vim.health.ok or vim.health.report_ok)(msg)
end
local function warn(msg, advice)
  (vim.health.warn or vim.health.report_warn)(msg, advice)
end
local function err(msg)
  (vim.health.error or vim.health.report_error)(msg)
end
local function start(msg)
  (vim.health.start or vim.health.report_start)(msg)
end

--- The minimum Neovim this plugin is documented against. It is `vim.pack`
--- that sets it, not an API the plugin itself calls, so an older Neovim is
--- reported rather than refused: it will work, it is just not the version
--- the install instructions assume.
M.MIN_VERSION = { 0, 12, 0 }

function M.check()
  start("mdresearch")

  local v = vim.version()
  local have = string.format("%d.%d.%d", v.major, v.minor, v.patch)
  local want = table.concat(M.MIN_VERSION, ".")
  if vim.version.ge(v, M.MIN_VERSION) then
    ok("Neovim " .. have)
  else
    warn(
      string.format("Neovim %s, below the supported %s", have, want),
      { "the plugin should still work; vim.pack, the documented way to install it, needs " .. want }
    )
  end

  local cfg_ok, cfg = pcall(function()
    return require("mdresearch.config").get()
  end)
  if not cfg_ok then
    err("setup() has not been called")
    return
  end
  ok(string.format("configured with %d workspace(s)", #cfg.workspaces))

  start("workspaces")
  for _, ws in ipairs(cfg.workspaces) do
    local st = vim.uv.fs_stat(ws.root)
    if not st then
      err(string.format("%s: root %s does not exist", ws.name, ws.root))
    elseif st.type ~= "directory" then
      err(string.format("%s: root %s is not a directory", ws.name, ws.root))
    else
      ok(string.format("%s: %s (%d fields, glob %s)", ws.name, ws.root, #ws.fields, ws.glob))
    end
  end

  start("external tools")
  local rg = require("mdresearch.engine.rg")
  if rg.available() then
    local res = vim.system({ cfg.rg.cmd, "--version" }, { text = true }):wait()
    ok("ripgrep: " .. (res.stdout or ""):match("^[^\n]*"))
  else
    warn("ripgrep not found", { "the Lua backend falls back to a slower directory walk" })
  end

  local engine = require("mdresearch.engine")
  local picked_ok, picked = pcall(engine.pick)
  if not picked_ok then
    err(tostring(picked))
  else
    if picked.name == "mdrq" then
      ok(string.format("backend: mdrq (%s) — %s", picked.cmd, picked.reason))
    else
      ok(string.format("backend: lua — %s", picked.reason))
      local path = engine.find_mdrq()
      if not path then
        warn("mdrq not built", { "run scripts/build-mdrq.sh for the faster Rust backend" })
      end
    end
  end

  start("commands and mappings")
  local commands = require("mdresearch.commands")
  local created = vim.api.nvim_get_commands({})
  local missing = {}
  for _, name in ipairs(commands.names()) do
    if not created[name] then
      missing[#missing + 1] = name
    end
  end
  if #missing > 0 then
    err("commands not installed: " .. table.concat(missing, ", "))
  else
    ok(string.format("%d commands installed (:MdResearch<Tab>)", #commands.names()))
  end

  local total = 0
  local per_scope = {}
  for _, scope in ipairs({ "global", "mask", "results" }) do
    local n = vim.tbl_count(cfg.keymaps[scope] or {})
    total = total + n
    per_scope[#per_scope + 1] = string.format("%s %d", scope, n)
  end
  if total == 0 then
    ok("no mappings declared — the commands and the Lua API are the surface")
  else
    ok(string.format("%d mappings declared (%s)", total, table.concat(per_scope, ", ")))
  end

  start("cache")
  ok(string.format("%d parsed file(s) cached", require("mdresearch.engine.frontmatter").cache_size()))
end

return M
