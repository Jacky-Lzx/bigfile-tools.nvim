vim.opt.rtp:prepend(vim.fn.getcwd())
local guard = require("bigfile_tools")
local api = vim.api
assert(not guard.info().enabled)
local opts = { max_bytes = 1500, max_line_length = 1000, buffer = { completion = false, ui_tools_disable = true } }
local snapshot = vim.deepcopy(opts)
guard.setup(opts)
assert(vim.deep_equal(opts, snapshot))
vim.cmd("filetype on")
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local file = dir .. "/large.lua"
vim.fn.writefile({ 'local LARGE_VISIBLE = "' .. string.rep("x", 2000) .. '"' }, file)
local observed
api.nvim_create_autocmd("FileType", {
  pattern = "bigfile",
  callback = function(ev)
    observed = vim.b[ev.buf].bigfile and vim.b[ev.buf].completion == false
  end,
})
vim.cmd.edit(file)
local buf = api.nvim_get_current_buf()
assert(observed and vim.bo.filetype == "bigfile")
assert(vim.wo.foldmethod == "manual" and vim.wo.conceallevel == 0)
assert(#guard.info().buffers == 1)
local handlers = #api.nvim_get_autocmds({ group = "BigfileTools" })
guard.setup(opts)
assert(#api.nvim_get_autocmds({ group = "BigfileTools" }) == handlers)
assert(not pcall(guard.setup, { max_bytes = -1 }))
assert(not pcall(guard.setup, { window = { foldmethod = "invalid" } }))
assert(not pcall(guard.setup, { buffer = { invalid = function() end } }))
assert(guard.info().enabled and vim.b.bigfile)
vim.cmd.vsplit()
assert(vim.wo.foldmethod == "manual")
vim.wo.conceallevel = 1 -- A later user change must survive release.
vim.b.completion = true
assert(guard.release(buf))
assert(vim.wo.conceallevel == 1 and vim.b.completion == true)
assert(vim.bo.filetype == "lua" and vim.b.bigfile == nil and vim.b.ui_tools_disable == nil)
vim.cmd("enew!")
vim.bo.filetype = "text"
api.nvim_buf_set_lines(0, 0, -1, false, { string.rep("y", 2000) })
assert(guard.detect(0))
api.nvim_exec_autocmds("TextChanged", { buffer = 0 })
assert(vim.b.bigfile and vim.bo.filetype == "bigfile")
guard.dispose()
assert(not guard.info().enabled and not vim.b.bigfile and vim.bo.filetype == "text")
guard.dispose()
-- The inert filetype classifier must not classify future files after disposal.
vim.cmd("edit! " .. vim.fn.fnameescape(file))
assert(vim.bo.filetype == "lua" and not vim.b.bigfile)
guard.setup({ max_bytes = false, max_line_length = false })
assert(not guard.detect(0))
guard.setup({
  max_bytes = 1,
  exclude = function()
    return true
  end,
})
assert(not guard.detect(0) and #guard.info().buffers == 0)
guard.dispose()
vim.fn.delete(dir, "rf")
print("Bigfile: early ordering, edits, splits, restore ownership, setup/disposal and exclusions passed")
