-- Edge cases: annotations under real-world editing (formatters, :s, :g, J, undo chains,
-- Insert mode, hidden buffers) and what survives a save and reopen afterwards.
local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child)

local function root()
  return child.lua_get('_G.root')
end

local function mark(s, e, label)
  return child.lua_get('require("earmark").annotate(0, ...).id', { s, e, { set = 'vivid', label = label or '1' } })
end

local function save()
  child.lua('require("earmark.buffer").save(0)')
end

local function changed()
  child.lua('require("earmark.buffer").on_change(0)')
end

local function quotes()
  return vim.tbl_map(function(x)
    return x.text or false
  end, h.texts())
end

local function statuses()
  return vim.tbl_map(function(x)
    return x.status
  end, h.texts())
end

local function starts()
  return child.lua_get('vim.tbl_map(function(x) return x.s or false end, require("earmark").list(0))')
end

local function reopen()
  child.cmd('bwipeout!')
  child.cmd('edit ' .. root() .. '/notes/doc.md')
end

local function set_all(lines)
  child.api.nvim_buf_set_lines(0, 0, -1, false, lines)
end

---------------------------------------------------------------------------
-- Formatters: the whole buffer replaced at once
---------------------------------------------------------------------------

T['whole-buffer replace'] = MiniTest.new_set()

T['whole-buffer replace']['same text: every annotation in place'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  mark({ 0, 10 }, { 1, 8 }, '2') -- across lines
  mark({ 2, 12 }, { 2, 19 }, '3')
  set_all(H.LINES)
  h.settle()
  eq(quotes(), { 'quick', 'brown fox jumps over the lazy dog.\nA second', 'the end' })
  eq(statuses(), { 'ok', 'ok', 'ok' })
end

T['whole-buffer replace']['re-indented and re-wrapped lines'] = function()
  h.open({ 'def f(a,b):', '  return a+b # sum them up', 'x = f(1,2)' })
  mark({ 1, 9 }, { 1, 12 }) -- a+b
  mark({ 1, 15 }, { 1, 26 }, '2') -- sum them up
  set_all({ 'def f(a, b):', '    return a + b  # sum them up', '', 'x = f(1, 2)' })
  h.settle()
  eq(quotes(), { 'a + b', 'sum them up' })
end

T['whole-buffer replace']['lightly edited text keeps annotations, edited ones go stale'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  mark({ 1, 2 }, { 1, 8 }, '2')
  set_all({ 'The quick brown fox jumped over the lazy dog!', 'A 2nd line with some words.', 'Third line: the end.' })
  h.settle()
  eq(quotes(), { 'quick', '2nd' })
  eq(statuses(), { 'ok', 'stale' })
end

T['whole-buffer replace']['twice before the debounce runs'] = function()
  h.open()
  mark({ 1, 2 }, { 1, 8 })
  set_all({ 'header', H.LINES[1], H.LINES[2], H.LINES[3] })
  set_all({ 'header', 'more', H.LINES[1], H.LINES[2], H.LINES[3] })
  h.settle()
  eq(quotes(), { 'second' })
  eq(starts(), { { 3, 2 } })
end

T['whole-buffer replace']['format on save (replace in BufWritePre) keeps annotations on disk'] = function()
  h.open({ 'def f(a,b):', '  return a+b # sum them up', 'x = f(1,2)' })
  mark({ 1, 9 }, { 1, 12 }) -- a+b
  child.cmd('write')
  child.lua([[
    vim.api.nvim_create_autocmd('BufWritePre', { buffer = 0, callback = function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'def f(a, b):', '    return a + b  # sum them up', 'x = f(1, 2)' })
    end })
  ]])
  child.cmd('write')
  h.settle()
  eq(quotes(), { 'a + b' })
  reopen()
  eq(quotes(), { 'a + b' })
end

T['whole-buffer replace']['annotating right after a replace (before the debounce) loses nothing'] = function()
  h.open()
  mark({ 1, 2 }, { 1, 8 })
  set_all({ 'header', 'The quick brown fox jumps over the lazy dog.', 'A secnd line with some words.', H.LINES[3] })
  mark({ 1, 4 }, { 1, 9 }, '2')
  h.settle()
  eq(quotes(), { 'quick', 'secnd' })
end

