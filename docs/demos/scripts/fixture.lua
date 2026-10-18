-- Builds the demo project used by `make demo` and by the recordings in docs/demos: a small
-- Markdown "project" (notes/essay.md already annotated, notes/fresh.md blank, notes/changed.md
-- edited "outside Neovim" after annotating) and an init.lua that loads this checkout of earmark
-- with its defaults and nothing from your own config.
--   nvim --headless --clean -l docs/demos/scripts/fixture.lua <repo> <dir>
--   then: cd <dir>/proj && nvim -u ../init.lua notes/essay.md
local repo, base = arg[1], arg[2]
assert(repo and base, 'usage: fixture.lua <repo> <dir>')
vim.fn.delete(base, 'rf')
vim.fn.mkdir(base .. '/proj/.earmark/sets', 'p')
vim.fn.mkdir(base .. '/proj/notes', 'p')
-- the project is also a zk notebook (for the zk clip); notes are named after their title
vim.fn.mkdir(base .. '/proj/.zk', 'p')
vim.fn.writefile({ '[note]', 'filename = "{{slug title}}"' }, base .. '/proj/.zk/config.toml')

-- The init finds its own directory, so the project can be copied anywhere.
vim.fn.writefile({
  '-- earmark demo: this checkout of earmark with its defaults, nothing from your config.',
  "local here = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h')",
  ('vim.opt.runtimepath:prepend(%q)'):format(repo),
  '-- optional extras, used when your lazy.nvim has them: a dark theme, a picker, jump labels',
  "local lazy = vim.fn.stdpath('data') .. '/lazy'",
  "if os.getenv('EARMARK_DEMO_LAZY') then lazy = os.getenv('EARMARK_DEMO_LAZY') end",
  "for _, p in ipairs({ 'tokyonight.nvim', 'snacks.nvim', 'flash.nvim' }) do",
  "  if vim.uv.fs_stat(lazy .. '/' .. p) then vim.opt.runtimepath:append(lazy .. '/' .. p) end",
  'end',
  "vim.g.mapleader = ' '",
  "vim.g.maplocalleader = ','",
  'vim.g.have_nerd_font = true',
  'vim.o.termguicolors = true',
  'vim.o.swapfile = false',
  "vim.o.shadafile = 'NONE'",
  'vim.o.number = true',
  'vim.o.wrap = true',
  'vim.o.linebreak = true',
  'vim.o.cursorline = true',
  'vim.o.hlsearch = false',
  'vim.o.laststatus = 3',
  'vim.o.showcmd = false',
  'vim.o.ruler = false',
  "vim.o.signcolumn = 'no'",
  "vim.o.shortmess = vim.o.shortmess .. 'IF'",
  "if pcall(require, 'tokyonight') then require('tokyonight').setup({ style = 'night' }); vim.cmd.colorscheme('tokyonight-night') end",
  "if pcall(require, 'snacks') then require('snacks').setup({ picker = { enabled = true } }) end",
  "if pcall(require, 'flash') then require('flash').setup({}) end",
  "local cfg = { storage_dir = here .. '/data', sets_dir = false }",
  "local extra = os.getenv('EARMARK_DEMO_OPTS') -- recordings that show a non-default option",
  "if extra and extra ~= '' then cfg = vim.tbl_deep_extend('force', cfg, assert(loadstring('return ' .. extra))()) end",
  "require('earmark').setup(cfg)",
  "vim.o.statusline = ' %t %m%= %{%v:lua.require(\"earmark\").statusline()%} '",
  ('if os.getenv(%q) then dofile(%q) end'):format('EARMARK_DEMO_REC', repo .. '/docs/demos/scripts/keycast.lua'),
}, base .. '/init.lua')

-- the label set file used by the "Label set files" clip (copied from scripts/demo.lua)
vim.fn.writefile({ vim.json.encode({
  labels = {
    { key = 'q1', name = 'Accuracy', color = '#e06c75',
      choices = { { key = 'a', name = 'Correct' }, { key = 'b', name = 'Minor issue', color = '#e5c07b' }, { key = 'c', name = 'Major issue' } },
      text = { when = { 'b', 'c' }, prompt = 'What is wrong?' } },
    { key = 'q2', name = 'Tone', color = '#61afef' },
  },
}) }, base .. '/proj/.earmark/sets/review.json')
vim.fn.writefile({}, base .. '/proj/.earmark/.keep')

-- essay.md: already annotated (for hover, notes, pickers, review, export ...)
local essay = {
  '# Town budget, field notes',
  '',
  'The committee approved the annual budget yesterday',
  'after a long debate about whether the new library',
  'wing should come first.',
  '',
  'Several members argued that the roads were in worse',
  'shape than anyone admitted. The mayor called it a',
  'vague promise and asked for a real plan.',
  '',
  'Revenue grew by 40% last year, which nobody can',
  'quite explain. The treasurer said the figures would',
  'be ready next week.',
  '',
  'Next steps: ask the treasurer for the figures, and',
  'read the minutes again before Thursday.',
}
vim.fn.writefile(essay, base .. '/proj/notes/essay.md')

