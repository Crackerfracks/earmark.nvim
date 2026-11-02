-- The note editor next to other floats: a picker opened from it (an emoji picker, any
-- vim.ui.select float) keeps it open, and the hover can be entered (flash.nvim, a click,
-- <C-w>w) to edit its note at the same place.
local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child, "{ prompt = { ask_name = 'never' } }")

local LINES = { 'The quick brown fox jumps over the lazy dog.', 'zebra line in main', 'Third line: the end.' }

local function mark(note)
  local id = child.lua_get('require("earmark").annotate(0, {0,4}, {0,9}, { set = "vivid", label = "3" }).id')
  if note then child.lua('require("earmark").set_note(0, ...)', { id, note }) end
  return id
end

local function cur_name()
  return child.lua_get('vim.api.nvim_buf_get_name(0)')
end

local function note_of(id)
  return child.lua_get('require("earmark").get(0, ...).note', { id })
end

-- a picker in the style of telescope / vim.ui.select floats: takes focus, then closes and
-- the caller inserts the choice where the cursor was
local PICKER = [[
  _G.pick_and_insert = function(text, back)
    local from = vim.api.nvim_get_current_win()
    local mode = vim.api.nvim_get_mode().mode
    local b = vim.api.nvim_create_buf(false, true)
    local w = vim.api.nvim_open_win(b, true, { relative = 'editor', row = 2, col = 2, width = 20, height = 3 })
    vim.cmd('stopinsert')
    vim.schedule(function()
      vim.api.nvim_win_close(w, true)
      if back then vim.api.nvim_set_current_win(from) end
      vim.schedule(function()
        if vim.api.nvim_get_current_win() == from then vim.api.nvim_put({ text }, 'c', true, true) end
        _G.picked = true
      end)
    end)
  end
]]

T['a picker opened from the note keeps it open and inserts into it'] = function()
  h.open(LINES)
  local id = mark()
  h.cursor(1, 5)
  child.lua(PICKER)
  child.type_keys(' mm') -- no note yet: Insert mode
  child.type_keys('hi ')
  child.lua('_G.pick_and_insert("😀", true)')
  child.lua('vim.wait(500, function() return _G.picked end)')
  eq(cur_name():match('^earmark://note/') ~= nil, true)
  eq(child.lua_get('vim.api.nvim_get_current_line()'), 'hi 😀')
  eq(child.lua_get('vim.api.nvim_buf_get_lines(vim.fn.bufnr("doc.md"), 0, 1, false)[1]'), LINES[1])
  child.type_keys('<Esc>', 'q')
  eq(note_of(id), 'hi 😀')
end

T['a picker that closes into the note window without being sent back still keeps it'] = function()
  h.open(LINES)
  mark('x')
  h.cursor(1, 5)
  child.lua(PICKER)
  child.type_keys(' mm')
  child.lua('_G.pick_and_insert("y", false)') -- closing the picker returns to the note by itself
  child.lua('vim.wait(500, function() return _G.picked end)')
  eq(cur_name():match('^earmark://note/') ~= nil, true)
end

