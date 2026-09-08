local link = require("mdresearch.link")

local function row(rel, fields)
  return { path = "/vault/" .. rel, rel = rel, fields = fields or {} }
end

describe("link", function()
  describe("markdown", function()
    it("labels with the title field and targets the relative path", function()
      local r = row("projects/rust-cli.md", { title = "Rust CLI patterns" })
      expect(link.render(r)).eq("[Rust CLI patterns](projects/rust-cli.md)")
    end)

    it("falls back to the file stem when the title is missing or empty", function()
      expect(link.render(row("journal/2025-01-02.md"))).eq("[2025-01-02](journal/2025-01-02.md)")
      expect(link.render(row("a/b.md", { title = "" }))).eq("[b](a/b.md)")
    end)

    it("uses another field as the label, or the stem when asked", function()
      local r = row("a/b.md", { title = "T", status = "draft" })
      expect(link.render(r, { label = "status" })).eq("[draft](a/b.md)")
      expect(link.render(r, { label = false })).eq("[b](a/b.md)")
    end)

    it("takes the first item of a list-valued label", function()
      expect(link.render(row("a/b.md", { title = { "First", "Second" } }))).eq("[First](a/b.md)")
    end)

    it("brackets a target that would break the link", function()
      expect(link.render(row("my notes/a b.md"))).eq("[a b](<my notes/a b.md>)")
      expect(link.render(row("a(1).md"))).eq("[a(1)](<a(1).md>)")
    end)

    it("escapes brackets in the label", function()
      expect(link.render(row("a.md", { title = "see [1]" }))).eq("[see \\[1\\]](a.md)")
    end)

    it("keeps a colon in the label, which needs no escaping", function()
      local r = row("projects/mdresearch.md", { title = "mdresearch: plugin plan" })
      expect(link.render(r)).eq("[mdresearch: plugin plan](projects/mdresearch.md)")
    end)
  end)

  describe("wiki", function()
    it("wraps the relative path", function()
      expect(link.render(row("a/b.md"), { format = "wiki" })).eq("[[a/b.md]]")
    end)

    it("drops the extension when ext is false", function()
      expect(link.render(row("a/b.md"), { format = "wiki", ext = false })).eq("[[a/b]]")
    end)
  end)

  describe("path", function()
    it("is the bare relative path", function()
      expect(link.render(row("a/b.md"), { format = "path" })).eq("a/b.md")
      expect(link.render(row("a/b.md"), { format = "path", ext = false })).eq("a/b")
    end)
  end)

  describe("ext = false", function()
    it("only strips the last extension, and only from the file name", function()
      expect(link.render(row("a.b/c.tar.md"), { format = "path", ext = false })).eq("a.b/c.tar")
      expect(link.render(row("a.b/c"), { format = "path", ext = false })).eq("a.b/c")
    end)
  end)

  it("rejects an unknown format instead of guessing", function()
    local text, err = link.render(row("a.md"), { format = "org" })
    expect(text).eq(nil)
    expect(err).contains("unknown link format")
  end)
end)

describe("link edge cases", function()
  local function row(rel, fields)
    return { path = "/vault/" .. rel, rel = rel, fields = fields or {} }
  end

  it("escapes angle brackets in a target rather than dropping them", function()
    expect(link.render(row("a<b>.md"))).eq("[a<b>](<a\\<b\\>.md>)")
  end)

  it("keeps a boolean-valued label field", function()
    expect(link.render(row("a.md", { title = false }))).eq("[false](a.md)")
  end)

  it("leaves a target with no special character unbracketed", function()
    expect(link.render(row("a-b_c.1.md"))).eq("[a-b_c.1](a-b_c.1.md)")
  end)
end)
