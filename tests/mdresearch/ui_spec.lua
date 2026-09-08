local config = require("mdresearch.config")
local mask = require("mdresearch.ui.mask")
local results = require("mdresearch.ui.results")
local query = require("mdresearch.query")

local VAULT = TEST_ROOT .. "/tests/fixtures/vault"

local cfg = config.setup({
  workspaces = {
    {
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
    },
  },
  backend = "lua",
})
local WS = cfg.workspaces[1]

describe("mask", function()
  it("renders one line per field plus a text line", function()
    local m = mask.build(WS)
    expect(#m.lines).eq(5)
    expect(m.rows[5].key).eq("__fulltext")
    expect(m.lines[1]).contains("Title")
  end)

  it("shows the configured default mode", function()
    local m = mask.build(WS)
    expect(m.lines[1]).contains("[any]")
    expect(m.lines[2]).contains("[all]")
    expect(m.lines[5]).contains("[all]") -- free text ands by default
  end)

  it("round-trips values through render and read", function()
    local raw = { tags = "linux server", date = ">=2025-01", __fulltext = 'docker "compose file"' }
    local modes = { tags = "all", title = "any" }
    local m = mask.build(WS, raw, modes)
    local back, back_modes = mask.read(m.lines, m.rows)
    expect(back.tags).eq("linux server")
    expect(back.date).eq(">=2025-01")
    expect(back.__fulltext).eq('docker "compose file"')
    expect(back.title).eq("")
    expect(back_modes.tags).eq("all")
    expect(back_modes.title).eq("any")
  end)

  it("keeps a value that contains the separator glyph", function()
    local m = mask.build(WS, { title = "a │ b" })
    local back = mask.read(m.lines, m.rows)
    expect(back.title).eq("a │ b")
  end)

  it("reports where the value column starts", function()
    local m = mask.build(WS)
    local col = mask.value_col(m.lines[1])
    expect(m.lines[1]:sub(col + 1)).eq("")
    expect(col > 0).truthy()
  end)

  it("parses a query out of what it renders", function()
    local m = mask.build(WS, { tags = "linux server", date = "2025-01-01..2025-12-31" }, { tags = "all" })
    local raw, modes = mask.read(m.lines, m.rows)
    local q = assert(query.parse(WS, raw, modes))
    expect(q.fields.tags.mode).eq("all")
    expect(#q.fields.tags.terms).eq(2)
    expect(q.fields.date.terms[1].from).eq(20250101)
  end)
end)

describe("results buffer", function()
  local function run(raw)
    local q = assert(query.parse(WS, raw))
    local rows = assert(require("mdresearch.engine").run_sync(WS, q))
    return q, rows
  end

  it("fills a buffer with the table and maps lines to files", function()
    local q, rows = run({ tags = "journal" })
    local buf = results.open(WS, q, rows)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    expect(#rows).eq(2)
    expect(lines[1]).contains("2 files")
    expect(table.concat(lines, "\n")).contains("Journal entry")

    local view = results.view(buf)
    vim.api.nvim_win_set_cursor(0, { view.first_row + 1, 0 })
    expect(results.row_under_cursor(buf).rel).eq("journal/2025-01-02.md")
    vim.api.nvim_win_set_cursor(0, { view.first_row + 2, 0 })
    expect(results.row_under_cursor(buf).rel).eq("journal/2025-12-31.md")
  end)

  it("puts no file on the header lines", function()
    local q, rows = run({ tags = "journal" })
    local buf = results.open(WS, q, rows)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    expect(results.row_under_cursor(buf)).eq(nil)
  end)

  it("is a read-only scratch buffer", function()
    local q, rows = run({ tags = "journal" })
    local buf = results.open(WS, q, rows)
    expect(vim.bo[buf].modifiable).falsy()
    expect(vim.bo[buf].buftype).eq("nofile")
    expect(vim.bo[buf].filetype).eq("mdresearch-results")
  end)

  it("loads the file under the cursor", function()
    local q, rows = run({ title = "linux server" })
    local buf = results.open(WS, q, rows)
    local view = results.view(buf)
    vim.api.nvim_win_set_cursor(0, { view.first_row + 1, 0 })
    results.open_row("edit")
    expect(vim.api.nvim_buf_get_name(0)).eq(VAULT .. "/linux-server.md")
  end)

  it("says so when nothing matched", function()
    local q, rows = run({ tags = "nothing-matches-this" })
    local buf = results.open(WS, q, rows)
    expect(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]).contains("0 files")
  end)

  it("fires the User MdResearchResults event", function()
    local seen
    vim.api.nvim_create_autocmd("User", {
      pattern = "MdResearchResults",
      once = true,
      callback = function(ev)
        seen = ev.data
      end,
    })
    local q, rows = run({ tags = "journal" })
    results.open(WS, q, rows)
    expect(seen).eq({ count = 2, workspace = "vault" })
  end)
end)

describe("commands", function()
  it("parses :MdResearchSearch arguments", function()
    local raw, modes = require("mdresearch.commands").parse_args(
      'tags="linux server" date=>=2025-01 text=docker'
    )
    expect(raw.tags).eq("linux server")
    expect(raw.date).eq(">=2025-01")
    expect(raw.__fulltext).eq("docker")
    expect(modes).eq({})
  end)

  it("picks up an any:/all: prefix", function()
    local raw, modes = require("mdresearch.commands").parse_args('tags="all: linux server"')
    expect(raw.tags).eq("linux server")
    expect(modes.tags).eq("all")
  end)
end)
