local tbl = require("mdresearch.ui.table")

local COLS = {
  { key = "title", label = "Title" },
  { key = "tags", label = "Tags" },
  { key = "path", label = "Path" },
}
local ROWS = {
  { path = "/v/a.md", rel = "a.md", fields = { title = "Alpha", tags = { "linux", "server" } } },
  { path = "/v/b.md", rel = "sub/b.md", fields = { title = "A much longer title here", tags = "solo", prio = 3 } },
}

describe("table", function()
  describe("format_value", function()
    it("joins a list", function()
      expect(tbl.format_value({ "a", "b" })).eq("a, b")
    end)

    it("prints an integer without a decimal point", function()
      expect(tbl.format_value(3)).eq("3")
    end)

    it("flattens newlines", function()
      expect(tbl.format_value("a\nb")).eq("a b")
    end)

    it("renders a missing value as empty", function()
      expect(tbl.format_value(nil)).eq("")
    end)
  end)

  describe("cell", function()
    it("uses rel for the virtual path column", function()
      expect(tbl.cell(ROWS[2], { key = "path" })).eq("sub/b.md")
    end)
  end)

  describe("layout", function()
    it("sizes a column to its widest value", function()
      local w = tbl.layout(COLS, ROWS)
      expect(w[1]).eq(#"A much longer title here")
    end)

    it("never goes below the label width", function()
      expect(tbl.layout({ { key = "status", label = "Status" } }, {})[1]).eq(6)
    end)

    it("clamps to a configured width", function()
      local cols = { { key = "title", label = "Title", width = 10 } }
      expect(tbl.layout(cols, ROWS)[1]).eq(10)
    end)

    it("shrinks the widest column to fit the window", function()
      local w = tbl.layout(COLS, ROWS, 40)
      local total = w[1] + w[2] + w[3] + 2 * vim.fn.strdisplaywidth(tbl.SEP)
      expect(total <= 40).truthy()
      expect(w[1] >= tbl.MIN_WIDTH).truthy()
    end)

    it("stops shrinking at the minimum width", function()
      local w = tbl.layout(COLS, ROWS, 5)
      expect(w).eq({ tbl.MIN_WIDTH, tbl.MIN_WIDTH, tbl.MIN_WIDTH })
    end)
  end)

  describe("render", function()
    it("emits a header, a rule and one line per row", function()
      local r = tbl.render(COLS, ROWS)
      expect(#r.lines).eq(4)
      expect(r.first_row).eq(2)
      expect(r.lines[1]).contains("Title")
      expect(r.lines[3]).contains("Alpha")
    end)

    it("can omit the header", function()
      local r = tbl.render(COLS, ROWS, { header = false })
      expect(#r.lines).eq(2)
      expect(r.first_row).eq(0)
    end)

    it("pads every row to the same display width", function()
      local r = tbl.render(COLS, ROWS)
      local w = vim.fn.strdisplaywidth(r.lines[3])
      expect(vim.fn.strdisplaywidth(r.lines[4])).eq(w)
      expect(vim.fn.strdisplaywidth(r.lines[1])).eq(w)
    end)

    it("truncates with an ellipsis instead of overflowing", function()
      local r = tbl.render({ { key = "title", label = "Title", width = 10 } }, ROWS)
      expect(r.lines[4]).contains("…")
      expect(vim.fn.strdisplaywidth(r.lines[4])).eq(10)
    end)

    it("keeps double-width characters inside the column", function()
      local rows = { { rel = "x", fields = { title = "日本語のタイトルです" } } }
      local r = tbl.render({ { key = "title", label = "Title", width = 9 } }, rows)
      expect(vim.fn.strdisplaywidth(r.lines[3])).eq(9)
    end)

    it("reports a highlight span per cell", function()
      local r = tbl.render(COLS, ROWS)
      local titles = vim.tbl_filter(function(s)
        return s.hl == "MdResearchTitle"
      end, r.spans)
      expect(#titles).eq(2)
    end)
  end)
end)
