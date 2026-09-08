local M = {}

--- Linked to standard groups so the plugin inherits any colourscheme.
M.groups = {
  MdResearchHeader = { link = "Title" },
  MdResearchRule = { link = "Comment" },
  MdResearchTitle = { link = "Identifier" },
  MdResearchCell = { link = "Normal" },
  MdResearchLabel = { link = "Function" },
  MdResearchMode = { link = "Special" },
  MdResearchModeAll = { link = "DiagnosticWarn" },
  MdResearchSeparator = { link = "Comment" },
  MdResearchCount = { link = "Comment" },
  MdResearchHint = { link = "NonText" },
  MdResearchCursorRow = { link = "CursorLine" },
}

function M.setup()
  for name, opts in pairs(M.groups) do
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("keep", { default = true }, opts))
  end
end

return M
