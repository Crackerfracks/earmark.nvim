local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child)

local function mark(s, e, label)
  return child.lua_get('require("earmark").annotate(0, ...).id', { s, e, { set = 'vivid', label = label or '3' } })
end

local function note_of(id)
  return child.lua_get('(require("earmark.buffer").annotation(vim.fn.bufnr(_G.root .. "/notes/doc.md"), ...) or {}).note or vim.NIL', { id })
end

local function note_bufs()
  return child.lua_get([[vim.tbl_filter(function(b)
    return vim.api.nvim_buf_get_name(b):match('^earmark://note/') ~= nil
  end, vim.api.nvim_list_bufs())]])
end

local function record()
  return child.lua_get([[(function()
    local p = _G.root .. '/.earmark/docs/notes/doc.md.json'
    require('earmark.buffer').save(0)
    return vim.fn.filereadable(p) == 1 and vim.json.decode(table.concat(vim.fn.readfile(p), '\n')) or vim.NIL
  end)()]])
end

T['<leader>mm opens a float under the span, q saves and closes'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  h.cursor(1, 6)
  child.type_keys(' mm')
  local fl = h.floats()
  eq(#fl, 1)
  eq(fl[1].name, 'earmark://note/' .. id)
  eq(fl[1].config.row, 1) -- right under line 1
  eq(fl[1].config.col <= 4, true)
  eq(child.fn.mode(), 'i') -- empty note: starts typing
  child.type_keys('first thought #todo @A', '<Esc>', 'q')
  eq(#h.floats(), 0)
  eq(note_of(id), 'first thought #todo @A')
  eq(#note_bufs(), 0) -- wiped
  eq(child.api.nvim_get_current_buf() ~= nil, true)
  eq(record().annotations[1].note, 'first thought #todo @A')
end

T['reopening shows the same note, one buffer, no E95'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  child.lua('require("earmark.buffer").set_note(0, ..., "line one\\nline two")', { id })
  h.cursor(1, 6)
  child.type_keys(' mm')
  eq(h.floats()[1].lines, { 'line one', 'line two' })
  eq(child.fn.mode(), 'n')
  child.type_keys('q')
  child.type_keys(' mm')
  eq(h.floats()[1].lines, { 'line one', 'line two' })
  eq(#note_bufs(), 1)
  child.type_keys(' mm') -- toggles closed
  eq(#h.floats(), 0)
end

T[':w in the note saves without E382 and keeps it open'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  h.cursor(1, 6)
  child.type_keys(' mm', 'abc', '<Esc>')
  child.cmd('w')
  eq(note_of(id), 'abc')
  eq(#h.floats(), 1)
  eq(child.bo.modified, false)
  eq(child.cmd_capture('messages'):find('E382') == nil, true)
end

T['an unmodified editor never overwrites a note changed elsewhere'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  child.lua('require("earmark.buffer").set_note(0, ..., "old")', { id })
  h.cursor(1, 6)
  child.type_keys(' mm')
  child.lua('require("earmark.buffer").set_note(vim.fn.bufnr("notes/doc.md"), ..., "new from API")', { id })
  child.type_keys('q')
  eq(note_of(id), 'new from API')
  child.type_keys(' mm')
  eq(h.floats()[1].lines, { 'new from API' })
end

T['clearing the text removes the note'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  child.lua('require("earmark.buffer").set_note(0, ..., "gone soon")', { id })
  h.cursor(1, 6)
  child.type_keys(' mm', 'dd', 'q')
  eq(note_of(id), vim.NIL)
end

T['leaving the float saves and closes it'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  h.cursor(1, 6)
  child.type_keys(' mm', 'typed', '<Esc>')
  child.cmd('wincmd p')
  h.settle()
  eq(#h.floats(), 0)
  eq(note_of(id), 'typed')
end

T[',s moves the note to a split and ,f back, keeping unsaved text'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  h.cursor(1, 6)
  child.type_keys(' mm', 'draft', '<Esc>')
  child.type_keys(',s')
  eq(#h.floats(), 0)
  eq(#child.api.nvim_list_wins(), 2)
  eq(child.api.nvim_buf_get_name(0), 'earmark://note/' .. id)
  eq(child.api.nvim_buf_get_lines(0, 0, -1, false), { 'draft' })
  child.type_keys(',f')
  eq(#h.floats(), 1)
  eq(#child.api.nvim_list_wins(), 2) -- source + float
  eq(h.floats()[1].lines, { 'draft' })
  child.type_keys('q')
  eq(note_of(id), 'draft')
end

T[':q in the split saves'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  h.cursor(1, 6)
  child.type_keys(' mm', 'split text', '<Esc>', ',s')
  child.cmd('q')
  h.settle()
  eq(note_of(id), 'split text')
  eq(#child.api.nvim_list_wins(), 1)
  eq(#note_bufs(), 0)
end

T['erase then restore keeps the note'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  child.lua('require("earmark.buffer").set_note(0, ..., "keep me")', { id })
  h.cursor(1, 6)
  child.type_keys(' mx')
  child.type_keys(' mu')
  local list = child.lua_get('vim.tbl_map(function(x) return x.annotation.note end, require("earmark").list(0))')
  eq(list, { 'keep me' })
end

T['a count picks among overlapping annotations'] = function()
  h.open()
  local outer = mark({ 0, 0 }, { 0, 19 }, '1')
  local inner = mark({ 0, 4 }, { 0, 9 }, '2')
  h.cursor(1, 6)
  child.type_keys(' mm')
  eq(h.floats()[1].name, 'earmark://note/' .. inner)
  child.type_keys('<Esc>', 'q')
  child.type_keys('2 mm')
  eq(h.floats()[1].name, 'earmark://note/' .. outer)
end

T['nothing under the cursor'] = function()
  h.open()
  h.cursor(1, 6)
  child.type_keys(' mm')
  eq(#h.floats(), 0)
end

T['tags.parse finds #tags and @idents, not headings, code or emails'] = function()
  local parse = function(s)
    return child.lua_get('require("earmark.tags").parse(...)', { s })
  end
  eq(parse('#todo first @A and #b/c.'), { tags = { 'todo', 'b/c' }, idents = { 'A' } })
  eq(parse('# Heading\nmail a@b.com, url x.com/p#frag'), { tags = {}, idents = {} })
  eq(parse('`#nope` text\n```\n#inside @code\n```\n#after'), { tags = { 'after' }, idents = {} })
  eq(parse('#a #a @B @B'), { tags = { 'a' }, idents = { 'B' } })
end

return T
