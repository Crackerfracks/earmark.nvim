-- Fixes from the audit against what Numhi was meant to do.
local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child)

local function name_of(label)
  return child.lua_get('require("earmark.buffer").display_name(0, { set = "vivid", label = ... })', { label })
end

local function msgs()
  child.lua('_G.msgs = {}; vim.notify = function(m) table.insert(_G.msgs, m) end')
end

T['a label named in one file is named in the project\'s other files'] = function()
  h.open()
  child.lua('require("earmark.names").save(0, { set = "vivid", label = "3" }, "Vague")')
  h.open({ 'other text here', 'more text' }, 'notes/other.md')
  h.cursor(1, 0)
  child.type_keys('3ghiw')
  eq(name_of('3'), 'Vague')
  -- cleared here: stays cleared while label 3 is in use in this file
  child.lua('require("earmark.buffer").rename_label(0, { set = "vivid", label = "3" }, nil)')
  h.cursor(2, 0)
  child.type_keys('3ghiw')
  eq(name_of('3'), '3')
end

T['first use in a new project still asks, pre-filled from the global history'] = function()
  child.lua([[
    local store = require('earmark.store')
    store.mru_push(require('earmark.config').options.storage_dir .. '/names.json', 'vivid/3', 'Elsewhere')
  ]])
  h.open()
  h.cursor(1, 10)
  child.type_keys('ghiw', '3', '<CR>')
  eq(child.lua_get('require("earmark.ui.prompt").active.stage'), 'name')
  eq(child.lua_get('vim.api.nvim_get_current_line()'), 'Elsewhere')
  child.type_keys('<CR>')
  h.settle()
  eq(name_of('3'), 'Elsewhere')
end

