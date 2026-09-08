local parser = require("mdresearch.query.parser")
local pred = require("mdresearch.query.predicate")

local TAGS = { key = "tags", type = "text", label = "Tags", list = true, mode = "any" }
local TITLE = { key = "title", type = "text", label = "Title", list = false, mode = "any" }
local PRIO = { key = "prio", type = "int", label = "Prio", list = false, mode = "any" }
local DATE = { key = "date", type = "date", label = "Date", list = false, mode = "any" }
local UPDATED = { key = "updated", type = "datetime", label = "Updated", list = false, mode = "any" }

local function m(spec, input, value, mode)
  local f = assert(parser.field(spec, input, mode))
  return pred.field(f, value)
end

describe("predicate", function()
  describe("list text field", function()
    local tags = { "linux", "server", "Tutorial" }

    it("any matches when one term hits", function()
      expect(m(TAGS, "macos server", tags, "any")).truthy()
    end)

    it("any fails when no term hits", function()
      expect(m(TAGS, "macos windows", tags, "any")).falsy()
    end)

    it("all needs every term to hit some item", function()
      expect(m(TAGS, "linux server", tags, "all")).truthy()
      expect(m(TAGS, "linux macos", tags, "all")).falsy()
    end)

    it("ignores capitalisation on both sides", function()
      expect(m(TAGS, "TUTORIAL", tags, "any")).truthy()
    end)

    it("matches substrings by default and whole items with =", function()
      expect(m(TAGS, "serv", tags, "any")).truthy()
      expect(m(TAGS, "=serv", tags, "any")).falsy()
      expect(m(TAGS, "=server", tags, "any")).truthy()
    end)

    it("negates", function()
      expect(m(TAGS, "!macos", tags, "all")).truthy()
      expect(m(TAGS, "!linux", tags, "all")).falsy()
    end)

    it("handles a quoted multi-word tag", function()
      expect(m(TAGS, '"personal notes"', { "journal", "personal notes" }, "any")).truthy()
    end)

    it("treats a missing field as no match, but a negated term as a match", function()
      expect(m(TAGS, "linux", nil, "any")).falsy()
      expect(m(TAGS, "!linux", nil, "all")).truthy()
    end)
  end)

  describe("scalar text field", function()
    it("requires all terms in the one value under all", function()
      expect(m(TITLE, "linux server", "Linux server setup", "all")).truthy()
      expect(m(TITLE, "linux macos", "Linux server setup", "all")).falsy()
    end)

    it("applies a regex", function()
      expect(m(TITLE, "/ser.*setup/", "Linux server setup", "any")).truthy()
      expect(m(TITLE, "/^setup/", "Linux server setup", "any")).falsy()
    end)
  end)

  describe("int field", function()
    it("compares", function()
      expect(m(PRIO, "3", 3)).truthy()
      expect(m(PRIO, "3", 4)).falsy()
      expect(m(PRIO, ">=3", 5)).truthy()
      expect(m(PRIO, "<2", 1)).truthy()
      expect(m(PRIO, "2..4", 4)).truthy()
      expect(m(PRIO, "2..4", 5)).falsy()
    end)

    it("reads an int stored as a string", function()
      expect(m(PRIO, ">=3", "4")).truthy()
    end)

    it("ors several values", function()
      expect(m(PRIO, "1 5", 5, "any")).truthy()
      expect(m(PRIO, "1 5", 3, "any")).falsy()
    end)
  end)

  describe("date field", function()
    it("matches an exact day", function()
      expect(m(DATE, "2025-01-15", "2025-01-15")).truthy()
      expect(m(DATE, "2025-01-15", "2025-01-16")).falsy()
    end)

    it("matches a whole month or year", function()
      expect(m(DATE, "2025-01", "2025-01-31")).truthy()
      expect(m(DATE, "2025", "2025-12-31")).truthy()
      expect(m(DATE, "2025", "2026-01-01")).falsy()
    end)

    it("includes the boundary on after", function()
      expect(m(DATE, ">=2025-01-15", "2025-01-15")).truthy()
      expect(m(DATE, ">=2025-01-15", "2025-01-14")).falsy()
    end)

    it("includes the boundary on before", function()
      expect(m(DATE, "<=2025-01-15", "2025-01-15")).truthy()
      expect(m(DATE, "<=2025-01-15", "2025-01-16")).falsy()
    end)

    it("includes both boundaries on a range", function()
      expect(m(DATE, "2025-01-01..2025-03-31", "2025-01-01")).truthy()
      expect(m(DATE, "2025-01-01..2025-03-31", "2025-03-31")).truthy()
      expect(m(DATE, "2025-01-01..2025-03-31", "2025-04-01")).falsy()
    end)

    it("ignores the time part of a datetime", function()
      expect(m(UPDATED, "2025-02-01", "2025-02-01 09:30")).truthy()
      expect(m(UPDATED, "2025-02-01", "2025-02-01T23:59:59")).truthy()
      expect(m(UPDATED, "2025-02-01", "2025-02-01-11:45")).truthy()
    end)

    it("does not match an unparseable value", function()
      expect(m(DATE, "2025", "someday")).falsy()
    end)
  end)
end)
