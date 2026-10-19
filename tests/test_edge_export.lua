-- Edge cases of the Markdown export: every grouping, detached on and off, text that is
-- hostile to Markdown or to line-based writing, buffers without a file, every location,
-- folders that are missing or can't be written, and labels whose set is gone.
local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child, "{ prompt = { ask_name = 'never', confirm_stack = false }, sets_dir = false }")

local function mark(s, e, label, set)
  return child.lua_get('require("earmark").annotate(0, ...).id', { s, e, { set = set or 'vivid', label = label or '3' } })
end

local function note(id, text)
  child.lua('require("earmark.buffer").set_note(0, ...)', { id, text })
end

local function export(opts)
  return child.lua_get('require("earmark.export").markdown(0, ...)', { opts or vim.empty_dict() })
end

local function body(opts)
  return vim.list_slice(export(opts), 3)
end

--- Every line is one line: no newline or carriage return inside an element.
local function flat(lines)
  for _, l in ipairs(lines) do
    if l:find('[\r\n]') then return false, l end
  end
  return true
end

local function input(answer)
  child.lua([[
    _G.msgs = {}
    vim.notify = function(m, l) table.insert(_G.msgs, { m, l }) end
    _G.answer = ...
    vim.ui.input = function(opts, cb) _G.default = opts.default; cb(_G.answer or opts.default) end
  ]], { answer })
end

-- three labels, tags, a note, and one annotation made later than the others
local function sample()
  h.open()
  local a = mark({ 2, 0 }, { 2, 5 }, '3') -- Third
  local b = mark({ 0, 4 }, { 0, 9 }, '4') -- quick
  local c = mark({ 1, 2 }, { 1, 8 }, '3') -- second
  child.lua('require("earmark").set_tags(0, ..., { "zeta", "alpha" })', { a })
  note(b, 'about #alpha')
  child.lua([[
    local list = ...
    for i, id in ipairs(list) do require('earmark.buffer').annotation(0, id).created = 1000 + i end
  ]], { { c, a, b } }) -- made in this order: second, Third, quick
  return a, b, c
end

---------------------------------------------------------------------------
-- Groupings
---------------------------------------------------------------------------

T['group_by label: one section per label in the order first seen'] = function()
  sample()
  eq(body({ group_by = 'label' }), {
    '## 4 (vivid·4)',
    '- **"quick"** (L1) #alpha',
    '  about #alpha',
    '',
    '## 3 (vivid·3)',
    '- **"second"** (L2)',
    '- **"Third"** (L3) #zeta #alpha',
  })
end

T['group_by position: one list in text order, each item named'] = function()
  sample()
  eq(body({ group_by = 'position' }), {
    '- **4** **"quick"** (L1) #alpha',
    '  about #alpha',
    '- **3** **"second"** (L2)',
    '- **3** **"Third"** (L3) #zeta #alpha',
  })
end

T['group_by time: in the order they were made'] = function()
  sample()
  eq(body({ group_by = 'time' }), {
    '- **3** **"second"** (L2)',
    '- **3** **"Third"** (L3) #zeta #alpha',
    '- **4** **"quick"** (L1) #alpha',
    '  about #alpha',
  })
end

T['group_by time: made in the same second, they stay in text order'] = function()
  h.open({ string.rep('ab ', 40) })
  child.lua([[
    for i = 0, 39 do
      local a = require('earmark').annotate(0, { 0, i * 3 }, { 0, i * 3 + 2 }, { set = 'vivid', label = tostring(i + 1) })
      require('earmark.buffer').annotation(0, a.id).created = 5000
    end
  ]])
  local out = body({ group_by = 'time' })
  local want = {}
  for i = 1, 40 do
    want[i] = ('- **%d** **"ab"** (L1)'):format(i)
  end
  eq(out, want)
end

T['group_by tag: a section per tag, sorted; an item with two tags is in both; then Untagged'] = function()
  sample()
  eq(body({ group_by = 'tag' }), {
    '## #alpha',
    '- **4** **"quick"** (L1) #alpha',
    '  about #alpha',
    '- **3** **"Third"** (L3) #zeta #alpha',
    '',
    '## #zeta',
    '- **3** **"Third"** (L3) #zeta #alpha',
    '',
    '## Untagged',
    '- **3** **"second"** (L2)',
  })
end

