-- Modes and odd contexts: the cmdline window, cancelled operators, Visual selections over
-- multibyte text, repeats, counts, macros, :normal, readonly/help/terminal/quickfix
-- buffers, one buffer in two windows, folds, conceal, wrap, 'list' and 'virtualedit'.
local H = dofile('tests/helpers.lua')
local E = dofile('tests/edge_helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child, "{ prompt = { ask_name = 'never' } }")

local function mark(s, e, label)
  return child.lua_get('require("earmark").annotate(0, ...).id', { s, e, { set = 'vivid', label = label or '3' } })
end

local function lines()
  return child.api.nvim_buf_get_lines(0, 0, -1, false)
end

local function prompt_active()
  return child.lua_get('require("earmark.ui.prompt").active ~= nil')
end

local MB = { 'héllo wörld ñandú', 'ça va très bien', '日本語のテキスト' }

---------------------------------------------------------------------------
-- Cmdline window, operator-pending
---------------------------------------------------------------------------

T['cmdline window: gh, ghh, the hover, notes and the palette decline or work'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  child.lua('require("earmark").set_note(0, ..., "n")', { id })
  E.watch(child)
  child.type_keys('q:')
  child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, { "echo 1", "echo 2" })')
  h.settle()
  child.lua('vim.v.errmsg = ""')
  for _, keys in ipairs({ { 'ghiw' }, { 'ghh' }, { '3ghiw' }, { ' mm' }, { ' mc' }, { ' m?' }, { ' mi' }, { ' mp' } }) do
    child.lua('pcall(vim.api.nvim_input, ...)', { table.concat(keys) })
    h.settle(150)
    child.lua('pcall(vim.api.nvim_input, "<Esc><Esc>")')
    h.settle(100)
  end
  child.type_keys('j', 'k')
  h.settle(200)
  child.lua('pcall(vim.cmd, "quit")')
  h.settle()
  E.no_errors(child)
  eq(child.fn.getcmdwintype(), '')
end

T['operator-pending: gh<Esc>, 3gh<Esc> and ghh<Esc> leave nothing behind'] = function()
  h.open()
  h.cursor(1, 10)
  E.watch(child)
  child.type_keys('gh', '<Esc>')
  child.type_keys('3gh', '<Esc>')
  h.settle()
  eq(#h.floats(), 0) -- the count hint closed
  child.type_keys('gh', 'i', '<Esc>')
  h.settle()
  eq(child.fn.mode(), 'n')
  eq(#h.floats(), 0)
  eq(lines(), H.LINES)
  child.type_keys('5ghiw')
  eq(#h.texts(), 1)
  E.no_errors(child)
end

T['. right after a cancelled gh repeats the last annotation silently'] = function()
  h.open()
  E.watch(child)
  h.cursor(1, 10)
  child.type_keys('ghiw', '5', '<CR>')
  h.settle()
  h.cursor(2, 2)
  child.type_keys('gh', '<Esc>', '.')
  h.settle()
  eq(prompt_active(), false)
  eq(vim.tbl_map(function(t) return t.text .. '=' .. t.label end, h.texts()), { 'brown=5', 'second=5' })
  -- and after :normal leaves an operator waiting
  h.cursor(3, 0)
  child.cmd('normal gh')
  child.type_keys('.')
  h.settle()
  eq(prompt_active(), false)
  child.cmd('normal 3gh')
  h.settle()
  eq(#h.floats(), 0) -- the count hint went with it
  E.no_errors(child)
  eq(#h.texts(), 3)
end

---------------------------------------------------------------------------
-- Visual selections over multibyte text
---------------------------------------------------------------------------

T['Visual charwise, linewise and blockwise over multibyte text'] = function()
  h.open(MB)
  E.watch(child)
  h.cursor(1, 0)
  child.type_keys('v', 'e', '3gh') -- héllo
  h.cursor(2, 0)
  child.type_keys('V', '4gh')
  h.cursor(1, 7) -- "w" (after the two-byte é)
  child.type_keys('<C-v>', 'j', 'l', '5gh')
  h.cursor(3, 0)
  child.type_keys('v', 'l', 'l', 'gh', '6', '<CR>')
  h.settle()
  local got = {}
  for _, t in ipairs(h.texts()) do
    got[#got + 1] = t.text .. '=' .. t.label
  end
  table.sort(got)
  local want = { 'héllo=3', 'ça va très bien=4', 'wö=5', 'tr=5', '日本語=6' }
  table.sort(want)
  eq(got, want)
  -- every span starts and ends on a character boundary
  for _, x in ipairs(child.lua_get('require("earmark").list(0)')) do
    local line = lines()[x.s[1] + 1]
    eq(vim.str_utf_start(line, x.s[2] + 1), 0)
    local eline = lines()[x.e[1] + 1]
    if x.e[2] < #eline then eq(vim.str_utf_start(eline, x.e[2] + 1), 0) end
  end
  E.no_errors(child)
end

T['Visual block past the end of short lines with virtualedit=all'] = function()
  h.open({ 'short', 'a much longer line here', 'mid line' })
  child.o.virtualedit = 'all'
  E.watch(child)
  h.cursor(1, 2)
  child.type_keys('<C-v>', '2j', '15l', '3gh')
  h.settle()
  local got = vim.tbl_map(function(t) return t.text end, h.texts())
  eq(got, { 'ort', 'much longer line', 'd line' })
  -- the cursor beyond the end of a line: gh, the hover and a note
  child.type_keys('gg', '20l')
  child.type_keys('ghh', '4', '<CR>')
  h.settle()
  child.type_keys('gg', '30l', ' mi')
  h.settle()
  child.lua('pcall(vim.cmd, "normal q")')
  E.no_errors(child)
end

T['Visual block to the end of lines of different lengths ($)'] = function()
  h.open({ 'short', 'a much longer line', '', 'mid ñ line' })
  E.watch(child)
  h.cursor(1, 1)
  child.type_keys('<C-v>', '3j', '$', '3gh')
  h.settle()
  eq(vim.tbl_map(function(t) return t.text end, h.texts()), { 'hort', ' much longer line', 'id ñ line' })
  -- through the prompt (the operator is replayed after it), and a normal motion after it
  child.lua('require("earmark").erase(0, vim.tbl_map(function(x) return x.annotation.id end, require("earmark").list(0)))')
  h.cursor(1, 1)
  child.type_keys('<C-v>', '3j', '$', 'gh', '5', '<CR>')
  h.settle()
  eq(vim.tbl_map(function(t) return t.text end, h.texts()), { 'hort', ' much longer line', 'id ñ line' })
  h.cursor(2, 2)
  child.type_keys('4ghiw')
  eq(#h.texts(), 4)
  E.no_errors(child)
end

T['rightleft windows'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  child.lua('require("earmark").set_note(0, ..., "n")', { id })
  child.wo.rightleft = true
  E.watch(child)
  h.cursor(1, 5)
  child.type_keys('l')
  h.settle(250)
  h.cursor(1, 12)
  child.type_keys('ghiw', '5', '<CR>')
  h.settle()
  child.type_keys(' mm', '<Esc>', 'q')
  h.settle()
  E.no_errors(child)
end

---------------------------------------------------------------------------
-- Repeats, counts, macros, :normal
---------------------------------------------------------------------------

T['. after an undo repeats the annotation'] = function()
  h.open()
  E.watch(child)
  h.cursor(1, 10)
  child.type_keys('ghiw', '5', '<CR>')
  h.settle()
  child.type_keys('u')
  h.cursor(2, 2)
  child.type_keys('.')
  h.settle()
  eq(#h.texts(), 2)
  child.type_keys('x', 'u', 'w', '.')
  h.settle()
  E.no_errors(child)
  eq(lines()[2]:sub(1, 2), 'A ') -- `.` after `x u` deletes again, as Vim does
end

T['a count larger than the set changes no text'] = function()
  h.open()
  child.lua('require("earmark").use_set("feedback")')
  h.cursor(1, 10)
  child.lua('_G.msgs = {} vim.notify = function(m) table.insert(_G.msgs, m) end')
  child.type_keys('42ghiw')
  h.settle()
  eq(lines(), H.LINES) -- the motion is not typed as text
  eq(child.fn.mode(), 'n')
  eq(#h.texts(), 0)
  eq(child.lua_get('_G.msgs[1]'):find('no label 42', 1, true) ~= nil, true)
  child.type_keys('999ghh')
  h.settle()
  eq(lines(), H.LINES)
  child.type_keys('v', 'e', '77gh', '<Esc>')
  eq(lines(), H.LINES)
  eq(#h.texts(), 0)
end

T['a macro recording gh with the prompt replays it'] = function()
  h.open()
  E.watch(child)
  h.cursor(1, 0)
  child.type_keys('qa', 'ghiw', '5', '<CR>')
  h.settle()
  child.type_keys('j0', 'q')
  eq(#h.texts(), 1)
  child.type_keys('@a')
  h.settle()
  if prompt_active() then child.type_keys('<CR>') end
  h.settle()
  E.no_errors(child)
  eq(lines(), H.LINES)
  local got = vim.tbl_map(function(t) return t.text .. '=' .. t.label end, h.texts())
  eq(got, { 'The=5', 'A=5' })
end

T['a macro with a count gh replays it'] = function()
  h.open()
  E.watch(child)
  h.cursor(1, 0)
  child.type_keys('qa', '4ghiw', 'j0', 'q', '@a', '@@')
  h.settle()
  E.no_errors(child)
  eq(vim.tbl_map(function(t) return t.text end, h.texts()), { 'The', 'A', 'Third' })
end

T[':normal 3ghiw and :normal ghiw'] = function()
  h.open()
  E.watch(child)
  h.cursor(1, 10)
  child.cmd('normal 3ghiw')
  eq(h.texts(), { { text = 'brown', label = '3', status = 'ok' } })
  h.cursor(2, 2)
  child.cmd('normal ghiw')
  h.settle()
  if prompt_active() then child.type_keys('6', '<CR>') end
  h.settle()
  E.no_errors(child)
  eq(lines(), H.LINES)
end

---------------------------------------------------------------------------
-- Special buffers
---------------------------------------------------------------------------

local function exercise()
  h.cursor(1, 0)
  child.type_keys('3ghiw')
  child.type_keys('ghh')
  h.settle()
  if prompt_active() then child.type_keys('4', '<CR>') end
  h.settle()
  child.lua('local x = require("earmark").list(0)[1] if x then require("earmark").set_note(0, x.annotation.id, "n") end')
  child.type_keys('l')
  h.settle(200)
  child.type_keys(' mm')
  h.settle()
  if child.lua_get('require("earmark.ui.note").active ~= nil') then child.type_keys('<Esc>', 'q') end
  h.settle()
  child.type_keys(' mi')
  h.settle()
  child.lua('pcall(require("earmark.ui.hover").hide)')
  child.type_keys(' mc', 'q')
  child.type_keys(' mx')
  h.settle()
end

T['readonly and nomodifiable buffers'] = function()
  h.open()
  child.bo.readonly = true
  child.bo.modifiable = false
  E.watch(child)
  exercise()
  E.no_errors(child)
  eq(lines(), H.LINES)
end

T['a help buffer'] = function()
  child.cmd('help help')
  child.cmd('only')
  E.watch(child)
  exercise()
  E.no_errors(child)
end

T['a terminal buffer is never annotated, without errors'] = function()
  child.cmd('terminal')
  h.settle(200)
  E.watch(child)
  child.type_keys('<C-\\><C-n>')
  exercise()
  E.no_errors(child)
  eq(#child.lua_get('require("earmark").list(0)'), 0)
  eq(prompt_active(), false)
end

T['a quickfix buffer is never annotated, without errors'] = function()
  h.open()
  child.lua([[local name = vim.api.nvim_buf_get_name(0)
    vim.fn.setqflist({ { filename = name, lnum = 1, text = 'one' }, { filename = name, lnum = 2, text = 'two' } })]])
  child.cmd('copen')
  E.watch(child)
  exercise()
  E.no_errors(child)
  eq(#child.lua_get('require("earmark").list(0)'), 0)
end

T['the prompt and note on a buffer opened with -R (readonly)'] = function()
  h.open()
  child.cmd('view')
  E.watch(child)
  h.cursor(1, 10)
  child.type_keys('ghiw', '5', '<CR>')
  h.settle()
  eq(#h.texts(), 1)
  child.type_keys(' mm', 'note text', '<Esc>', 'q')
  h.settle()
  eq(child.lua_get('require("earmark").list(0)[1].annotation.note'), 'note text')
  E.no_errors(child)
end

---------------------------------------------------------------------------
-- Windows and display options
---------------------------------------------------------------------------

T['one buffer in two windows: hover and indicators in both'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  child.lua('require("earmark").set_note(0, ..., "shared note")', { id })
  child.cmd('vsplit')
  E.watch(child)
  h.cursor(1, 5)
  child.type_keys('l')
  h.settle(250)
  local w1 = child.lua_get('require("earmark.ui.hover").shown.src_win')
  child.cmd('wincmd l')
  h.cursor(1, 6)
  child.type_keys('l')
  h.settle(250)
  local w2 = child.lua_get('require("earmark.ui.hover").shown.src_win')
  eq(w1 ~= w2, true)
  eq(w2, child.api.nvim_get_current_win())
  -- the note from the second window, edited, shows in both
  child.type_keys(' mm', 'G', 'A', ' edited', '<Esc>', 'q')
  h.settle()
  eq(child.lua_get('require("earmark").get(0, ...).note', { id }), 'shared note edited')
  child.cmd('wincmd h')
  child.type_keys('h', 'l')
  h.settle(250)
  E.no_errors(child)
end

T['one buffer in a wide and a narrow window: indicator lines settle'] = function()
  h.open({ ('word '):rep(14) .. 'end', 'second line' })
  local id = mark({ 0, 70 }, { 0, 73 })
  child.lua('require("earmark").set_note(0, ..., "n")', { id })
  child.lua('require("earmark.config").options.indicators.tags = true')
  child.lua('require("earmark").set_tags(0, ..., { "a-rather-long-tag", "another-one" })', { id })
  -- the indicators fit after the line in the wide window, not in the narrow one
  child.cmd('vsplit')
  child.cmd('vertical resize 40')
  child.lua('vim.wo.wrap = true')
  E.watch(child)
  h.settle(300)
  -- count the indicator lines placed from now on
  child.lua([[
    _G.placed = 0
    local set = vim.api.nvim_buf_set_extmark
    vim.api.nvim_buf_set_extmark = function(b, ns, ...)
      if ns == require('earmark.render').ns_lines then _G.placed = _G.placed + 1 end
      return set(b, ns, ...)
    end
  ]])
  for _ = 1, 5 do
    child.cmd('redraw')
    h.settle(60)
  end
  -- not removed by one window and put back by the other, again and again
  eq(child.lua_get('_G.placed') <= 1, true)
  -- the narrow window shows them on a line of their own
  eq(child.lua_get('#vim.api.nvim_buf_get_extmarks(0, require("earmark.render").ns_lines, 0, -1, {})'), 1)
  E.no_errors(child)
end

T['folds over annotated lines'] = function()
  h.open({ 'one', 'two words here', 'three', 'four', 'five' })
  local id = mark({ 1, 4 }, { 1, 9 })
  child.lua('require("earmark").set_note(0, ..., "folded")', { id })
  child.cmd('2,4fold')
  E.watch(child)
  h.cursor(2, 4)
  h.settle(250)
  child.type_keys('j', 'k')
  h.settle(250)
  child.type_keys(' mi')
  h.settle()
  child.lua('pcall(require("earmark.ui.hover").hide)')
  child.type_keys(' mm')
  h.settle()
  child.type_keys('<Esc>', 'q')
  child.type_keys('ghh', '5', '<CR>') -- a closed fold: the line under the cursor
  h.settle()
  child.type_keys('3ghj')
  h.settle()
  child.type_keys(' mn', ' mN')
  E.no_errors(child)
end

T['conceal, nowrap, list with tabs, number and signcolumn'] = function()
  h.open({ '\tTabbed **bold** text', '\t\tmore\ttabs\there', ('long '):rep(60) })
  child.lua([[
    vim.wo.conceallevel = 2
    vim.wo.list = true
    vim.wo.listchars = 'tab:>-,trail:~'
    vim.wo.number, vim.wo.signcolumn = true, 'yes:3'
  ]])
  local id = mark({ 0, 8 }, { 0, 16 })
  child.lua('require("earmark").set_note(0, ..., "on bold")', { id })
  E.watch(child)
  for _, wrap in ipairs({ true, false }) do
    child.wo.wrap = wrap
    h.cursor(1, 9)
    h.settle(250)
    child.type_keys('l')
    h.settle(250)
    child.type_keys('j', '3ghiw', 'G', '$', 'ghiw', '7', '<CR>')
    h.settle()
    child.type_keys('$', ' mi')
    h.settle()
    child.lua('pcall(require("earmark.ui.hover").hide)')
  end
  E.no_errors(child)
end

T['hover while the completion menu is open'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  child.lua('require("earmark").set_note(0, ..., "n")', { id })
  E.watch(child)
  h.cursor(1, 5)
  child.type_keys('l')
  h.settle(250)
  child.type_keys('o', 'w', '<C-n>')
  h.settle(250)
  eq(child.fn.pumvisible(), 1)
  eq(child.lua_get('require("earmark.ui.hover").shown'), vim.NIL)
  child.type_keys('<C-e>', '<Esc>', 'u')
  h.settle(250)
  E.no_errors(child)
end

return T
