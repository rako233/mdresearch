local config = require("mdresearch.config")

local function ws(extra)
  return vim.tbl_extend("force", {
    name = "notes",
    root = TEST_ROOT .. "/tests/fixtures/vault",
    fields = { { key = "title", type = "text" }, { key = "tags", type = "text", list = true } },
  }, extra or {})
end

local function bad(opts)
  local ok, err = pcall(config.normalize, opts)
  expect(ok).falsy()
  return tostring(err)
end

describe("config", function()
  it("accepts a full configuration", function()
    local cfg = config.normalize({
      workspaces = {
        ws({ glob = "**/*.md", exclude = { "archive/**" }, sort = { key = "title", desc = true } }),
      },
      backend = "lua",
      limit = 10,
    })
    expect(cfg.workspaces[1].name).eq("notes")
    expect(cfg.default_workspace).eq("notes")
    expect(cfg.workspaces[1].sort).eq({ key = "title", desc = true })
    expect(cfg.limit).eq(10)
  end)

  it("indexes fields by key and defaults their labels", function()
    local w = config.normalize({ workspaces = { ws() } }).workspaces[1]
    expect(w.by_key.tags.list).truthy()
    expect(w.by_key.title.label).eq("Title")
    expect(w.by_key.title.mode).eq("any")
  end)

  it("defaults the columns to every field plus path", function()
    local w = config.normalize({ workspaces = { ws() } }).workspaces[1]
    expect(#w.columns).eq(3)
    expect(w.columns[3].key).eq("path")
  end)

  it("accepts columns given as bare strings", function()
    local w = config.normalize({ workspaces = { ws({ columns = { "title", "path" } }) } }).workspaces[1]
    expect(w.columns[1].label).eq("Title")
  end)

  it("expands ~ in the root", function()
    local w = config.normalize({ workspaces = { ws({ root = "~/notes" }) } }).workspaces[1]
    expect(w.root:sub(1, 1)).eq("/")
  end)

  it("rejects an unknown top-level key", function()
    expect(bad({ workspaces = { ws() }, workspacse = {} })).contains("unknown key")
  end)

  it("rejects an unknown field type", function()
    expect(bad({ workspaces = { ws({ fields = { { key = "a", type = "float" } } }) } })).contains("unknown type")
  end)

  it("rejects a workspace without a root", function()
    expect(bad({ workspaces = { { name = "x" } } })).contains("root")
  end)

  it("rejects duplicate workspace names", function()
    expect(bad({ workspaces = { ws(), ws() } })).contains("duplicate")
  end)

  it("rejects a duplicated field key", function()
    local w = ws({ fields = { { key = "a" }, { key = "a" } } })
    expect(bad({ workspaces = { w } })).contains("twice")
  end)

  it("rejects a column that is not a field", function()
    expect(bad({ workspaces = { ws({ columns = { "nope" } }) } })).contains("not a field")
  end)

  it("rejects an unknown backend", function()
    expect(bad({ workspaces = { ws() }, backend = "grep" })).contains("backend")
  end)

  it("rejects a default_workspace that does not exist", function()
    expect(bad({ workspaces = { ws() }, default_workspace = "other" })).contains("default_workspace")
  end)

  it("rejects an empty workspace list", function()
    expect(bad({ workspaces = {} })).contains("at least one workspace")
  end)

  it("rejects a bad field mode", function()
    expect(bad({ workspaces = { ws({ fields = { { key = "a", mode = "maybe" } } }) } })).contains("mode")
  end)
end)

describe("link options", function()
  it("defaults to a markdown link labelled by title", function()
    local cfg = config.normalize({ workspaces = { ws() } })
    expect(cfg.ui.results.link.format).eq("markdown")
    expect(cfg.ui.results.link.label).eq("title")
    expect(cfg.ui.results.link.ext).eq(true)
  end)

  it("rejects an unknown format at setup time", function()
    expect(bad({ workspaces = { ws() }, ui = { results = { link = { format = "org" } } } }))
      .contains("ui.results.link.format")
  end)

  it("keeps label = false, which means the file stem", function()
    local cfg = config.normalize({
      workspaces = { ws() },
      ui = { results = { link = { label = false, ext = false } } },
    })
    expect(cfg.ui.results.link.label).eq(false)
    expect(cfg.ui.results.link.ext).eq(false)
  end)
end)

describe("config option keys", function()
  it("accepts every key whose default is nil", function()
    local cfg = config.normalize({
      workspaces = { ws() },
      default_workspace = "notes",
      on_open = function() end,
    })
    expect(cfg.default_workspace).eq("notes")
    expect(type(cfg.on_open)).eq("function")
  end)

  it("lists the accepted keys when it rejects one", function()
    local ok, err = pcall(config.normalize, { workspaces = { ws() }, nope = 1 })
    expect(ok).falsy()
    expect(tostring(err)).contains("default_workspace")
  end)
end)