T['an unknown group_by falls back to labels'] = function()
  sample()
  eq(body({ group_by = 'nonsense' }), body({ group_by = 'label' }))
end

T['include_detached: the Detached section on, and off'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 }, '3')
  local d = mark({ 2, 0 }, { 2, 5 }, '5')
  note(d, 'first line of the note\nsecond line')
  child.api.nvim_buf_set_lines(0, 2, 3, false, {})
  child.lua('require("earmark.buffer").on_change(0)')
  for _, by in ipairs({ 'label', 'position', 'tag', 'time' }) do
    local on = body({ group_by = by })
    eq(vim.list_slice(on, #on - 1), { '## Detached', '- "Third" — 5 — first line of the note' })
    local off = body({ group_by = by, include_detached = false })
    eq(vim.tbl_contains(off, '## Detached'), false)
    eq(table.concat(off, '\n'):find('Third', 1, true), nil)
  end
end

T['only detached annotations, detached off: just the heading'] = function()
  h.open()
  mark({ 2, 0 }, { 2, 5 }, '5')
  child.api.nvim_buf_set_lines(0, 2, 3, false, {})
  child.lua('require("earmark.buffer").on_change(0)')
  eq(#export({ include_detached = false }), 1)
end

T['several labels on one annotation, a choice and its text'] = function()
  child.lua([[
    local dir = _G.root .. '/.earmark/sets'
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile({ vim.json.encode({ labels = {
      { key = 'q1', name = 'Accuracy', choices = { { key = 'a', name = 'Correct' }, { key = 'b', name = 'Minor' } } },
      { key = 'q2', name = 'Tone' },
    } }) }, dir .. '/wf.json')
  ]])
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 }, 'q1', 'wf')
  child.lua('require("earmark.buffer").set_values(0, ..., { { set = "wf", label = "q1", choice = "b", text = "wrong\\nanimal" }, { set = "wf", label = "q2" } })', { id })
  local out = body()
  eq(out[1], '## Accuracy · b Minor (wf·q1)')
  eq(out[2], '- **"quick"** (L1)')
  eq(flat(out), true)
  eq(vim.list_slice(out, 3), { '  > wrong', '  > animal' })
  eq(body({ group_by = 'position' })[1], '- **Accuracy · b Minor + Tone** **"quick"** (L1)')
end

T['line references: one line, several, and a span ending at the start of a line'] = function()
  h.open()
  mark({ 0, 0 }, { 2, 3 }, '3')
  mark({ 1, 0 }, { 2, 0 }, '4')
  local out = body({ group_by = 'position' })
  eq(out[1], '- **3** **"The quick brown fox jumps over the lazy dog. A second line with some words. Thi"** (L1–L3)')
  eq(out[2], '- **4** **"A second line with some words."** (L2)')
end

---------------------------------------------------------------------------
-- Hostile text
---------------------------------------------------------------------------

T['Markdown-hostile quote, note, names and tags: kept as written, one line each'] = function()
  h.open({ '`code` | pipe | *star* # hash <b>x</b> [l](u) _u_', 'next' })
  local id = mark({ 0, 0 }, { 1, 4 }, '3')
  note(id, 'line one\r\nline two\r\n# heading-ish\n- dash\n\n```\nfenced #nottag\n```')
  child.lua([[
    local id = ...
    require('earmark.buffer').rename_label(0, { set = 'vivid', label = '3' }, 'Name\nwith newline')
    require('earmark').set_tags(0, id, { 'a\nb' })
  ]], { id })
  for _, by in ipairs({ 'label', 'position', 'tag', 'time' }) do
    local out = export({ group_by = by })
    local ok, bad = flat(out)
    eq({ by, ok, bad }, { by, true, nil })
    local text = table.concat(out, '\n')
    eq(text:find('`code` | pipe | *star* # hash <b>x</b> [l](u) _u_ next', 1, true) ~= nil, true)
    eq(text:find('  line one\n  line two\n  # heading-ish\n  - dash\n\n  ```\n  fenced #nottag\n  ```', 1, true) ~= nil, true)
  end
  eq(body()[1], '## Name with newline (vivid·3)')
end

T['a note with a carriage return only line break, and trailing blank lines'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 }, '3')
  note(id, 'a\r\nb\n\n')
  local out = body()
  eq(flat(out), true)
  eq(vim.list_slice(out, 3, 4), { '  a', '  b' })
end

