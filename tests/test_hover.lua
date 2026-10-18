local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child)

local function mark(s, e, label)
  return child.lua_get('require("earmark").annotate(0, ...).id', { s, e, { set = 'vivid', label = label or '3' } })
end

local function hover()
  return child.lua_get([[(function()
    local S = require('earmark.ui.hover').shown
    if not S or not vim.api.nvim_win_is_valid(S.win) then return vim.NIL end
    local c = vim.api.nvim_win_get_config(S.win)
    return { row = c.row, col = c.col, width = c.width, height = c.height, focusable = c.focusable,
      lines = vim.api.nvim_buf_get_lines(S.buf, 0, -1, false) }
  end)()]])
end

local function move(keys)
  child.type_keys(keys)
  h.settle(200)
end

T['appears on a named annotation, not on a plain one'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 }, '3')
  mark({ 1, 2 }, { 1, 8 }, '4')
  child.lua('require("earmark.buffer").rename_label(0, { set = "vivid", label = "3" }, "Factually Inaccurate")')
  h.cursor(2, 0)
  move('ll') -- onto the plain one
  eq(hover(), vim.NIL)
  h.cursor(1, 0)
  move('5l')
  local hv = hover()
  eq(hv.lines[1]:find('Factually Inaccurate', 1, true) ~= nil, true)
  eq(hv.lines[1]:find('vivid·3', 1, true) ~= nil, true)
  eq(hv.focusable, false)
  eq(child.api.nvim_win_get_config(0).relative, '') -- focus stays in the text
end

T['shows tags, identifiers, pencil and the note'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  child.lua('require("earmark.buffer").set_note(0, ..., "check this #todo @A\\nsecond line")', { id })
  h.cursor(1, 0)
  move('5l')
  local hv = hover()
  eq(hv.lines[1]:find('#todo', 1, true) ~= nil, true)
  eq(hv.lines[1]:find('@A', 1, true) ~= nil, true)
  eq(hv.lines[1]:find('✎', 1, true) ~= nil, true)
  eq(vim.list_slice(hv.lines, 2), { 'check this #todo @A', 'second line' })
end

T['stays while moving within the span, closes when leaving it'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  child.lua('require("earmark.buffer").set_note(0, ..., "n")', { id })
  h.cursor(1, 4)
  move('l')
  local win = child.lua_get('require("earmark.ui.hover").shown.win')
  move('l')
  move('l')
  eq(child.lua_get('require("earmark.ui.hover").shown.win'), win)
  child.type_keys('w') -- next word: off the span, closes at once
  eq(hover(), vim.NIL)
end

T['stays inside the window: above the span near the bottom'] = function()
  local lines = {}
  for i = 1, 60 do
    lines[i] = 'line ' .. i .. ' with some words in it'
  end
  h.open(lines)
  child.cmd('normal! G')
  local id = mark({ 59, 5 }, { 59, 7 })
  child.lua('require("earmark.buffer").set_note(0, ..., "one\\ntwo\\nthree\\nfour")', { id })
  move('0w')
  local hv = hover()
  local wh = child.api.nvim_win_get_height(0)
  local srow = child.fn.winline() - 1 -- 0-based window row of the cursor
  eq(hv.row + hv.height + 2 <= srow, true) -- entirely above the cursor line
  eq(hv.row >= 0 and hv.row + hv.height + 2 <= wh, true)
  eq(hv.col + hv.width + 2 <= child.api.nvim_win_get_width(0), true)
end

T['closes on Insert mode and on operator-pending'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  child.lua('require("earmark.buffer").set_note(0, ..., "n")', { id })
  h.cursor(1, 4)
  move('l')
  eq(hover() ~= vim.NIL, true)
  child.type_keys('d')
  eq(hover(), vim.NIL)
  child.type_keys('<Esc>')
  h.settle(200)
  eq(hover() ~= vim.NIL, true) -- back in Normal mode on the same span
  child.type_keys('i')
  eq(hover(), vim.NIL)
end

T['<leader>mi shows details for any annotation and focuses; q closes'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  h.cursor(1, 6)
  child.type_keys(' mi')
  local hv = hover()
  eq(hv.focusable, true)
  eq(child.api.nvim_win_get_config(0).relative ~= '', true)
  child.type_keys('q')
  eq(hover(), vim.NIL)
  eq(child.api.nvim_win_get_config(0).relative, '')
end

T['overlapping annotations are numbered, innermost first'] = function()
  h.open()
  mark({ 0, 0 }, { 0, 19 }, '1')
  mark({ 0, 4 }, { 0, 9 }, '2')
  h.cursor(1, 6)
  child.type_keys(' mi')
  local hv = hover()
  eq(hv.lines[1]:sub(1, 3), '①')
  eq(hv.lines[1]:find('vivid·2', 1, true) ~= nil, true)
  eq(hv.lines[3]:sub(1, 3), '②')
end

T['<leader>mh turns automatic hover off and on'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  child.lua('require("earmark.buffer").set_note(0, ..., "n")', { id })
  child.type_keys(' mh')
  h.cursor(1, 4)
  move('l')
  eq(hover(), vim.NIL)
  child.type_keys(' mh')
  move('l')
  eq(hover() ~= vim.NIL, true)
end

T['the note editor and the prompt hide it'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  child.lua('require("earmark.buffer").set_note(0, ..., "n")', { id })
  h.cursor(1, 4)
  move('l')
  child.type_keys(' mm')
  h.settle(200)
  eq(hover(), vim.NIL)
  child.type_keys('q')
  h.settle(200)
  child.type_keys('ghiw')
  h.settle(200)
  eq(hover(), vim.NIL)
end

T['stale annotations say so'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  h.cursor(1, 4)
  child.type_keys('ciw', 'slowish', '<Esc>')
  h.settle(100)
  child.type_keys(' mi')
  local hv = hover()
  eq(hv.lines[1]:find('stale', 1, true) ~= nil, true)
  eq(hv.lines[2], 'was: "quick"')
end

return T
