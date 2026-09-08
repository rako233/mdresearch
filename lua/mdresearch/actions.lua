--- The action registry: every named thing the plugin can do.
---
--- One table, three consumers — `mdresearch.commands` (Ex commands),
--- `mdresearch.keymaps` (the maps *you* declare) and `:checkhealth`. A name
--- here is stable API: it is what you write in `keymaps`, and what
--- `doc/mdresearch.txt` documents.
local M = {}

---@class MdResearchAction
---@field name string
---@field scope "global"|"mask"|"results"
---@field desc string
---@field modes string[]  default modes when the action is mapped
---@field fn fun()

local function md()
  return require("mdresearch")
end

local NORMAL = { "n" }
local BOTH = { "n", "i" }

---@type MdResearchAction[]
M.list = {
  -- global -----------------------------------------------------------------
  {
    name = "open",
    scope = "global",
    desc = "open the search mask",
    modes = NORMAL,
    fn = function()
      md().open()
    end,
  },
  {
    name = "resume",
    scope = "global",
    desc = "reopen the mask with the last query",
    modes = NORMAL,
    fn = function()
      md().resume()
    end,
  },
  {
    name = "last",
    scope = "global",
    desc = "reopen the last result table",
    modes = NORMAL,
    fn = function()
      md().last()
    end,
  },
  {
    name = "close",
    scope = "global",
    desc = "close the mask, or the result table",
    modes = NORMAL,
    fn = function()
      md().close()
    end,
  },
  {
    name = "workspace",
    scope = "global",
    desc = "pick a workspace",
    modes = NORMAL,
    fn = function()
      md().workspace()
    end,
  },
  {
    name = "workspace.next",
    scope = "global",
    desc = "switch to the next workspace",
    modes = NORMAL,
    fn = function()
      md().workspace_next()
    end,
  },
  {
    name = "workspace.prev",
    scope = "global",
    desc = "switch to the previous workspace",
    modes = NORMAL,
    fn = function()
      md().workspace_prev()
    end,
  },
  {
    name = "reload",
    scope = "global",
    desc = "clear caches and re-detect the backend",
    modes = NORMAL,
    fn = function()
      md().reload()
    end,
  },
  {
    name = "health",
    scope = "global",
    desc = "run the health check",
    modes = NORMAL,
    fn = function()
      md().health()
    end,
  },

  -- mask -------------------------------------------------------------------
  {
    name = "mask.submit",
    scope = "mask",
    desc = "run the search",
    modes = BOTH,
    fn = function()
      md().mask.submit()
    end,
  },
  {
    name = "mask.cancel",
    scope = "mask",
    desc = "close the mask",
    modes = NORMAL,
    fn = function()
      md().mask.cancel()
    end,
  },
  {
    name = "mask.toggle_mode",
    scope = "mask",
    desc = "flip any/all on this field",
    modes = BOTH,
    fn = function()
      md().mask.toggle_mode()
    end,
  },
  {
    name = "mask.clear_field",
    scope = "mask",
    desc = "empty this field",
    modes = BOTH,
    fn = function()
      md().mask.clear_field()
    end,
  },
  {
    name = "mask.clear_all",
    scope = "mask",
    desc = "empty every field",
    modes = BOTH,
    fn = function()
      md().mask.clear_field({ all = true })
    end,
  },
  {
    name = "mask.next_field",
    scope = "mask",
    desc = "cursor to the next field",
    modes = BOTH,
    fn = function()
      md().mask.focus_field("next")
    end,
  },
  {
    name = "mask.prev_field",
    scope = "mask",
    desc = "cursor to the previous field",
    modes = BOTH,
    fn = function()
      md().mask.focus_field("prev")
    end,
  },

  -- results ----------------------------------------------------------------
  {
    name = "results.open",
    scope = "results",
    desc = "load the file on this line",
    modes = NORMAL,
    fn = function()
      md().results.open("edit")
    end,
  },
  {
    name = "results.split",
    scope = "results",
    desc = "load it in a split",
    modes = NORMAL,
    fn = function()
      md().results.open("split")
    end,
  },
  {
    name = "results.vsplit",
    scope = "results",
    desc = "load it in a vertical split",
    modes = NORMAL,
    fn = function()
      md().results.open("vsplit")
    end,
  },
  {
    name = "results.tab",
    scope = "results",
    desc = "load it in a new tab",
    modes = NORMAL,
    fn = function()
      md().results.open("tabedit")
    end,
  },
  {
    name = "results.preview",
    scope = "results",
    desc = "preview the file on this line",
    modes = NORMAL,
    fn = function()
      md().results.preview()
    end,
  },
  {
    name = "results.yank_link",
    scope = "results",
    desc = "copy a link to this file, relative to the workspace",
    modes = NORMAL,
    fn = function()
      md().results.yank_link()
    end,
  },
  {
    name = "results.refine",
    scope = "results",
    desc = "reopen the mask with this query",
    modes = NORMAL,
    fn = function()
      md().results.refine()
    end,
  },
  {
    name = "results.close",
    scope = "results",
    desc = "close the result table",
    modes = NORMAL,
    fn = function()
      md().results.close()
    end,
  },
}

---@type table<string, MdResearchAction>
M.by_name = {}
for _, a in ipairs(M.list) do
  M.by_name[a.name] = a
end

---@param name string
---@return MdResearchAction|nil
function M.get(name)
  return M.by_name[name]
end

---Action names, sorted; `scope` narrows the list.
---@param scope "global"|"mask"|"results"|nil
---@return string[]
function M.names(scope)
  local out = {}
  for _, a in ipairs(M.list) do
    if not scope or a.scope == scope then
      out[#out + 1] = a.name
    end
  end
  table.sort(out)
  return out
end

return M