T['the export written to a file has no NUL bytes from embedded newlines'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 }, '3')
  child.lua('require("earmark.buffer").set_values(0, ..., { { set = "vivid", label = "3", text = "one\\ntwo" } })', { id })
  input()
  child.type_keys(' me')
  local path = child.lua_get('_G.default')
  local f = assert(io.open(path, 'rb'))
  local raw = f:read('*a')
  f:close()
  eq(raw:find('%z'), nil)
  eq(raw:find('  > one\n  > two', 1, true) ~= nil, true)
end

T['the lines can go straight into a buffer'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 }, '3')
  note(id, 'x\r\ny')
  child.lua('require("earmark.buffer").set_values(0, ..., { { set = "vivid", label = "3", text = "t\\nu" } })', { id })
  child.lua([[
    local lines = require('earmark').export(0)
    local b = vim.api.nvim_create_buf(false, true)
    _G.ok = pcall(vim.api.nvim_buf_set_lines, b, 0, -1, false, lines)
  ]])
  eq(child.lua_get('_G.ok'), true)
end

---------------------------------------------------------------------------
-- Buffers without annotations or without a file
---------------------------------------------------------------------------

T['a buffer without annotations: the heading only; <leader>me says so and writes nothing'] = function()
  h.open()
  eq(#export(), 1)
  input()
  child.type_keys(' me')
  eq(child.lua_get('_G.msgs[1][1]'), 'earmark: no annotations')
  eq(child.lua_get('_G.default'), vim.NIL)
end

T['an empty file with an annotation on nothing left: only Detached'] = function()
  h.open({ 'word' })
  mark({ 0, 0 }, { 0, 4 }, '3')
  child.api.nvim_buf_set_lines(0, 0, -1, false, {})
  child.lua('require("earmark.buffer").on_change(0)')
  eq(body(), { '## Detached', '- "word" — 3' })
end

T['an unnamed buffer: [scratch] in the heading, the export goes to storage_dir'] = function()
  child.cmd('enew')
  child.api.nvim_buf_set_lines(0, 0, -1, false, { 'scratch words here' })
  mark({ 0, 0 }, { 0, 7 }, '3')
  local out = export()
  eq(out[1]:match('^# %[scratch%] — earmark export') ~= nil, true)
  eq(out[4], '- **"scratch"** (L1)')
  local p = child.lua_get('require("earmark.export").default_path(0)')
  eq(p:match('^' .. vim.pesc(child.lua_get('_G.tmp')) .. '/data/export/scratch%-%d+%-%d+%.md$') ~= nil, true)
  child.lua('require("earmark.config").options.export.location = "beside"')
  eq(child.lua_get('require("earmark.export").default_path(0)'):find('/data/export/scratch-', 1, true) ~= nil, true)
  input()
  child.type_keys(' me')
  eq(child.fn.filereadable(child.lua_get('_G.default')), 1)
end

T['a file outside any project: the export goes to storage_dir under its name'] = function()
  child.lua([[
    vim.fn.mkdir(_G.tmp .. '/loose', 'p')
    vim.fn.writefile({ 'loose text' }, _G.tmp .. '/loose/free.md')
    vim.cmd('edit ' .. _G.tmp .. '/loose/free.md')
  ]])
  mark({ 0, 0 }, { 0, 5 }, '3')
  eq(child.lua_get('require("earmark.export").default_path(0)'), child.lua_get('_G.tmp') .. '/data/export/free.md')
end

---------------------------------------------------------------------------
-- Locations
---------------------------------------------------------------------------

T['location project: <root>/.earmark/export/<project>-<path>.md'] = function()
  h.open(nil, 'notes/sub/my doc.v2.md')
  local root = child.lua_get('vim.uv.fs_realpath(_G.root)')
  eq(child.lua_get('require("earmark.export").default_path(0)'), root .. '/.earmark/export/proj-notes-sub-my doc.v2.md')
end

T['location project: folders with dots do not lose the file name'] = function()
  local root = child.lua_get('vim.uv.fs_realpath(_G.root)')
  h.open(nil, 'notes/v1.2/README')
  local a = child.lua_get('require("earmark.export").default_path(0)')
  h.open(nil, 'notes/v1.3/README')
  local b = child.lua_get('require("earmark.export").default_path(0)')
  eq(a, root .. '/.earmark/export/proj-notes-v1.2-README.md')
  eq(b, root .. '/.earmark/export/proj-notes-v1.3-README.md')
end

T['location beside: <name>.earmark.md next to the file, also without an extension'] = function()
  local root = child.lua_get('vim.uv.fs_realpath(_G.root)')
  child.lua('require("earmark.config").options.export.location = "beside"')
  h.open(nil, 'notes/plan.md')
  eq(child.lua_get('require("earmark.export").default_path(0)'), root .. '/notes/plan.earmark.md')
  h.open(nil, 'notes/Makefile')
  eq(child.lua_get('require("earmark.export").default_path(0)'), root .. '/notes/Makefile.earmark.md')
end

T['location function: gets buf and ctx; nil is skipped; a list keeps order without duplicates'] = function()
  h.open()
  child.lua([[
    local o = require('earmark.config').options.export
    o.location = {
      function(buf, ctx) _G.ctx = { buf = buf, path = ctx.path, key = ctx.doc.key } return _G.tmp .. '/out/a.md' end,
      function() return nil end,
      'project',
      function() return _G.tmp .. '/out/a.md' end,
      'project',
    }
  ]])
  local root = child.lua_get('vim.uv.fs_realpath(_G.root)')
  local tmp = child.lua_get('_G.tmp')
  eq(child.lua_get('require("earmark.export").paths(0)'), { tmp .. '/out/a.md', root .. '/.earmark/export/proj-notes-doc.md' })
  eq(child.lua_get('_G.ctx'), { buf = child.api.nvim_get_current_buf(), path = child.api.nvim_buf_get_name(0), key = 'notes/doc.md' })
end

T['location that gives nothing at all: asked with an empty default, nothing written on cancel'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 }, '3')
  child.lua('require("earmark.config").options.export.location = function() return nil end')
  child.lua([[
    _G.msgs = {}
    vim.notify = function(m) table.insert(_G.msgs, m) end
    vim.ui.input = function(opts, cb) _G.asked = { default = opts.default }; cb('  ') end
  ]])
  child.type_keys(' me')
  eq(child.lua_get('_G.asked'), {})
  eq(#child.api.nvim_list_wins(), 1)
  eq(child.v.errmsg, '')
end

T['<leader>me: a destination folder that does not exist is made; a relative answer is from the cwd'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 }, '3')
  child.lua('vim.cmd.cd(_G.tmp)')
  input('deep/new/folder/out.md')
  child.type_keys(' me')
  local tmp = child.lua_get('vim.uv.fs_realpath(_G.tmp)')
  eq(child.fn.filereadable(tmp .. '/deep/new/folder/out.md'), 1)
  eq(child.lua_get('_G.msgs[#_G.msgs][1]'):find('exported 1 to', 1, true) ~= nil, true)
