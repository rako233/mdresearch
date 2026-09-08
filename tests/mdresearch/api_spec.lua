--- The public surface: the action registry, the commands, the keymap
--- declaration, and the mask/results actions the two of them call.
local actions = require("mdresearch.actions")
local commands = require("mdresearch.commands")
local config = require("mdresearch.config")
local keymaps = require("mdresearch.keymaps")
local mask = require("mdresearch.ui.mask")
local md = require("mdresearch")
local query = require("mdresearch.query")
local results = require("mdresearch.ui.results")

local VAULT = TEST_ROOT .. "/tests/fixtures/vault"

local WS_OPTS = {
  name = "vault",
  root = VAULT,
  fields = {
    { key = "title", type = "text" },
    { key = "tags", type = "text", list = true, mode = "all" },
    { key = "prio", type = "int" },
    { key = "date", type = "date" },
  },
  columns = { "title", "tags", "date", "path" },
  sort = { key = "date" },
}

local function setup(opts)
  return config.setup(vim.tbl_deep_extend("force", {
    workspaces = { WS_OPTS },
    backend = "lua",
    ui = { mask = { insert = false } },
  }, opts or {}))
end

local cfg = setup()
local WS = cfg.workspaces[1]

describe("actions", function()
  it("gives every action a scope, a description and a function", function()
    expect(#actions.list > 0).truthy()
    for _, a in ipairs(actions.list) do
      expect(type(a.name)).eq("string")
      expect(type(a.desc)).eq("string")
      expect(type(a.fn)).eq("function")
      expect(a.scope == "global" or a.scope == "mask" or a.scope == "results").truthy()
      expect(#a.modes > 0).truthy()
    end
  end)

  it("looks actions up by name", function()
    expect(actions.get("mask.submit").scope).eq("mask")
    expect(actions.get("results.vsplit").scope).eq("results")
    expect(actions.get("nope")).eq(nil)
  end)

  it("lists names per scope, sorted", function()
    local names = actions.names("mask")
    expect(names).contains("mask.toggle_mode")
    expect(names).excludes("results.open")
    expect(names[1] < names[2]).truthy()
  end)

  it("covers every command-mode action from the command table", function()
    expect(commands.names()).contains("MdResearchSubmit")
    expect(commands.names()).contains("MdResearchOpen")
    expect(commands.names()).contains("MdResearchActions")
  end)
end)

describe("commands", function()
  it("creates every command in the spec table", function()
    commands.setup()
    local created = vim.api.nvim_get_commands({})
    for _, name in ipairs(commands.names()) do
      expect(created[name] ~= nil).truthy()
    end
  end)

  it("describes each one for :command and completion", function()
    commands.setup()
    local created = vim.api.nvim_get_commands({})
    expect(created["MdResearch"].definition).contains("mdresearch:")
  end)

  it("parses :MdResearchSearch arguments", function()
    local raw, modes = commands.parse_args('tags="linux server" date=>=2025-01 text=docker')
    expect(raw.tags).eq("linux server")
    expect(raw.__fulltext).eq("docker")
    expect(modes).eq({})
  end)
end)

describe("keymaps", function()
  it("maps nothing of its own", function()
    expect(config.defaults.keymaps).eq({ global = {}, mask = {}, results = {} })
  end)

  it("resolves an action name to its default modes", function()
    local modes, rhs, desc = keymaps.resolve("mask", "<CR>", "mask.submit")
    expect(modes).eq({ "n", "i" })
    expect(type(rhs)).eq("function")
    expect(desc).contains("run the search")
  end)

  it("resolves a function and a table form", function()
    local fn = function() end
    local modes, rhs = keymaps.resolve("results", "gx", fn)
    expect(modes).eq({ "n" })
    expect(rhs).eq(fn)

    local modes2, _, desc2 = keymaps.resolve("results", "gy", { "results.split", mode = "x", desc = "mine" })
    expect(modes2).eq({ "x" })
    expect(desc2).eq("mine")
  end)

  it("rejects an unknown action, and one from another scope", function()
    local _, _, _, err = keymaps.resolve("mask", "<CR>", "mask.nope")
    expect(err).contains("unknown action")
    local _, _, _, err2 = keymaps.resolve("mask", "<CR>", "results.open")
    expect(err2).contains("scope")
  end)

  it("is validated at setup time", function()
    local ok, err = pcall(setup, { keymaps = { mask = { ["<CR>"] = "results.open" } } })
    expect(ok).falsy()
    expect(tostring(err)).contains("scope")

    local ok2, err2 = pcall(setup, { keymaps = { enabled = true } })
    expect(ok2).falsy()
    expect(tostring(err2)).contains("unknown key")
    setup()
  end)

  it("sets the declared buffer-local maps", function()
    setup({ keymaps = { results = { ["<CR>"] = "results.open", ["gp"] = "results.preview" } } })
    local buf = vim.api.nvim_create_buf(false, true)
    keymaps.results(buf)
    local lhs = {}
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
      lhs[#lhs + 1] = m.lhs
    end
    expect(lhs).contains("gp")
    vim.api.nvim_buf_delete(buf, { force = true })
    setup()
  end)

  it("hints the mapping when there is one, the command when there is not", function()
    setup()
    expect(mask.hint()).contains(":MdResearchSubmit")
    setup({ keymaps = { mask = { ["<CR>"] = "mask.submit" } } })
    expect(mask.hint()).contains("<CR> search")
    setup()
  end)
end)

describe("mask actions", function()
  local function open(prefill, modes)
    local submitted
    local buf = mask.open(WS, prefill or {}, modes or {}, function(raw, m)
      submitted = { raw = raw, modes = m }
    end)
    return buf, function()
      return submitted
    end
  end

  it("finds the open mask from another window", function()
    local elsewhere = vim.api.nvim_get_current_win()
    local buf = open()
    vim.api.nvim_set_current_win(elsewhere)
    expect(mask.is_open()).truthy()
    expect((mask.find())).eq(buf)
    mask.close({ buf = buf })
    expect(mask.is_open()).falsy()
  end)

  it("forgets a mask buffer that was wiped under it", function()
    local buf = open()
    vim.api.nvim_buf_delete(buf, { force = true })
    expect(mask.is_open()).falsy()
    local ok, err = mask.toggle_mode()
    expect(ok).falsy()
    expect(err).contains("no search mask")
  end)

  it("addresses a field by key, label, alias and index", function()
    local buf = open()
    local m = mask.mask(buf)
    expect((mask.field_index(m, "tags"))).eq(2)
    expect((mask.field_index(m, "Date"))).eq(4)
    expect((mask.field_index(m, "text"))).eq(5)
    expect((mask.field_index(m, 1))).eq(1)
    local _, err = mask.field_index(m, "nope")
    expect(err).contains("no field")
    mask.close({ buf = buf })
  end)

  it("sets, toggles and clears fields without the cursor", function()
    local buf = open()
    expect(mask.set_field("tags", "linux server", { buf = buf })).truthy()
    expect(mask.toggle_mode({ buf = buf, field = "tags" })).truthy()
    local raw, modes = mask.get({ buf = buf })
    expect(raw.tags).eq("linux server")
    expect(modes.tags).eq("any") -- the workspace default is "all"

    expect(mask.set_field("title", "setup", { buf = buf })).truthy()
    expect(mask.clear_field({ buf = buf, field = "tags" })).truthy()
    raw = mask.get({ buf = buf })
    expect(raw.tags).eq("")
    expect(raw.title).eq("setup")

    expect(mask.clear_field({ buf = buf, all = true })).truthy()
    raw = mask.get({ buf = buf })
    expect(raw.title).eq("")
    mask.close({ buf = buf })
  end)

  it("moves the cursor by name and by direction", function()
    local buf = open()
    local win = mask.mask(buf).win
    expect(mask.focus_field("date", { buf = buf })).truthy()
    expect(vim.api.nvim_win_get_cursor(win)[1]).eq(4)
    mask.focus_field("next", { buf = buf })
    expect(vim.api.nvim_win_get_cursor(win)[1]).eq(5)
    mask.focus_field("next", { buf = buf }) -- wraps
    expect(vim.api.nvim_win_get_cursor(win)[1]).eq(1)
    mask.focus_field("prev", { buf = buf })
    expect(vim.api.nvim_win_get_cursor(win)[1]).eq(5)
    mask.focus_field("first", { buf = buf })
    expect(vim.api.nvim_win_get_cursor(win)[1]).eq(1)
    -- the cursor never sits in the label column
    expect(vim.api.nvim_win_get_cursor(win)[2] > 0).truthy()
    mask.close({ buf = buf })
  end)

  it("submits from another window and closes itself", function()
    local elsewhere = vim.api.nvim_get_current_win()
    local buf, submitted = open({ tags = "journal" }, { tags = "all" })
    vim.api.nvim_set_current_win(elsewhere)
    expect(mask.submit({ buf = buf })).truthy()
    expect(submitted().raw.tags).eq("journal")
    expect(submitted().modes.tags).eq("all")
    expect(mask.is_open(buf)).falsy()
  end)

  it("says so when no mask is open", function()
    local ok, err = mask.submit()
    expect(ok).falsy()
    expect(err).contains("no search mask")
  end)
end)

describe("results actions", function()
  local function table_of(raw)
    local q = assert(query.parse(WS, raw))
    local rows = assert(require("mdresearch.engine").run_sync(WS, q))
    return results.open(WS, q, rows), rows
  end

  it("addresses a row by index", function()
    local buf, rows = table_of({ tags = "journal" })
    expect(#md.results.rows({ buf = buf })).eq(#rows)
    expect(md.results.row(1, { buf = buf }).rel).eq("journal/2025-01-02.md")
    expect(md.results.row(2, { buf = buf }).rel).eq("journal/2025-12-31.md")
    local row, err = results.row(99, buf)
    expect(row).eq(nil)
    expect(err).contains("no row #99")
  end)

  it("loads a row named by index, from another window", function()
    local buf = table_of({ tags = "journal" })
    local other = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(other)
    expect(results.open_row("edit", { buf = buf, index = 2 })).truthy()
    expect(vim.api.nvim_buf_get_name(0)).contains("journal/2025-12-31.md")
  end)

  it("reports an empty line instead of loading the wrong file", function()
    local buf = table_of({ tags = "journal" })
    local win = vim.fn.win_findbuf(buf)[1]
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
    local ok, err = results.open_row("edit", { buf = buf })
    expect(ok).falsy()
    expect(err).contains("no file on this line")
  end)

  it("reopens a table whose window was closed", function()
    local buf = table_of({ tags = "journal" })
    expect(results.is_open(buf)).truthy()
    results.close({ buf = buf })
    expect(results.is_open(buf)).falsy()
    expect(results.reopen()).truthy()
    expect(results.is_open()).truthy()
    -- the same buffer comes back, so its name is never taken twice
    expect((results.find())).eq(buf)
  end)
end)

describe("status", function()
  it("reports the workspace and the last result count", function()
    require("mdresearch.workspace").switch("vault")
    local q = assert(query.parse(WS, { tags = "journal" }))
    results.open(WS, q, assert(require("mdresearch.engine").run_sync(WS, q)))
    local st = md.status()
    expect(st.workspace).eq("vault")
    expect(st.results).eq(2)
  end)
end)
