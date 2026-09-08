-- The commands exist from startup, before setup() runs: they are the plugin's
-- command-mode surface, and a command that only appears after setup() cannot
-- be discovered with <Tab>. Nothing else happens here — no config is read, no
-- key is mapped.
if vim.g.loaded_mdresearch then
  return
end
vim.g.loaded_mdresearch = true

require("mdresearch.commands").setup()
