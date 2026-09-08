local parser = require("mdresearch.query.parser")

local TEXT = { key = "tags", type = "text", label = "Tags", list = true, mode = "any" }
local INT = { key = "prio", type = "int", label = "Prio", list = false, mode = "any" }
local DATE = { key = "date", type = "date", label = "Date", list = false, mode = "any" }

describe("parser", function()
  describe("text fields", function()
    it("makes a contains term per value", function()
      local f = parser.field(TEXT, "Linux Server")
      expect(f.mode).eq("any")
      expect(#f.terms).eq(2)
      expect(f.terms[1]).eq({ op = "contains", value = "linux", negate = false })
    end)

    it("understands =exact, /regex/ and !negation", function()
      local f = parser.field(TEXT, '=linux /ser.*r/ !archive')
      expect(f.terms[1].op).eq("exact")
      expect(f.terms[2]).eq({ op = "regex", value = "ser.*r", negate = false })
      expect(f.terms[3]).eq({ op = "contains", value = "archive", negate = true })
    end)

    it("treats #tag as tag", function()
      expect(parser.field(TEXT, "#rust").terms[1].value).eq("rust")
    end)

    it("treats a fully quoted token as a literal", function()
      expect(parser.field(TEXT, '"=linux"').terms[1]).eq({ op = "contains", value = "=linux" })
    end)

    it("returns nil for an empty field", function()
      expect(parser.field(TEXT, "   ")).eq(nil)
    end)
  end)

  describe("modes", function()
    it("takes the mode from the caller", function()
      expect(parser.field(TEXT, "a b", "all").mode).eq("all")
    end)

    it("lets an inline prefix win", function()
      expect(parser.field(TEXT, "all: a b", "any").mode).eq("all")
      expect(parser.field(TEXT, "or: a b", "all").mode).eq("any")
    end)

    it("falls back to the field default", function()
      local spec = vim.tbl_extend("force", {}, TEXT, { mode = "all" })
      expect(parser.field(spec, "a b").mode).eq("all")
    end)
  end)

  describe("int fields", function()
    it("parses equality and comparisons", function()
      local f = parser.field(INT, "3 >=4 <2 1..5")
      expect(f.terms[1]).eq({ op = "eq", value = 3, negate = false })
      expect(f.terms[2]).eq({ op = "between", from = 4, negate = false })
      expect(f.terms[3]).eq({ op = "between", to = 1, negate = false })
      expect(f.terms[4]).eq({ op = "between", from = 1, to = 5, negate = false })
    end)

    it("reports a bad integer", function()
      local f, err = parser.field(INT, "abc")
      expect(f).eq(nil)
      expect(err).contains("Prio")
    end)
  end)

  describe("date fields", function()
    it("expands a partial date into a closed range", function()
      expect(parser.field(DATE, "2025").terms[1]).eq({ op = "between", from = 20250101, to = 20251231, negate = false })
      expect(parser.field(DATE, "2025-02").terms[1]).eq({ op = "between", from = 20250201, to = 20250228, negate = false })
      expect(parser.field(DATE, "2024-02").terms[1].to).eq(20240229) -- leap year
    end)

    it("treats a full date as an exact day", function()
      expect(parser.field(DATE, "2025-01-15").terms[1]).eq({ op = "between", from = 20250115, to = 20250115, negate = false })
    end)

    it("makes >= and after: inclusive", function()
      expect(parser.field(DATE, ">=2025-01-15").terms[1]).eq({ op = "after", from = 20250115, negate = false })
      expect(parser.field(DATE, "after:2025-01-15").terms[1]).eq({ op = "after", from = 20250115, negate = false })
    end)

    it("makes <= and before: inclusive", function()
      expect(parser.field(DATE, "<=2025-01-15").terms[1]).eq({ op = "before", to = 20250115, negate = false })
      expect(parser.field(DATE, "before:2025-01").terms[1]).eq({ op = "before", to = 20250131, negate = false })
    end)

    it("makes > and < exclusive of the whole token", function()
      expect(parser.field(DATE, ">2025-01").terms[1].from).eq(20250201)
      expect(parser.field(DATE, "<2025-02").terms[1].to).eq(20250131)
    end)

    it("parses an inclusive range", function()
      expect(parser.field(DATE, "2025-01-01..2025-03-31").terms[1])
        .eq({ op = "between", from = 20250101, to = 20250331, negate = false })
      expect(parser.field(DATE, "2025-01..2025-03").terms[1].to).eq(20250331)
    end)

    it("rejects a non-ISO date", function()
      local f, err = parser.field(DATE, "15.01.2025")
      expect(f).eq(nil)
      expect(err).contains("Date")
    end)

    it("rejects an impossible date", function()
      expect(parser.parse_date_token("2025-02-30")).eq(nil)
      expect(parser.parse_date_token("2025-13-01")).eq(nil)
    end)
  end)

  describe("value_to_ymd", function()
    for _, case in ipairs({
      { "2025-01-15", 20250115 },
      { "2025-01-15 10:30", 20250115 },
      { "2025-01-15T10:30:00", 20250115 },
      { "2025-01-15-10:30", 20250115 },
      { "not a date", nil },
    }) do
      it("reads " .. case[1], function()
        expect(parser.value_to_ymd(case[1])).eq(case[2])
      end)
    end
  end)

  describe("fulltext", function()
    it("keeps literals verbatim and honours all by default", function()
      local f = parser.fulltext('docker "compose file"')
      expect(f.mode).eq("all")
      expect(f.terms[1].value).eq("docker")
      expect(f.terms[2].value).eq("compose file")
    end)

    it("supports negation", function()
      expect(parser.fulltext("!draft").terms[1]).eq({ op = "contains", value = "draft", negate = true })
    end)
  end)
end)
