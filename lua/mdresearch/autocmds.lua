local M = {}

M.GROUP = "MdResearch"

function M.setup()
  local group = vim.api.nvim_create_augroup(M.GROUP, { clear = true })
  local keymaps = require("mdresearch.keymaps")
  local mask = require("mdresearch.ui.mask")
  local results = require("mdresearch.ui.results")

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "mdresearch-mask",
    callback = function(ev)
      keymaps.mask(ev.buf)
    end,
  })

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "mdresearch-results",
    callback = function(ev)
      keymaps.results(ev.buf)
    end,
  })

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    callback = function(ev)
      if vim.bo[ev.buf].filetype == "mdresearch-mask" then
        mask.guard_cursor()
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = group,
    callback = function(ev)
      mask.forget(ev.buf)
      results.forget(ev.buf)
    end,
  })

  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      local m = mask.mask()
      if m and m.win and vim.api.nvim_win_is_valid(m.win) then
        local width = math.max(40, math.floor(vim.o.columns * require("mdresearch.config").get().ui.mask.width))
        pcall(vim.api.nvim_win_set_config, m.win, {
          relative = "editor",
          width = width,
          height = #m.lines,
          row = math.max(1, math.floor((vim.o.lines - #m.lines) / 2) - 2),
          col = math.floor((vim.o.columns - width) / 2),
        })
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = { "*.md", "*.markdown" },
    callback = function(ev)
      require("mdresearch.engine.frontmatter").invalidate(vim.api.nvim_buf_get_name(ev.buf))
    end,
  })

  vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    pattern = "global",
    callback = function()
      local ws = require("mdresearch.workspace").detect(vim.fn.getcwd())
      local state = require("mdresearch.state")
      if ws and ws.name ~= state.workspace then
        require("mdresearch.workspace").switch(ws.name)
      end
    end,
  })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      require("mdresearch.ui.highlight").setup()
    end,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      require("mdresearch.state").persist()
    end,
  })
end

return M