T['whole-buffer replace']['saving right after a replace (before the debounce) loses nothing'] = function()
  h.open()
  mark({ 1, 2 }, { 1, 8 })
  set_all({ 'header', 'The quick brown fox jumps over the lazy dog.', 'A secnd line with some words.', H.LINES[3] })
  save()
  h.settle()
  eq(quotes(), { 'secnd' })
  local rec = vim.json.decode(table.concat(child.fn.readfile(root() .. '/.earmark/docs/notes/doc.md.json'), '\n'))
  eq({ rec.annotations[1].quote, rec.annotations[1].s, rec.annotations[1].status }, { 'secnd', { 2, 2 }, 'ok' })
end

---------------------------------------------------------------------------
-- Ex commands
---------------------------------------------------------------------------

T['ex'] = MiniTest.new_set()

T['ex'][':%s inside an annotated span'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 19 }) -- quick brown fox
  child.cmd('%s/brown/red/')
  h.settle()
  eq(quotes(), { 'quick red fox' })
end

T['ex'][':%s replacing a whole annotated word'] = function()
  h.open()
  mark({ 0, 10 }, { 0, 15 }) -- brown
  child.cmd('%s/brown/crimson/')
  h.settle()
  eq(quotes(), { 'crimson' })
  eq(statuses(), { 'stale' })
end

