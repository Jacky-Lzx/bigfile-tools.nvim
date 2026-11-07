if vim.g.loaded_bigfile_tools then
  return
end
vim.g.loaded_bigfile_tools = true
-- Entry point is intentionally retained when protection is disposed.
if vim.fn.exists(":BigfileToolsInfo") == 0 then
  vim.api.nvim_create_user_command("BigfileToolsInfo", function()
    vim.print(require("bigfile_tools").info())
  end, { desc = "Inspect large-buffer protection without activating it" })
end
