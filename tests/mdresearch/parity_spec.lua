--- The Lua backend is normative; this proves mdrq agrees with it.
---
--- Every query is run through both engines and the rows are compared field by
--- field. Regex terms are deliberately absent: `/re/` is a Lua pattern in the
--- Lua backend and an RE2 pattern in mdrq, which is documented in
--- doc/mdresearch.txt — the two only agree on the common subset.
local config = require("mdresearch.config")
local engine = require("mdresearch.engine")
local query = require("mdresearch.query")

local VAULT = TEST_ROOT .. "/tests/fixtures/vault"

local cfg = config.setup({
  workspaces = {
    {
      name = "vault",
      root = VAULT,
      fields = {
        { key = "title", type = "text" },
        { key = "tags", type = "text", list = true },
        { key = "status", type = "text" },
        { key = "prio", type = "int" },
        { key = "date", type = "date" },
        { key = "updated", type = "datetime" },
      },
      sort = { key = "date" },
    },
    { name = "no-archive", root = VAULT, exclude = { "archive/**" }, fields = { { key = "tags", type = "text", list = true } } },
    {
      name = "desc",
      root = VAULT,
      fields = { { key = "title", type = "text" }, { key = "prio", type = "int" } },
      sort = { key = "prio", desc = true },
    },
  },
  backend = "lua",
})

local CASES = {
  { name = "everything", raw = {} },
  { name = "tags or", raw = { tags = "macos rust" }, modes = { tags = "any" } },
  { name = "tags and", raw = { tags = "linux server" }, modes = { tags = "all" } },
  { name = "tags negated", raw = { tags = "linux !archive" }, modes = { tags = "all" } },
  { name = "tag exact", raw = { tags = "=linux" } },
  { name = "quoted tag", raw = { tags = '"personal notes"' } },
  { name = "capitalisation", raw = { tags = "LINUX" } },
  { name = "two fields", raw = { tags = "linux", status = "published" } },
  { name = "title substring", raw = { title = "linux server" }, modes = { title = "all" } },
  { name = "int range", raw = { prio = ">=4" } },
  { name = "int list", raw = { prio = "1 5" }, modes = { prio = "any" } },
  { name = "date exact", raw = { date = "2025-01-15" } },
  { name = "date month", raw = { date = "2025-01" } },
  { name = "date year", raw = { date = "2025" } },
  { name = "date after", raw = { date = ">=2025-06-10" } },
  { name = "date before", raw = { date = "<=2025-01-15" } },
  { name = "date between", raw = { date = "2025-01-02..2025-01-15" } },
  { name = "datetime", raw = { updated = "2025-06-11" } },
  { name = "fulltext one", raw = { __fulltext = "docker" } },
  { name = "fulltext and", raw = { __fulltext = "docker ripgrep" } },
  { name = "fulltext or", raw = { __fulltext = "docker ripgrep" }, modes = { __fulltext = "any" } },
  { name = "fulltext negated", raw = { tags = "tutorial", __fulltext = "!docker" } },
  { name = "fulltext and metadata", raw = { tags = "linux", __fulltext = "docker" } },
  { name = "no match", raw = { tags = "nothing-here" } },
}

local function shape(rows)
  local out = {}
  for _, r in ipairs(rows) do
    out[#out + 1] = { rel = r.rel, fields = r.fields }
  end
  return out
end

local mdrq = engine.find_mdrq()

describe("backend parity", function()
  if not mdrq then
    it("SKIPPED: no mdrq binary (run scripts/build-mdrq.sh)", function() end)
    return
  end

  for _, ws in ipairs(cfg.workspaces) do
    for _, case in ipairs(CASES) do
      local applicable = true
      for key in pairs(case.raw) do
        if key ~= "__fulltext" and not ws.by_key[key] then
          applicable = false
        end
      end
      if applicable then
        it(string.format("%s / %s", ws.name, case.name), function()
          local q = assert(query.parse(ws, case.raw, case.modes))
          local a, ea = engine.run_sync(ws, q, { backend = "lua" })
          local b, eb = engine.run_sync(ws, q, { backend = "mdrq" })
          expect(ea).eq(nil)
          expect(eb).eq(nil)
          expect(shape(b)).eq(shape(a))
        end)
      end
    end
  end

  it("reports the same protocol the plugin expects", function()
    local res = vim.system({ mdrq, "--protocol" }, { text = true }):wait()
    expect(tonumber(vim.trim(res.stdout))).eq(engine.PROTOCOL)
  end)

  it("is selected automatically when it is present", function()
    config.options.backend = "auto"
    engine.reset()
    local picked = engine.pick()
    config.options.backend = "lua"
    engine.reset()
    expect(picked.name).eq("mdrq")
  end)
end)
