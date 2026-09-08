local fm = require("mdresearch.engine.frontmatter")
local vault = TEST_ROOT .. "/tests/fixtures/vault"

describe("frontmatter", function()
  it("reads a multi-line tag list", function()
    local f = fm.read(vault .. "/linux-server.md")
    expect(f.title).eq("Linux server setup")
    expect(f.tags).eq({ "linux", "server", "tutorial" })
    expect(f.prio).eq(3)
    expect(f.date).eq("2025-01-15")
    expect(f.updated).eq("2025-02-01 09:30")
  end)

  it("reads a flow sequence", function()
    expect(fm.read(vault .. "/macos-notes.md").tags).eq({ "macos", "tutorial" })
  end)

  it("reads inline #tags", function()
    expect(fm.read(vault .. "/projects/rust-cli.md").tags).eq({ "rust", "cli", "tutorial" })
  end)

  it("unquotes a value that contains a colon", function()
    expect(fm.read(vault .. "/projects/mdresearch.md").title).eq("mdresearch: plugin plan")
  end)

  it("keeps a quoted list item with a space", function()
    expect(fm.read(vault .. "/journal/2025-01-02.md").tags).eq({ "journal", "personal notes" })
  end)

  it("reads a block scalar", function()
    local f = fm.read(vault .. "/blockscalar.md")
    expect(f.description).eq("first line\nsecond line")
    expect(f.tags).eq({ "misc" })
  end)

  it("returns nil when there is no frontmatter", function()
    expect(fm.read(vault .. "/no-frontmatter.md")).eq(nil)
  end)

  it("returns nil when the frontmatter is never closed", function()
    expect(fm.read(vault .. "/broken.md")).eq(nil)
  end)

  it("returns nil for a missing file", function()
    expect(fm.read(vault .. "/does-not-exist.md")).eq(nil)
  end)

  describe("parse", function()
    it("strips a trailing comment but keeps a tag list", function()
      expect(fm.parse("a: value # note\nb: #x #y").a).eq("value")
      expect(fm.parse("a: value # note\nb: #x #y").b).eq({ "x", "y" })
    end)

    it("keeps a # inside quotes", function()
      expect(fm.parse('a: "c # d"').a).eq("c # d")
    end)

    it("skips comment lines", function()
      expect(fm.parse("# lead\na: 1").a).eq(1)
    end)

    it("reads a nested map", function()
      expect(fm.parse("meta:\n  author: rako\n  year: 2025").meta).eq({ author = "rako", year = 2025 })
    end)

    it("reads a sequence written at the parent indent", function()
      expect(fm.parse("tags:\n- a\n- b").tags).eq({ "a", "b" })
    end)

    it("survives junk", function()
      expect(type(fm.parse(":::\n\t\t\n"))).eq("table")
    end)
  end)
end)
