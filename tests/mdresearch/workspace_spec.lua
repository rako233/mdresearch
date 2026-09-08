local config = require("mdresearch.config")
local state = require("mdresearch.state")
local workspace = require("mdresearch.workspace")

local VAULT = TEST_ROOT .. "/tests/fixtures/vault"

config.setup({
  workspaces = {
    { name = "notes", root = VAULT, fields = { { key = "title", type = "text" } } },
    { name = "journal", root = VAULT .. "/journal", fields = { { key = "title", type = "text" } } },
    { name = "other", root = "/nonexistent/elsewhere", fields = { { key = "title", type = "text" } } },
  },
  default_workspace = "notes",
})

describe("workspace", function()
  it("starts on the default", function()
    state.workspace = nil
    expect(workspace.current().name).eq("notes")
  end)

  it("switches by name", function()
    expect(workspace.switch("journal")).truthy()
    expect(workspace.current().name).eq("journal")
  end)

  it("refuses an unknown name", function()
    expect(workspace.switch("nope")).falsy()
    expect(workspace.current().name).eq("journal")
  end)

  it("cycles", function()
    workspace.switch("notes")
    workspace.cycle(1)
    expect(workspace.current().name).eq("journal")
    workspace.cycle(-1)
    expect(workspace.current().name).eq("notes")
    workspace.cycle(-1)
    expect(workspace.current().name).eq("other")
  end)

  it("fires User MdResearchWorkspaceChanged on a real switch", function()
    workspace.switch("notes")
    local seen = {}
    local id = vim.api.nvim_create_autocmd("User", {
      pattern = "MdResearchWorkspaceChanged",
      callback = function(ev)
        seen[#seen + 1] = ev.data.workspace
      end,
    })
    workspace.switch("journal")
    workspace.switch("journal") -- already current: no second event
    vim.api.nvim_del_autocmd(id)
    expect(seen).eq({ "journal" })
  end)

  it("detects the innermost workspace containing a path", function()
    expect(workspace.detect(VAULT .. "/journal/2025-01-02.md").name).eq("journal")
    expect(workspace.detect(VAULT .. "/projects").name).eq("notes")
    expect(workspace.detect("/tmp")).eq(nil)
  end)

  it("does not confuse a sibling directory with a prefix match", function()
    expect(workspace.detect(VAULT .. "-other/x.md")).eq(nil)
  end)

  it("forgets the last query when the workspace changes", function()
    workspace.switch("notes")
    state.raw = { title = "x" }
    workspace.switch("journal")
    expect(state.raw).eq(nil)
  end)
end)
