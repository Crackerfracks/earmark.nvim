-- Scene for screen.py: the overlap looks, on a dark or (vim.g.light) light theme.
vim.o.termguicolors = true
if vim.env.EARMARK_LIGHT then
  vim.o.background = 'light'
  vim.api.nvim_set_hl(0, 'Normal', { fg = '#24292f', bg = '#ffffff' })
else
  vim.api.nvim_set_hl(0, 'Normal', { fg = '#c0caf5', bg = '#1a1b26' })
end
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. '/.earmark', 'p')
local em = require('earmark')
em.setup({ storage_dir = tmp .. '/data', hover = { auto = false } })
vim.fn.writefile({
  'Different labels: she has run the library for twelve years.',
  'One label, nested: the reading room is full every afternoon.',
  'Four labels on one word: the roof leaks in two places.',
  'Stale: the new wing would double the budget for staff.',
  'Plain: label 3 alone, label 7 alone.',
}, tmp .. '/scene.md')
vim.cmd('edit ' .. tmp .. '/scene.md')
vim.o.laststatus, vim.o.ruler, vim.o.showmode = 0, false, false
local function v(l) return { set = 'vivid', label = l } end
local function find(row, s) local c = vim.fn.getline(row + 1):find(s, 1, true) - 1 return c, c + #s end
local s, e = find(0, 'the library for'); em.annotate(0, { 0, s }, { 0, e }, v('2'))
s, e = find(0, 'library'); em.annotate(0, { 0, s }, { 0, e }, v('5'))
s, e = find(1, 'reading room is'); em.annotate(0, { 1, s }, { 1, e }, v('4'))
s, e = find(1, 'room is'); em.annotate(0, { 1, s }, { 1, e }, v('4'))
s, e = find(1, 'room'); em.annotate(0, { 1, s }, { 1, e }, v('4'))
s, e = find(2, 'roof leaks'); local a = em.annotate(0, { 2, s }, { 2, e }, v('6'))
require('earmark.buffer').set_values(0, a.id, { v('6'), v('3'), v('8'), v('9') })
s, e = find(3, 'double the budget'); em.annotate(0, { 3, s }, { 3, e }, v('1'))
vim.api.nvim_buf_set_text(0, 3, s, 3, e, { 'triple the money' })
require('earmark.buffer').on_change(0)
require('earmark.buffer').refresh_snapshot(0, require('earmark.buffer').state[vim.api.nvim_get_current_buf()])
s, e = find(4, 'label 3'); em.annotate(0, { 4, s }, { 4, e }, v('3'))
s, e = find(4, 'label 7'); em.annotate(0, { 4, s }, { 4, e }, v('7'))
vim.cmd('normal! G$')
