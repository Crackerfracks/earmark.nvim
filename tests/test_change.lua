-- Changing annotated text with c, s and C keeps the new text in the annotation.
local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child)

local function setup()
  h.open({ 'roads were in worse shape than anyone admitted' })
  child.lua('require("earmark").annotate(0, { 0, 14 }, { 0, 25 }, { set = "vivid", label = "3" })')
end

local function one()
  h.settle(100)
  local t = h.texts()
  eq(#t, 1)
  return t[1]
end

T['cw on the last word keeps the new word in the annotation'] = function()
  setup()
  h.cursor(1, 20)
  child.type_keys('cw', 'state', '<Esc>')
  eq(one(), { text = 'worse state', label = '3', status = 'ok' })
end

T['cw on the first word keeps the new word in the annotation'] = function()
  setup()
  h.cursor(1, 14)
  child.type_keys('cw', 'awful', '<Esc>')
  eq(one().text, 'awful shape')
end

T['changing all of it keeps the annotation on the new text, marked stale'] = function()
  setup()
  h.cursor(1, 14)
  child.type_keys('c2e', 'bad mess', '<Esc>')
  eq(one(), { text = 'bad mess', label = '3', status = 'stale' })
end

T['dot repeats the change and the annotation follows again'] = function()
  h.open({ 'one worse shape', 'two worse shape' })
  child.lua('require("earmark").annotate(0, { 0, 4 }, { 0, 15 }, { set = "vivid", label = "3" })')
  child.lua('require("earmark").annotate(0, { 1, 4 }, { 1, 15 }, { set = "vivid", label = "3" })')
  h.cursor(1, 10)
  child.type_keys('cw', 'state', '<Esc>')
  h.cursor(2, 10)
  child.type_keys('.')
  h.settle(100)
  eq(vim.tbl_map(function(t) return t.text end, h.texts()), { 'worse state', 'worse state' })
end

T['typing right after an annotation still stays outside it'] = function()
  h.open({ 'one two' })
  child.lua('require("earmark").annotate(0, { 0, 4 }, { 0, 7 }, { set = "vivid", label = "3" })')
  child.type_keys('A', ' three', '<Esc>')
  eq(one().text, 'two')
end

T['deleting then inserting somewhere else does not grow it'] = function()
  setup()
  h.cursor(1, 20)
  child.type_keys('dw')
  h.cursor(1, 0)
  child.type_keys('i', 'new ', '<Esc>')
  eq(one().text, 'worse ')
end

T['changing a whole word then typing nothing detaches it as before'] = function()
  h.open({ 'one two three' })
  child.lua('require("earmark").annotate(0, { 0, 4 }, { 0, 7 }, { set = "vivid", label = "3" })')
  h.cursor(1, 4)
  child.type_keys('ciw', '<Esc>')
  h.settle(100)
  eq(h.texts()[1].status, 'detached')
end

return T