end

T['<leader>me: a destination that cannot be written is an error message, not a Lua error'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 }, '3')
  child.lua('vim.fn.writefile({ "a file" }, _G.tmp .. "/blocker")')
  input(child.lua_get('_G.tmp') .. '/blocker/sub/out.md')
  child.type_keys(' me')
  eq(child.v.errmsg, '')
  local m = child.lua_get('_G.msgs[#_G.msgs]')
  eq(m[1]:find('could not write', 1, true) ~= nil, true)
  eq(m[2], vim.log.levels.ERROR)
  eq(#child.api.nvim_list_wins(), 1)
  -- the file itself in place of a folder
  input(child.lua_get('_G.tmp') .. '/blocker/out.md')
  child.type_keys(' me')
  eq(child.v.errmsg, '')
  eq(child.lua_get('_G.msgs[#_G.msgs][1]'):find('could not write', 1, true) ~= nil, true)
end

T['<leader>me: a second location that cannot be written is a warning; the first is written'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 }, '3')
  child.lua([[
    vim.fn.writefile({ 'a file' }, _G.tmp .. '/blocker')
    require('earmark.config').options.export.location = { 'project', function() return _G.tmp .. '/blocker/x/y.md' end }
  ]])
  input()
  child.type_keys(' me')
  eq(child.v.errmsg, '')
  eq(child.fn.filereadable(child.lua_get('_G.default')), 1)
  local warned = false
  for _, m in ipairs(child.lua_get('_G.msgs')) do
    if m[1]:find('could not write', 1, true) and m[2] == vim.log.levels.WARN then warned = true end
  end
  eq(warned, true)
end

