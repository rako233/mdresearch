-- nvim --headless -l tests/run.lua [pattern]
local root = vim.fn.fnamemodify(vim.fn.resolve(debug.getinfo(1, "S").source:sub(2)), ":p:h:h")
vim.opt.runtimepath:prepend(root)
package.path = root .. "/tests/?.lua;" .. package.path

local harness = require("harness")
harness.install()
_G.TEST_ROOT = root

local pattern = arg and arg[1] or nil
local specs = vim.fn.globpath(root .. "/tests/mdresearch", "*_spec.lua", false, true)
table.sort(specs)

-- Notifications are UX, not test output; keep them out of the report but
-- reachable through harness.notifications.
vim.notify = function(msg, level)
  harness.notifications[#harness.notifications + 1] = { msg = msg, level = level }
end

for _, spec in ipairs(specs) do
  if not pattern or spec:find(pattern, 1, true) then
    -- Specs each install their own config; make sure none of them inherits a
    -- current workspace from the file before it.
    require("mdresearch.state").workspace = nil
    harness.notifications = {}
    local ok, err = pcall(dofile, spec)
    if not ok then
      harness.total = harness.total + 1
      harness.failures[#harness.failures + 1] =
        { name = vim.fn.fnamemodify(spec, ":t") .. " (load)", err = tostring(err) }
      io.write("E")
    end
  end
end

os.exit(harness.report() and 0 or 1)