T['going from the picker to the text closes the note and saves it'] = function()
  h.open(LINES)
  local id = mark()
  h.cursor(1, 5)
  child.type_keys(' mm', 'kept', '<Esc>')
  child.lua([[
    local b = vim.api.nvim_create_buf(false, true)
    _G.pw = vim.api.nvim_open_win(b, true, { relative = 'editor', row = 2, col = 2, width = 20, height = 3 })
  ]])
  h.settle()
  eq(#h.floats(), 2) -- note + picker
  child.lua('vim.cmd("wincmd t")') -- straight to the text window
  h.settle()
  eq(cur_name():match('doc%.md$') ~= nil, true)
  eq(note_of(id), 'kept')
  eq(child.lua_get('require("earmark.ui.note").active'), vim.NIL)
  child.lua('pcall(vim.api.nvim_win_close, _G.pw, true)')
end

T['leaving the note for the text still closes it'] = function()
  h.open(LINES)
  local id = mark()
  h.cursor(1, 5)
  child.type_keys(' mm', 'gone', '<Esc>')
  child.type_keys('<C-w>p')
  h.settle()
  eq(child.lua_get('require("earmark.ui.note").active'), vim.NIL)
  eq(note_of(id), 'gone')
  eq(#h.floats(), 0)
end

local function hover()
  return child.lua_get('require("earmark.ui.hover").shown and require("earmark.ui.hover").shown.win or vim.NIL')
end

T['entering the hover on a note line edits that note at the same place'] = function()
  h.open(LINES)
  local id = mark('alpha beta\ndelta zebra epsilon')
  h.cursor(1, 5)
  h.settle(600)
  local win = hover()
  eq(win ~= vim.NIL, true)
  eq(child.lua_get('vim.api.nvim_win_get_config(...).focusable', { win }), true)
  -- what flash.nvim does for a jump: enter the window, put the cursor on the match
  local row = child.lua_get([[(function()
    local S = require('earmark.ui.hover').shown
    for r, x in pairs(S.rows) do if x.line == 2 then return r end end
  end)()]])
  child.lua('vim.api.nvim_set_current_win(...); vim.api.nvim_win_set_cursor(0, { ' .. (row + 1) .. ', 6 })', { win })
  h.settle()
  eq(cur_name(), 'earmark://note/' .. id)
  eq(child.lua_get('vim.api.nvim_win_get_cursor(0)'), { 2, 6 })
  eq(child.lua_get('vim.api.nvim_get_mode().mode'), 'n')
  eq(hover(), vim.NIL)
  child.type_keys('cw', 'ZEBRA', '<Esc>', 'q')
  eq(note_of(id), 'alpha beta\ndelta ZEBRA epsilon')
end

T['entering the hover on its heading keeps it focused; <CR> opens the note'] = function()
  h.open(LINES)
  local id = mark('alpha')
  h.cursor(1, 5)
  h.settle(600)
  local win = hover()
  child.lua('vim.api.nvim_set_current_win(...)', { win })
  h.settle()
  eq(child.lua_get('vim.api.nvim_get_current_win()'), win)
  eq(child.lua_get('require("earmark.ui.hover").shown.focused'), true)
  child.type_keys('<CR>')
  h.settle()
  eq(cur_name(), 'earmark://note/' .. id)
end

T['the hover stays while the cursor goes into it and closes when it leaves'] = function()
  h.open(LINES)
  mark('alpha')
  h.cursor(1, 5)
  h.settle(600)
  local win = hover()
  child.type_keys('<C-w>w')
  h.settle()
  eq(child.lua_get('vim.api.nvim_get_current_win()'), win)
  child.type_keys('<C-w>p')
  h.settle()
  eq(hover(), vim.NIL)
  eq(#h.floats(), 0)
end

T['flash.nvim labels the hover and a jump there opens the note'] = function()
  if vim.fn.isdirectory('deps/flash.nvim') == 0 then MiniTest.skip('flash.nvim not in deps/') end
  h.open(LINES)
  local id = mark('alpha gamma')
  child.lua('vim.opt.rtp:append("deps/flash.nvim"); require("flash").setup({ label = { uppercase = false } })')
  child.lua('vim.keymap.set("n", "s", function() require("flash").jump() end)')
  h.cursor(1, 5)
  h.settle(600)
  child.type_keys('s', 'gam')
  local screen = table.concat(child.lua_get([[(function()
    local S = require('earmark.ui.hover').shown
    local out = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(S.buf, -1, 0, -1, { details = true })) do
      for _, t in ipairs(m[4].virt_text or {}) do out[#out + 1] = t[1] end
    end
    return out
  end)()]]), ' ')
  local label = screen:match('(%a)')
  eq(label ~= nil, true)
  child.type_keys(label)
  h.settle()
  eq(cur_name(), 'earmark://note/' .. id)
  eq(child.lua_get('vim.api.nvim_win_get_cursor(0)'), { 1, 6 })
end

T['flash inside the note jumps within it'] = function()
  if vim.fn.isdirectory('deps/flash.nvim') == 0 then MiniTest.skip('flash.nvim not in deps/') end
  h.open(LINES)
  local id = mark('alpha zebra beta')
  child.lua('vim.opt.rtp:append("deps/flash.nvim"); require("flash").setup({ label = { uppercase = false } })')
  child.lua('vim.keymap.set("n", "s", function() require("flash").jump() end)')
  h.cursor(1, 5)
  child.type_keys(' mm')
  h.settle()
  local nb = child.lua_get('vim.api.nvim_get_current_buf()')
  child.type_keys('s', 'zeb')
  local label = child.lua_get([[(function(b)
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(b, -1, 0, -1, { details = true })) do
      for _, t in ipairs(m[4].virt_text or {}) do if t[1]:match('%a') then return t[1] end end
    end
  end)(...)]], { nb })
  child.type_keys(label)
  h.settle()
  eq(cur_name(), 'earmark://note/' .. id)
  eq(child.lua_get('vim.api.nvim_win_get_cursor(0)'), { 1, 6 })
end

local function note_win()
  return child.lua_get([[(function()
    local E = require('earmark.ui.note').active
    local c = vim.api.nvim_win_get_config(E.win)
    return { width = c.width, height = c.height, row = c.row, col = c.col }
  end)()]])
end

T['the note float grows with the text, then wraps and grows taller'] = function()
  child.o.lines, child.o.columns = 40, 160
  h.open(LINES)
  mark()
  h.cursor(1, 5)
  child.type_keys(' mm')
  local w0 = note_win()
  eq(w0.width >= 60, true) -- roomy from the start
  child.type_keys(string.rep('word ', 20)) -- 100 columns
  local w1 = note_win()
  eq(w1.width > w0.width, true)
  eq(w1.width <= 120, true)
  child.type_keys(string.rep('more ', 160)) -- past the widest: wraps, so taller
  local w2 = note_win()
  eq(w2.width, 120)
  eq(w2.height > w0.height, true)
  eq(w2.row, w0.row) -- stayed on its side of the span
end

T['Alt+arrows move the float, and it keeps the offset while it grows'] = function()
  child.o.lines, child.o.columns = 40, 160
  h.open(LINES)
  mark()
  h.cursor(1, 5)
  child.type_keys(' mm')
  local w0 = note_win()
  child.type_keys('<M-Down>', '<M-Down>', '<M-Right>')
  local w1 = note_win()
  eq({ w1.row - w0.row, w1.col - w0.col }, { 2, 4 })
  eq(child.lua_get('vim.api.nvim_get_mode().mode'), 'i') -- still typing
  child.type_keys('text')
  eq(note_win().row, w1.row)
  child.type_keys('<Esc>', '<M-Up>')
  eq(note_win().row, w1.row - 1)
end

T['the footer names the split key as you type it'] = function()
  h.open(LINES)
  mark()
  h.cursor(1, 5)
  child.type_keys(' mm')
  local footer = child.lua_get([[(function()
    local f = vim.api.nvim_win_get_config(require('earmark.ui.note').active.win).footer
    return type(f) == 'table' and table.concat(vim.tbl_map(function(x) return x[1] end, f)) or f
  end)()]])
  eq(footer:find(',s split', 1, true) ~= nil, true)
end

return T
