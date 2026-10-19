-- Every float and prompt in windows too small for it: a tiny editor, a one-line split and a
-- three-column vertical split. Each opens sanely (or declines) without an error.
local H = dofile('tests/helpers.lua')
local E = dofile('tests/edge_helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child, "{ prompt = { ask_name = 'never' } }")

local layouts = {
  ['tiny editor'] = 'vim.o.lines, vim.o.columns = 5, 20',
  ['one-line split'] = 'vim.cmd("1split")',
  ['three-column vsplit'] = 'vim.cmd("3vsplit")',
  ['one-line three-column split'] = 'vim.cmd("1split | 3vsplit")',
  ['tiny editor without borders'] = 'require("earmark.config").options.ui.border = "none"; vim.o.lines, vim.o.columns = 5, 20',
  ['two-line editor'] = 'vim.o.cmdheight = 0; vim.o.laststatus = 0; vim.o.lines, vim.o.columns = 2, 12',
}

-- an annotation with a note on "The" (start of line 1), the cursor on it
local function setup(layout)
  h.open()
  child.lua([[
    local a = require('earmark').annotate(0, { 0, 0 }, { 0, 3 }, { set = 'vivid', label = '3' })
    require('earmark').set_note(0, a.id, 'a note\nwith two lines')
    _G.id = a.id
  ]])
  child.lua(layouts[layout])
  h.cursor(1, 0)
  E.watch(child)
end

local function float_count()
  return #h.floats()
end

local cases = {
  prompt = function()
    child.type_keys('ghiw')
    h.settle()
    if child.lua_get('require("earmark.ui.prompt").active ~= nil') then
      child.type_keys('5', '<CR>')
      h.settle()
      eq(child.lua_get('require("earmark.ui.prompt").active'), vim.NIL)
    end
  end,
  ['prompt, then cancel'] = function()
    child.type_keys('ghiw')
    h.settle()
    child.type_keys('<Esc>', '<Esc>')
    h.settle()
    eq(float_count(), 0)
  end,
  hover = function()
    child.type_keys('l')
    h.settle(250)
    child.type_keys('h')
    h.settle(250)
    child.type_keys('$')
    h.settle(100)
  end,
  peek = function()
    child.type_keys(' mi')
    h.settle()
    child.type_keys('q')
    h.settle()
    eq(float_count(), 0)
  end,
  ['note editor'] = function()
    child.type_keys(' mm')
    h.settle()
    child.type_keys('G', 'A', ' more', '<Esc>', 'q')
    h.settle()
    eq(child.lua_get('require("earmark").get(0, _G.id).note'), 'a note\nwith two lines more')
  end,
  palette = function()
    child.type_keys(' mc')
    h.settle()
    child.type_keys('j', 'k', '<Tab>', 'q')
    h.settle()
    eq(float_count(), 0)
  end,
  ['key list'] = function()
    child.type_keys(' m?')
    h.settle()
    child.type_keys('G', 'q')
    h.settle()
    eq(float_count(), 0)
  end,
  ['review list and diff'] = function()
    child.lua([[
      vim.ui.select = function(items, opts, cb) _G.offered = #items; cb(items[1]) end
      vim.cmd('normal! ggdw')
      require('earmark.buffer').on_change(0)
    ]])
    child.type_keys(' md')
    h.settle()
    child.lua('pcall(vim.cmd, "close")')
  end,
  diff = function()
    child.type_keys(' mD')
    h.settle()
    child.type_keys('q')
    h.settle()
  end,
  ['set popup'] = function()
    child.type_keys(' ms')
    h.settle()
    child.type_keys(' ms')
    h.settle()
  end,
  ['count hint'] = function()
    child.type_keys('3gh', 'iw')
    h.settle()
    eq(#h.texts() >= 1, true)
    eq(float_count(), 0)
  end,
}

T['tiny editor: set popup, count hint and stack question with long names'] = function()
  h.open()
  child.lua([[
    local name = 'a-label-set-with-a-very-long-name-indeed'
    require('earmark.sets').load(vim.tbl_extend('force', require('earmark.config').options, {
      sets = { 'vivid', [name] = { labels = {
        { key = '1', name = 'A rather long label name that will not fit', color = '#e06c75' },
        { key = '2', name = 'Another', color = '#98c379' },
      } } },
    }))
    require('earmark').use_set(name)
    require('earmark.buffer').rename_label(0, { set = name, label = '1' }, 'An even longer name for this label in this file')
    vim.o.lines, vim.o.columns = 5, 20
  ]])
  h.cursor(1, 4)
  E.watch(child)
  child.type_keys(' ms')
  h.settle()
  child.lua('require("earmark.ui.set_popup").show("a-label-set-with-a-very-long-name-indeed")')
  h.settle()
  child.type_keys('1ghiw')
  h.settle()
  eq(#h.texts(), 1)
  child.type_keys('1ghiw', '2ghiw') -- the second asks: already labelled
  h.settle()
  child.type_keys('a')
  h.settle()
  E.no_errors(child)
end

T['tiny editor: the note editor as a split, and ,s / ,f'] = function()
  setup('tiny editor')
  child.lua('require("earmark.config").options.note.layout = "split"')
  child.type_keys(' mm')
  h.settle()
  if child.lua_get('require("earmark.ui.note").active ~= nil') then
    child.type_keys('G', 'A', ' more', '<Esc>', ',f', ',s', 'q')
  end
  h.settle()
  child.lua('require("earmark.config").options.note.layout = "float"')
  child.type_keys(' mm', 'G', 'A', '!', '<Esc>', ',s')
  h.settle()
  if child.lua_get('require("earmark.ui.note").active ~= nil') then child.type_keys('q') end
  h.settle()
  E.no_errors(child)
  local note = child.lua_get('require("earmark").get(0, _G.id).note')
  eq(note:sub(-1), '!') -- the text typed is never lost
end

for lname in pairs(layouts) do
  for cname, fn in pairs(cases) do
    T[lname .. ': ' .. cname] = function()
      setup(lname)
      fn()
      E.no_errors(child)
    end
  end
end

return T