T['ex'][':%s across two annotations'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 }) -- quick
  mark({ 0, 10 }, { 0, 15 }, '2') -- brown
  child.cmd('%s/quick brown/slow grey/')
  h.settle()
  eq(#quotes(), 2)
  eq(vim.tbl_contains(statuses(), 'detached'), false)
  -- every annotation sits inside the replaced text
  for _, q in ipairs(quotes()) do
    eq(('slow grey'):find(q, 1, true) ~= nil, true)
  end
end

T['ex'][':%s on every line (formatter-like), with annotations on several lines'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  mark({ 1, 2 }, { 1, 8 }, '2')
  mark({ 2, 12 }, { 2, 19 }, '3')
  child.cmd([[%s/^/> /]])
  h.settle()
  eq(quotes(), { 'quick', 'second', 'the end' })
  child.cmd('undo')
  h.settle()
  eq(quotes(), { 'quick', 'second', 'the end' })
  eq(starts(), { { 0, 4 }, { 1, 2 }, { 2, 12 } })
end

T['ex'][':g/pat/d on the annotated line, then undo'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  mark({ 1, 2 }, { 1, 8 }, '2')
  child.cmd('g/quick/d')
  h.settle()
  eq(statuses(), { 'ok', 'detached' })
  child.cmd('undo')
  h.settle()
  eq(quotes(), { 'quick', 'second' })
  eq(starts(), { { 0, 4 }, { 1, 2 } })
end

T['ex']['deleting every line, then undo before the debounce'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  mark({ 2, 12 }, { 2, 19 }, '2')
  child.type_keys('ggdG')
  child.type_keys('u')
  h.settle()
  eq(quotes(), { 'quick', 'the end' })
end

T['ex']['deleting every line, saving, then undo'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  child.type_keys('ggdG')
  h.settle()
  child.cmd('write')
  child.type_keys('u')
  h.settle()
  eq(quotes(), { 'quick' })
  child.cmd('write')
  reopen()
  eq(quotes(), { 'quick' })
end

T['ex'][':m moves an annotated line'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('1m$')
  h.settle()
  eq(quotes(), { 'quick' })
  eq(starts(), { { 2, 4 } })
end

T['ex'][':sort reorders annotated lines'] = function()
  h.open({ 'zebra line', 'apple line', 'mango line' })
  mark({ 0, 0 }, { 0, 5 })
  mark({ 2, 0 }, { 2, 5 }, '2')
  child.cmd('sort')
  h.settle()
  local got = {}
  for _, x in ipairs(h.texts()) do
    got[x.label] = x.text
  end
  eq(got, { ['1'] = 'zebra', ['2'] = 'mango' })
end

T['ex'][':normal! J joins across a multi-line span'] = function()
  h.open()
  mark({ 0, 40 }, { 1, 8 }) -- "dog.\nA second"
  child.cmd('1normal! J')
  h.settle()
  eq(quotes(), { 'dog. A second' })
  eq(statuses(), { 'ok' })
end

T['ex']['J with the span starting at the joined line'] = function()
  h.open()
  mark({ 1, 0 }, { 1, 8 }) -- "A second"
  h.cursor(1, 0)
  child.type_keys('J')
  h.settle()
  eq(quotes(), { 'A second' })
end

T['ex']['gJ and then undo'] = function()
  h.open()
  mark({ 0, 40 }, { 1, 8 })
  h.cursor(1, 0)
  child.type_keys('gJ')
  h.settle()
  eq(quotes(), { 'dog.A second' })
  child.type_keys('u')
  h.settle()
  eq(quotes(), { 'dog.\nA second' })
end

---------------------------------------------------------------------------
-- Undo and redo
---------------------------------------------------------------------------

T['undo'] = MiniTest.new_set()

T['undo']['a chain of edits undone and redone step by step'] = function()
  h.open()
  mark({ 0, 10 }, { 0, 15 }) -- brown
  local seen = {}
  local function snap()
    h.settle(30)
    seen[#seen + 1] = { quotes()[1], starts()[1] }
  end
  snap()
  h.cursor(1, 0)
  child.type_keys('Onew first line<Esc>') -- 1
  snap()
  h.cursor(2, 0)
  child.type_keys('dw') -- 2: delete "The "
  snap()
  h.cursor(2, 6)
  child.type_keys('ciwdark<Esc>') -- 3: brown -> dark
  snap()
  child.type_keys('dd') -- 4: delete the line
  snap()
  child.type_keys('P') -- 5: put it back
  snap()
  local want = vim.deepcopy(seen)
  for i = #want - 1, 1, -1 do
    child.type_keys('u')
    h.settle(30)
    eq({ quotes()[1], starts()[1] }, want[i])
  end
  for i = 2, #want do
    child.type_keys('<C-r>')
    h.settle(30)
    eq({ quotes()[1], starts()[1] }, want[i])
  end
end

T['undo']['erase, edit, restore, undo the edit'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  child.lua('require("earmark").erase(0, { ... })', { id })
  h.cursor(1, 0)
  child.type_keys('Onew<Esc>')
  child.lua('require("earmark").restore(0)')
  eq(quotes(), { 'quick' })
  child.type_keys('u')
  h.settle()
  eq(quotes(), { 'quick' })
  eq(starts(), { { 0, 4 } })
end

T['undo']['undo past the point the file was loaded with annotations'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  reopen()
  h.cursor(1, 0)
  child.type_keys('Onew<Esc>')
  child.type_keys('uuuu')
  h.settle()
  eq(quotes(), { 'quick' })
  eq(starts(), { { 0, 4 } })
end

---------------------------------------------------------------------------
-- Insert mode and the debounce
---------------------------------------------------------------------------

T['insert'] = MiniTest.new_set()

T['insert']['typing inside a span widens it; quote catches up during Insert mode'] = function()
  child.lua('require("earmark.config").options.debounce_ms = 30')
  h.open()
  mark({ 0, 4 }, { 0, 15 }) -- quick brown
  h.cursor(1, 9)
  child.type_keys('i', ' and very')
  h.settle(100)
  eq(child.lua_get('require("earmark").list(0)[1].annotation.quote'), 'quick and very brown')
  child.type_keys('<Esc>')
  h.settle(60)
  eq(quotes(), { 'quick and very brown' })
end

T['insert']['typing a new line inside a span, then <Esc>'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 15 })
  h.cursor(1, 9)
  child.type_keys('i', '<CR>', '<Esc>')
  h.settle()
  eq(quotes(), { 'quick\n' .. child.lua_get('vim.fn.getline(2)'):match('^(.-brown)') })
end

T['insert']['<C-u> deleting the span in Insert mode, then typing'] = function()
  h.open({ 'quick brown' })
  mark({ 0, 0 }, { 0, 5 })
  h.cursor(1, 5)
  child.type_keys('a', '<C-w><C-w>')
  h.settle()
  child.type_keys('slow ', '<Esc>')
  h.settle()
  -- detached while gone, and it may come back when its text returns; never on wrong text
  local q = quotes()[1]
  eq(q == false or q == 'quick', true)
end

T['insert']['saving from Insert mode (autosave on TextChangedI) keeps positions'] = function()
  h.open()
  mark({ 1, 2 }, { 1, 8 })
  h.cursor(1, 0)
  child.type_keys('O', 'typed in insert')
  save()
  child.type_keys('<Esc>')
  h.settle()
  reopen()
  eq(quotes(), { 'second' })
end

---------------------------------------------------------------------------
-- Hidden buffers (notes kept open in floats, files reviewed in the background)
---------------------------------------------------------------------------

T['hidden'] = MiniTest.new_set()

T['hidden']['edits to a hidden buffer are tracked'] = function()
  h.open()
  mark({ 1, 2 }, { 1, 8 })
  local buf = child.lua_get('vim.api.nvim_get_current_buf()')
  h.open({ 'other' }, 'notes/other.md')
  child.api.nvim_buf_set_lines(buf, 0, 0, false, { 'one', 'two' })
  child.lua('require("earmark.buffer").on_change(...)', { buf })
  eq(child.lua_get('require("earmark").list(...)[1].s', { buf }), { 3, 2 })
end

T['hidden']['a hidden buffer replaced wholesale and then unloaded saves its annotations right'] = function()
  h.open()
  mark({ 1, 2 }, { 1, 8 })
  child.cmd('write')
  local buf = child.lua_get('vim.api.nvim_get_current_buf()')
  h.open({ 'other' }, 'notes/other.md')
  child.api.nvim_buf_set_lines(buf, 0, -1, false, { 'new first', H.LINES[1], H.LINES[2], H.LINES[3] })
  child.lua('vim.api.nvim_buf_call(..., function() vim.cmd("silent write") end)', { buf })
  child.cmd('bwipeout! ' .. buf)
  child.cmd('edit ' .. root() .. '/notes/doc.md')
  eq(quotes(), { 'second' })
  eq(starts(), { { 2, 2 } })
end

T['hidden']['replaced while hidden, repaired by the time it is shown again'] = function()
  h.open()
  mark({ 1, 2 }, { 1, 8 })
  local buf = child.lua_get('vim.api.nvim_get_current_buf()')
  h.open({ 'other' }, 'notes/other.md')
  child.api.nvim_buf_set_lines(buf, 0, -1, false, { 'new first', H.LINES[1], H.LINES[2], H.LINES[3] })
  child.cmd('buffer ' .. buf)
  h.settle()
  eq(quotes(), { 'second' })
  eq(starts(), { { 2, 2 } })
end

T['hidden']['replaced while shown in a float (current window elsewhere)'] = function()
  h.open()
  mark({ 1, 2 }, { 1, 8 })
  local buf = child.lua_get('vim.api.nvim_get_current_buf()')
  h.open({ 'other' }, 'notes/other.md')
  child.lua('_G.fw = vim.api.nvim_open_win(..., false, { relative = "editor", row = 1, col = 1, width = 40, height = 5 })', { buf })
  child.api.nvim_buf_set_lines(buf, 0, -1, false, { 'new first', H.LINES[1], H.LINES[2], H.LINES[3] })
  h.settle()
  local got = child.lua_get('vim.tbl_map(function(x) return x.s or false end, require("earmark").list(...))', { buf })
  -- repaired without TextChanged (which only fires for the current buffer)
  eq(got[1], { 2, 2 })
  child.lua('require("earmark.buffer").save(...)', { buf })
  eq(child.lua_get('require("earmark").list(...)[1].s', { buf }), { 2, 2 })
end

T['hidden']['annotating a hidden buffer by number'] = function()
  h.open()
  local buf = child.lua_get('vim.api.nvim_get_current_buf()')
  h.open({ 'other' }, 'notes/other.md')
  child.lua('require("earmark").annotate(..., { 0, 4 }, { 0, 9 }, { set = "vivid", label = "1" })', { buf })
  child.lua('require("earmark.buffer").save(...)', { buf })
  child.cmd('bwipeout! ' .. buf)
  child.cmd('edit ' .. root() .. '/notes/doc.md')
  eq(quotes(), { 'quick' })
end

T['hidden']['an unloaded buffer (bufadd without bufload) is not annotated or saved over'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  child.cmd('bwipeout!')
  child.lua('_G.b = vim.fn.bufadd(_G.root .. "/notes/doc.md")')
  child.lua('require("earmark.buffer").get(_G.b)')
  child.lua('require("earmark.buffer").save(_G.b)')
  child.lua('vim.api.nvim_exec_autocmds("VimLeavePre", {})')
  child.cmd('edit ' .. root() .. '/notes/doc.md')
  eq(quotes(), { 'quick' })
end

return T