T['<Esc> while naming keeps the chosen label'] = function()
  h.open()
  h.cursor(1, 10)
  child.type_keys('ghiw', '3', '<CR>')
  eq(child.lua_get('require("earmark.ui.prompt").active.stage'), 'name')
  child.type_keys('<Esc>')
  h.settle()
  eq(#h.floats(), 0)
  eq(h.texts(), { { text = 'brown', label = '3', status = 'ok' } })
  eq(name_of('3'), '3')
end

T['<Tab> on a label with choices still asks for the choice'] = function()
  child.lua([[
    vim.fn.mkdir(_G.root .. '/.earmark/sets', 'p')
    vim.fn.writefile({ vim.json.encode({ labels = { { key = 'q1', name = 'Accuracy', choices = { 'Correct', 'Wrong' } } } }) },
      _G.root .. '/.earmark/sets/wf.json')
  ]])
  h.open()
  child.lua('require("earmark").use_set("wf")')
  h.cursor(1, 10)
  child.type_keys('ghiw', 'q1', '<Tab>')
  eq(child.lua_get('require("earmark.ui.prompt").active.stage'), 'choice')
  child.type_keys('<CR>')
  eq(child.lua_get('require("earmark.ui.prompt").active.stage'), 'name')
  child.type_keys('<C-u>', 'Accurate?', '<CR>')
  h.settle()
  local a = child.lua_get('require("earmark").list(0)[1].annotation')
  eq(a.values, { { set = 'wf', label = 'q1', choice = 'a' } })
end

T['linewise Visual erase takes whole lines and says how many'] = function()
  h.open()
  child.lua('require("earmark").annotate(0, { 0, 4 }, { 0, 9 }, { set = "vivid", label = "3" })')
  child.lua('require("earmark").annotate(0, { 0, 40 }, { 0, 43 }, { set = "vivid", label = "4" })')
  child.lua('require("earmark").annotate(0, { 1, 2 }, { 1, 8 }, { set = "vivid", label = "5" })')
  msgs()
  h.cursor(1, 20)
  child.type_keys('V', ' mx')
  eq(vim.tbl_map(function(t) return t.label end, h.texts()), { '5' })
  eq(child.lua_get('_G.msgs[#_G.msgs]'), 'earmark: erased 2 (restore with <leader>mu)')
  h.cursor(2, 4)
  child.type_keys(' mx')
  eq(child.lua_get('_G.msgs[#_G.msgs]'), 'earmark: erased 1 (restore with <leader>mu)')
end

T['ghh on an empty line opens nothing'] = function()
  h.open({ 'text', '', 'more' })
  msgs()
  h.cursor(2, 0)
  child.type_keys('ghh')
  h.settle()
  eq(#h.floats(), 0)
  eq(child.lua_get('_G.msgs[#_G.msgs]'), 'earmark: nothing to annotate there (no text)')
end

T[':Earmark log twice refreshes the same window'] = function()
  child.cmd('Earmark log')
  child.cmd('wincmd p')
  child.cmd('Earmark log')
  eq(child.api.nvim_buf_get_name(0), 'earmark://log')
  eq(#child.api.nvim_list_wins(), 2)
end

T[':Earmark info uses the names you gave labels'] = function()
  h.open()
  child.lua('require("earmark").annotate(0, { 0, 4 }, { 0, 9 }, { set = "vivid", label = "3" })')
  child.lua('require("earmark.buffer").rename_label(0, { set = "vivid", label = "3" }, "Vague")')
  msgs()
  h.cursor(1, 5)
  child.cmd('Earmark info')
  eq(child.lua_get('_G.msgs[1]'), 'earmark: Vague (vivid·3)  [ok]  "quick"')
end

T['a note typed after its annotation was erased goes with it to the trash'] = function()
  child.lua('require("earmark.config").options.note.layout = "split"')
  h.open()
  local id = child.lua_get('require("earmark").annotate(0, { 0, 4 }, { 0, 9 }, { set = "vivid", label = "3" }).id')
  local src = child.api.nvim_get_current_buf()
  h.cursor(1, 5)
  child.type_keys(' mm')
  child.lua('require("earmark").erase(...)', { src, { id } })
  child.type_keys('keep me', '<Esc>') -- an empty note starts in Insert mode
  child.cmd('write')
  child.lua('require("earmark").restore(...)', { src })
  eq(child.lua_get('require("earmark").get(...).note', { src, id }), 'keep me')
end

T['a float that you leave for an operator stays until the operator is done'] = function()
  child.lua([[
    _G.gone = 0
    _G.mode = 'no'
    vim.fn.mode = function() return _G.mode end
    local src = vim.api.nvim_get_current_win()
    _G.float = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), true,
      { relative = 'editor', row = 1, col = 1, width = 10, height = 2 })
    vim.api.nvim_set_current_win(src)
    require('earmark.ui.place').on_leave(_G.float, function() _G.gone = _G.gone + 1 end)
  ]])
  h.settle(250)
  eq(child.lua_get('_G.gone'), 0) -- still in the operator
  child.lua('vim.api.nvim_set_current_win(_G.float); _G.mode = "n"')
  h.settle(250)
  eq(child.lua_get('_G.gone'), 0) -- came back
  -- left for good
  child.lua([[
    vim.cmd('wincmd p')
    require('earmark.ui.place').on_leave(_G.float, function() _G.gone = _G.gone + 1 end)
  ]])
  h.settle(100)
  eq(child.lua_get('_G.gone'), 1)
end

T['the statusline shows a detached annotation without waiting for another key'] = function()
  child.o.laststatus = 2
  child.lua([[_G.stl = function() return require('earmark').statusline() end]])
  child.o.statusline = '%{%v:lua.stl()%}'
  h.open()
  child.lua('require("earmark").annotate(0, { 0, 4 }, { 0, 9 }, { set = "vivid", label = "3" })')
  h.cursor(1, 0)
  child.type_keys('dd')
  h.settle(400)
  local lines = child.get_screenshot().text
  local status = table.concat(lines[#lines - 1])
  eq(status:find('⚠', 1, true) ~= nil, true)
end

T['reloading after an outside edit leaves no highlight at the old place'] = function()
  h.open({ 'one two three', 'four five six' })
  child.lua('require("earmark").annotate(0, { 0, 4 }, { 0, 7 }, { set = "vivid", label = "3" })')
  child.lua('require("earmark.buffer").save(0)')
  child.lua([[
    local p = vim.api.nvim_buf_get_name(0)
    vim.fn.writefile({ 'zero', '', 'one two three', 'four five six' }, p)
  ]])
  child.cmd('edit')
  h.settle(300)
  local marks = child.lua_get([[vim.tbl_map(function(m) return { m[2], m[3] } end,
    vim.api.nvim_buf_get_extmarks(0, require('earmark.buffer').ns, 0, -1, {}))]])
  eq(marks, { { 2, 4 } })
end

T['a reload that keeps the buffer loaded (checktime, autoread) places annotations again'] = function()
  h.open({ 'one two three', 'four five six' })
  child.lua('require("earmark").annotate(0, { 0, 4 }, { 0, 7 }, { set = "vivid", label = "3" })')
  h.settle(300)
  child.lua('vim.fn.writefile({ "zero", "", "one two three", "four five six" }, vim.api.nvim_buf_get_name(0))')
  child.cmd('checktime')
  h.settle(300)
  local marks = child.lua_get([[vim.tbl_map(function(m) return { m[2], m[3], m[4].end_col } end,
    vim.api.nvim_buf_get_extmarks(0, require('earmark.buffer').ns, 0, -1, { details = true }))]])
  eq(marks, { { 2, 4, 7 } })
  eq(child.lua_get('require("earmark").list(0)[1].annotation.status'), 'ok')
end

T['an annotation edited into a different text is drawn stale right away'] = function()
  h.open({ 'alpha beta gamma delta' })
  child.lua('require("earmark").annotate(0, { 0, 6 }, { 0, 16 }, { set = "vivid", label = "3" })')
  h.settle(200)
  child.lua('vim.api.nvim_buf_set_text(0, 0, 7, 0, 15, { "q" })')
  h.settle(400)
  local hl = child.lua_get([[vim.api.nvim_buf_get_extmarks(0, require('earmark.buffer').ns, 0, -1, { details = true })[1][4].hl_group]])
  eq(hl:match('Stale$') ~= nil, true)
end

T['the global statusline keeps showing the annotated buffer while a float has focus'] = function()
  child.o.laststatus = 3
  h.open()
  child.lua('require("earmark").annotate(0, { 0, 4 }, { 0, 9 }, { set = "vivid", label = "3" })')
  local before = child.lua_get('require("earmark").statusline()')
  child.lua([[vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), true,
    { relative = 'editor', row = 1, col = 1, width = 10, height = 2 })]])
  eq(child.lua_get('require("earmark").statusline()'), before)
  eq(before ~= '', true)
end

return T
