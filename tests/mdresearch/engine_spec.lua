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
    {
      name = "no-archive",
      root = VAULT,
      exclude = { "archive/**" },
      fields = { { key = "tags", type = "text", list = true } },
    },
  },
  backend = "lua",
})
local WS = cfg.workspaces[1]
local WS_EX = cfg.workspaces[2]

---Run a raw mask input and return the relative paths that matched.
local function search(raw, modes, ws, opts)
  local q = assert(query.parse(ws or WS, raw, modes))
  local rows, err = engine.run_sync(ws or WS, q, opts)
  assert(not err, tostring(err))
  local out = {}
  for _, r in ipairs(rows) do
    out[#out + 1] = r.rel
  end
  table.sort(out)
  return out
end

---Every query must give the same answer with the ripgrep prefilter disabled.
local function both(raw, modes, ws)
  local with = search(raw, modes, ws, { prefilter = true })
  local without = search(raw, modes, ws, { prefilter = false })
  expect(without).eq(with)
  return with
end

describe("engine (lua backend)", function()
  it("returns every parseable note for an empty query", function()
    expect(both({})).eq({
      "archive/old.md",
      "blockscalar.md",
      "journal/2025-01-02.md",
      "journal/2025-12-31.md",
      "linux-server.md",
      "macos-notes.md",
      "projects/mdresearch.md",
      "projects/rust-cli.md",
    })
  end)

  it("skips files without usable frontmatter", function()
    local all = both({})
    expect(all).excludes("no-frontmatter.md")
    expect(all).excludes("broken.md")
  end)

  it("filters a list field with or", function()
    expect(both({ tags = "macos rust" }, { tags = "any" })).eq({ "macos-notes.md", "projects/mdresearch.md", "projects/rust-cli.md" })
  end)

  it("filters a list field with and", function()
    expect(both({ tags = "linux server" }, { tags = "all" })).eq({ "linux-server.md" })
    expect(both({ tags = "linux archive" }, { tags = "all" })).eq({ "archive/old.md" })
  end)

  it("ignores capitalisation", function()
    expect(both({ tags = "LINUX" })).eq({ "archive/old.md", "linux-server.md" })
  end)

  it("matches a quoted tag containing a space", function()
    expect(both({ tags = '"personal notes"' })).eq({ "journal/2025-01-02.md" })
  end)

  it("combines fields with and", function()
    expect(both({ tags = "linux", status = "published" })).eq({ "linux-server.md" })
  end)

  it("negates a value", function()
    expect(both({ tags = "linux !archive" }, { tags = "all" })).eq({ "linux-server.md" })
  end)

  it("filters an int field by range", function()
    expect(both({ prio = ">=4" })).eq({ "projects/mdresearch.md", "projects/rust-cli.md" })
  end)

  it("finds an exact date", function()
    expect(both({ date = "2025-01-15" })).eq({ "linux-server.md" })
  end)

  it("finds everything on or after a date", function()
    expect(both({ date = ">=2025-06-10" })).eq({ "journal/2025-12-31.md", "projects/mdresearch.md" })
  end)

  it("finds everything on or before a date", function()
    expect(both({ date = "<=2025-01-15" })).eq({ "archive/old.md", "journal/2025-01-02.md", "linux-server.md", "projects/rust-cli.md" })
  end)

  it("finds a closed range, both bounds included", function()
    expect(both({ date = "2025-01-02..2025-01-15" })).eq({ "journal/2025-01-02.md", "linux-server.md" })
  end)

  it("expands a partial date to the whole month", function()
    expect(both({ date = "2025-01" })).eq({ "journal/2025-01-02.md", "linux-server.md" })
  end)

  it("searches a datetime field by date alone", function()
    expect(both({ updated = "2025-06-11" })).eq({ "projects/mdresearch.md" })
    expect(both({ updated = "2025-03-02" })).eq({ "macos-notes.md" })
  end)

  it("runs a full-text search over the body", function()
    expect(both({ __fulltext = "docker" })).eq({ "linux-server.md", "projects/mdresearch.md" })
  end)

  it("ands full-text terms by default", function()
    expect(both({ __fulltext = "docker ripgrep" })).eq({ "projects/mdresearch.md" })
    expect(both({ __fulltext = "docker ripgrep" }, { __fulltext = "any" }))
      .eq({ "linux-server.md", "projects/mdresearch.md" })
  end)

  it("combines full text with metadata", function()
    expect(both({ tags = "linux", __fulltext = "docker" })).eq({ "linux-server.md" })
  end)

  it("honours the workspace exclude globs", function()
    expect(both({ tags = "linux" }, nil, WS_EX)).eq({ "linux-server.md" })
  end)

  it("sorts by the workspace sort key", function()
    local q = assert(query.parse(WS, { tags = "journal" }))
    local rows = assert(engine.run_sync(WS, q))
    expect(rows[1].rel).eq("journal/2025-01-02.md")
    expect(rows[2].rel).eq("journal/2025-12-31.md")
  end)

  it("returns the field values needed by the table", function()
    local q = assert(query.parse(WS, { title = "linux server" }))
    local rows = assert(engine.run_sync(WS, q))
    expect(#rows).eq(1)
    expect(rows[1].fields.tags).eq({ "linux", "server", "tutorial" })
    expect(rows[1].fields.prio).eq(3)
    expect(rows[1].path).eq(VAULT .. "/linux-server.md")
  end)

  it("caps the result count at config.limit", function()
    local saved = cfg.limit
    cfg.limit = 2
    local rows = assert(engine.run_sync(WS, assert(query.parse(WS, {}))))
    cfg.limit = saved
    expect(#rows).eq(2)
  end)
end)
