-- Scene for screen.py: a word in an empty project, ready for `ghiw` + a label + <Tab>.
vim.o.termguicolors = true
vim.api.nvim_set_hl(0, 'Normal', { fg = '#c0caf5', bg = '#1a1b26' })
vim.api.nvim_set_hl(0, 'NormalFloat', { fg = '#c0caf5', bg = '#1f2335' })
vim.api.nvim_set_hl(0, 'FloatBorder', { fg = '#7aa2f7', bg = '#1f2335' })
vim.g.mapleader = ' '
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. '/.earmark', 'p')
require('earmark').setup({ storage_dir = tmp .. '/data', hover = { auto = false } })
vim.fn.writefile({ 'The committee approved the annual budget on Tuesday.', '', '' }, tmp .. '/scene.md')
vim.cmd('edit ' .. tmp .. '/scene.md')
vim.o.laststatus, vim.o.ruler, vim.o.showmode = 0, false, false
vim.api.nvim_win_set_cursor(0, { 1, 15 })
