-- Small shims over Neovim APIs that moved between versions.
local M = {}

--- `vim.diff` was renamed `vim.text.diff` (0.12 deprecates the old name).
M.diff = (vim.text and vim.text.diff) or vim.diff

function M.supported()
  return vim.fn.has('nvim-0.11') == 1
end

return M