-- fresh.md: no annotations yet (for the "make one" clips)
local fresh = {
  '# Interview with the librarian',
  '',
  'She has run the library for twelve years and says',
  'the reading room is full every afternoon. The roof',
  'leaks in two places, and the heating is unreliable.',
  '',
  'Her main worry is the budget: the new wing would',
  'double the floor space but not the staff. She would',
  'rather fix the roof first and hire two assistants.',
  '',
  'Visitors mostly come for the quiet, the free wifi',
  'and the children\'s corner on Saturday mornings.',
}
vim.fn.writefile(fresh, base .. '/proj/notes/fresh.md')

-- build the annotations in essay.md with the API, against the base paths
local runtime_storage = base .. '/data'  -- same as the init's here .. '/data'
vim.opt.runtimepath:prepend(repo)
require('earmark').setup({ storage_dir = runtime_storage, sets_dir = false })
local em = require('earmark')

local function annotate_file(path, lines, spec)
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
  local function span(row, word)
    local s = assert(lines[row]:find(word, 1, true), word) - 1
    return { row - 1, s }, { row - 1, s + #word }
  end
  spec(span)
  require('earmark.buffer').save(vim.api.nvim_get_current_buf())
end

annotate_file(base .. '/proj/notes/essay.md', essay, function(span)
  local s, e = span(3, 'approved the annual budget')
  local a = em.annotate(0, s, e, { set = 'vivid', label = '3' })
  em.set_note(0, a.id, 'Check the vote count in the minutes. #source @minutes')
  em.rename_label(0, { set = 'vivid', label = '3' }, 'Claim')
  s, e = span(3, 'budget')
  em.annotate(0, s, e, { set = 'vivid', label = '7' })

  s, e = span(4, 'new library')
  local b = em.annotate(0, s, e, { set = 'vivid', label = '3' })
  em.set_tags(0, b.id, { 'todo' })

  s, e = span(9, 'vague promise')
  local v = em.annotate(0, s, e, { set = 'vivid', label = '5' })
  em.set_note(0, v.id, 'Quote him exactly. #quote')
  em.rename_label(0, { set = 'vivid', label = '5' }, 'Vague')

  s, e = span(11, 'Revenue grew by 40% last year')
  local c = em.annotate(0, s, e, { set = 'vivid', label = '1' })
  em.set_note(0, c.id, 'Typo or real? The report says 14%. #todo')
  em.rename_label(0, { set = 'vivid', label = '1' }, 'Check')

  s, e = span(15, 'ask the treasurer for the figures')
  em.annotate(0, s, e, { set = 'vivid', label = '9' })
end)

-- changed.md: annotated, then rewritten "outside Neovim" so some annotations go stale,
-- detached or ambiguous (for the review, diff and reanchor clips)
local minutes = {
  '# Market minutes, 12 March',
  '',
  'Ann proposed moving the market to Saturdays.',
  'The motion passed with seven votes to two.',
  '',
  'Bob asked about parking near the square and',
  'nobody had an answer.',
  '',
  'Stall fees stay the same. Stall fees stay low.',
  '',
  'Revenue from stalls grew by 40% last year.',
}
vim.fn.writefile(minutes, base .. '/proj/notes/changed.md')
annotate_file(base .. '/proj/notes/changed.md', minutes, function(span)
  local s, e = span(4, 'seven votes to two')
  local a = em.annotate(0, s, e, { set = 'vivid', label = '2' })
  em.set_note(0, a.id, 'Who voted against? #todo')
  s, e = span(6, 'parking near the square')
  em.annotate(0, s, e, { set = 'vivid', label = '4' })
  s, e = span(11, 'grew by 40%')
  em.annotate(0, s, e, { set = 'vivid', label = '6' })
  s, e = span(3, 'moving the market to Saturdays')
  em.annotate(0, s, e, { set = 'vivid', label = '8' })
end)
vim.cmd('bwipeout!')
vim.fn.writefile({
  '# Market minutes, 12 March',
  '',
  'Ann proposed moving the market to Saturdays.',
  'The motion passed with seven votes to two.',
  '',
  'Stall fees stay the same. Stall fees stay low.',
  '',
  'Revenue from stalls shrank to 4% last year.',
  '',
  'Bob wants to know where people should park.',
}, base .. '/proj/notes/changed.md')

-- Records keep the file's absolute path in doc.name; record.py rewrites it when it copies
-- this project for each clip.
io.stdout:write(('earmark demo project written to %s\n\n  cd %s/proj && nvim -u ../init.lua notes/essay.md\n\n'):format(base, base))
vim.cmd('qall!')
