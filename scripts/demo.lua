-- `make demo`: writes a small annotated project to $EARMARK_DEMO (default /tmp/earmark-demo)
-- and prints the command that opens it with this checkout of earmark.
local repo = vim.fn.getcwd()
local dir = os.getenv('EARMARK_DEMO') or '/tmp/earmark-demo'
vim.fn.delete(dir, 'rf')
vim.fn.mkdir(dir .. '/.earmark/sets', 'p')

vim.fn.writefile({
  ('vim.opt.runtimepath:prepend(%q)'):format(repo),
  "vim.g.mapleader = ' '",
  "vim.g.maplocalleader = ','",
  'vim.o.termguicolors = true',
  "require('earmark').setup({ storage_dir = " .. ('%q'):format(dir .. '/.data') .. ' })',
}, dir .. '/init.lua')

vim.fn.writefile({ vim.json.encode({
  labels = {
    { key = 'q1', name = 'Accuracy', color = '#e06c75',
      choices = { { key = 'a', name = 'Correct' }, { key = 'b', name = 'Minor issue', color = '#e5c07b' }, { key = 'c', name = 'Major issue' } },
      text = { when = { 'b', 'c' }, prompt = 'What is wrong?' } },
    { key = 'q2', name = 'Tone', color = '#61afef' },
  },
}) }, dir .. '/.earmark/sets/review.json')

local text = {
  '# Field notes',
  '',
  'The committee approved the annual budget yesterday, after a long debate about',
  'whether the new library wing should come first. Several members argued that the',
  'roads were in worse shape than anyone admitted.',
  '',
  'Revenue grew by 40% last year, which nobody can quite explain.',
  '',
  'Next steps: ask the treasurer for the figures, and read the minutes again.',
}
vim.fn.writefile(text, dir .. '/draft.md')

vim.opt.runtimepath:prepend(repo)
require('earmark').setup({ storage_dir = dir .. '/.data' })
vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/draft.md'))
local em = require('earmark')

local function span(row, word, n)
  local line = text[row + 1]
  local s = assert(line:find(word, 1, true), word) - 1
  return { row, s }, { row, s + #word }, n
end

local s, e = span(2, 'approved the annual budget')
local a = em.annotate(0, s, e, { set = 'vivid', label = '3' })
em.set_note(0, a.id, 'Check the vote count. #source @minutes')
em.rename_label(0, { set = 'vivid', label = '3' }, 'Claim')

s, e = span(2, 'annual budget')
em.annotate(0, s, e, { set = 'vivid', label = '7' })

s, e = span(3, 'new library wing')
local b = em.annotate(0, s, e, { set = 'vivid', label = '3' })
em.set_tags(0, b.id, { 'todo' })

s, e = span(6, 'Revenue grew by 40% last year')
local c = em.annotate(0, s, e, { set = 'review', label = 'q1', choice = 'b', text = 'source says 14%' })
em.set_values(0, c.id, { c.values[1], { set = 'review', label = 'q2' } })
em.set_note(0, c.id, 'Typo or real? #todo')

s, e = span(8, 'ask the treasurer for the figures')
em.annotate(0, s, e, { set = 'pastel', label = '12' })

require('earmark.buffer').save(vim.api.nvim_get_current_buf())

io.stdout:write(('earmark demo written to %s (%d annotations)\n\n  nvim -u %s/init.lua %s/draft.md\n\n'):format(
  dir, #em.list(0), dir, dir))
io.stdout:write('Try: rest the cursor on "approved", <leader>mm for its note, <leader>mp to list,\n')
io.stdout:write('     3ghiw on any word, gh{motion} for the prompt, <leader>ms to switch sets.\n')
vim.cmd('qall!')