T['<leader>me twice: the open export window shows the new content'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 }, '3')
  input()
  child.type_keys(' me')
  child.cmd('wincmd p')
  note(id, 'added later')
  -- (not typed: reloading runs the markdown ftplugin's undo, whose `silent! nunmap` leaves
  -- E31 in v:errmsg, which type_keys reports)
  child.lua('require("earmark.export").run(0)')
  eq(#child.api.nvim_list_wins(), 2)
  local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
  eq(vim.tbl_contains(lines, '  added later'), true)
end

T['opts.format replaces the body and gets the list and ctx'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 }, '3')
  child.lua([[
    require('earmark.config').options.export.format = function(list, ctx)
      return { ('%d %s %s'):format(#list, ctx.name, tostring(ctx.buf == vim.api.nvim_get_current_buf())) }
    end
  ]])
  eq(body(), { '1 doc.md true' })
  child.lua('require("earmark.config").options.export.format = function() return nil end')
  eq(#export(), 2)
end

---------------------------------------------------------------------------
-- Labels whose set changed
---------------------------------------------------------------------------

local CHOICES = {
  extends = 'feedback',
  labels = { { key = 'a', name = 'Option A: one big picker' }, { key = 'b', name = 'Option B' } },
}

local function write(rel, tbl)
  child.lua([[
    local path = _G.root .. '/' .. select(1, ...)
    vim.fn.mkdir(vim.fs.dirname(path), 'p')
    vim.fn.writefile({ vim.json.encode(select(2, ...)) }, path)
  ]], { rel, tbl })
end

T['a file\'s own set that has expired: the export still reads its names'] = function()
  write('notes/plan.earmark-set.json', vim.tbl_extend('force', CHOICES, { expires = '2000-01-01' }))
  h.open(nil, 'notes/plan.md')
  mark({ 0, 4 }, { 0, 9 }, 'a', 'plan')
  mark({ 1, 2 }, { 1, 8 }, '2', 'plan')
  local out = body()
  eq(out[1], '## Option A: one big picker (plan·a)')
  eq(out[4], '## Change (plan·2)')
  eq(table.concat(export({ group_by = 'position' }), '\n'):find('nil', 1, true), nil)
end

T['a file\'s own set that was deleted: the export shows the keys, never nil'] = function()
  write('notes/plan.earmark-set.json', CHOICES)
  h.open(nil, 'notes/plan.md')
  mark({ 0, 4 }, { 0, 9 }, 'a', 'plan')
  child.lua([[
    require('earmark.buffer').save(0) -- :Earmark reload re-reads the record
    vim.fn.delete(_G.root .. '/notes/plan.earmark-set.json')
    vim.cmd('Earmark reload')
  ]])
  eq(child.lua_get('require("earmark.sets").by_name.plan'), vim.NIL)
  for _, by in ipairs({ 'label', 'position', 'tag', 'time' }) do
    local text = table.concat(export({ group_by = by }), '\n')
    eq(text:find('nil', 1, true), nil)
    eq(text:find('"quick"', 1, true) ~= nil, true)
  end
  eq(body()[1], '## a (plan·a)')
end

T['a file\'s own set that was deleted: names given in the file still read'] = function()
  write('notes/plan.earmark-set.json', CHOICES)
  h.open(nil, 'notes/plan.md')
  mark({ 0, 4 }, { 0, 9 }, 'a', 'plan')
  child.lua('require("earmark").rename_label(0, { set = "plan", label = "a" }, "My name for A")')
  child.lua([[
    require('earmark.buffer').save(0) -- :Earmark reload re-reads the record
    vim.fn.delete(_G.root .. '/notes/plan.earmark-set.json')
    vim.cmd('Earmark reload')
  ]])
  eq(body()[1], '## My name for A (plan·a)')
end

T['a file\'s own set that was deleted: the set\'s own label names still read'] = function()
  MiniTest.skip('label names live only in the set file; keeping them needs the record to store them (storage change)')
  write('notes/plan.earmark-set.json', CHOICES)
  h.open(nil, 'notes/plan.md')
  mark({ 0, 4 }, { 0, 9 }, 'a', 'plan')
  child.lua([[
    require('earmark.buffer').save(0) -- :Earmark reload re-reads the record
    vim.fn.delete(_G.root .. '/notes/plan.earmark-set.json')
    vim.cmd('Earmark reload')
  ]])
  eq(body()[1], '## Option A: one big picker (plan·a)')
end

return T
