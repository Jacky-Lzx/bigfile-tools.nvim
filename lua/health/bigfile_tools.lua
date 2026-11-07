local M = {}
function M.check()
  vim.health.start("bigfile-tools")
  if vim.fn.has("nvim-0.11") == 1 then
    vim.health.ok("Neovim is supported")
  else
    vim.health.error("Neovim 0.11+ is required")
  end
  vim.health.info("Use :BigfileToolsInfo for current protection state")
end
return M
