-- Scene for screen.py: the key list (<leader>m?).
vim.o.termguicolors = true
vim.g.mapleader = ' '
vim.g.maplocalleader = ','
vim.api.nvim_set_hl(0, 'Normal', { fg = '#c0caf5', bg = '#1a1b26' })
vim.api.nvim_set_hl(0, 'NormalFloat', { fg = '#c0caf5', bg = '#16161e' })
vim.api.nvim_set_hl(0, 'FloatBorder', { fg = '#565f89', bg = '#16161e' })
vim.api.nvim_set_hl(0, 'FloatTitle', { fg = '#7aa2f7', bg = '#16161e', bold = true })
vim.api.nvim_set_hl(0, 'FloatFooter', { fg = '#565f89', bg = '#16161e' })
vim.api.nvim_set_hl(0, 'Title', { fg = '#bb9af7', bold = true })
vim.api.nvim_set_hl(0, 'Special', { fg = '#e0af68' })
vim.api.nvim_set_hl(0, 'Comment', { fg = '#565f89' })
vim.api.nvim_set_hl(0, 'CursorLine', { bg = '#292e42' })
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. '/.earmark', 'p')
require('earmark').setup({ storage_dir = tmp .. '/data', hover = { auto = false } })
vim.fn.writefile({ 'Notes for the dashboard plan.' }, tmp .. '/plan.md')
vim.cmd('edit ' .. tmp .. '/plan.md')
require('earmark.ui.keys').open()
