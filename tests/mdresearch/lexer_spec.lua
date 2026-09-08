local lexer = require("mdresearch.query.lexer")

describe("lexer", function()
  it("splits on whitespace", function()
    expect(lexer.split("linux server")).eq({ "linux", "server" })
  end)

  it("keeps a quoted value atomic", function()
    expect(lexer.split('linux "personal notes" rust')).eq({ "linux", "personal notes", "rust" })
  end)

  it("supports single quotes", function()
    expect(lexer.split("a 'b c'")).eq({ "a", "b c" })
  end)

  it("tolerates an unterminated quote", function()
    expect(lexer.split('a "b c')).eq({ "a", "b c" })
  end)

  it("allows a quote in the middle of a token", function()
    expect(lexer.split('="a b" c')).eq({ "=a b", "c" })
  end)

  it("flags tokens that start with a quote", function()
    local toks = lexer.tokens('"=a" =b')
    expect(toks[1]).eq({ text = "=a", quoted = true })
    expect(toks[2]).eq({ text = "=b", quoted = false })
  end)

  it("collapses runs of whitespace", function()
    expect(lexer.split("  a \t b  ")).eq({ "a", "b" })
  end)

  it("returns nothing for an empty string", function()
    expect(lexer.split("   ")).eq({})
  end)
end)
