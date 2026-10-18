-- A label on text that already has an annotation of exactly that span asks first:
-- a adds it as another label, r replaces the label, Esc cancels; `.` repeats the answer.
local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child, "{ prompt = { ask_name = 'never' } }")

local function labels(i)
  return child.lua_get(('vim.tbl_map(function(v) return v.label end, require("earmark").list(0)[%d].annotation.values)'):format(i or 1))
end

local function shown()
  local fl = h.floats()
  if #fl == 0 then return nil end
  return table.concat(vim.tbl_map(function(l) return table.concat(l) end, child.get_screenshot().text), '\n')
end

T['a adds the label as another one'] = function()
  h.open()
  h.cursor(1, 10)
  child.type_keys('2ghiw')
  child.type_keys('5ghiw')
  h.settle(30)
  local s = shown()
  eq(s ~= nil and s:find('Already labelled', 1, true) ~= nil, true)
  eq(s:find('r replace', 1, true) ~= nil, true)
  child.type_keys('a')
  h.settle(30)
  eq(labels(), { '2', '5' })
  eq(#h.floats(), 0)
end

T['r replaces the label; . repeats that without asking'] = function()
  h.open()
  h.cursor(1, 10)
  child.type_keys('2ghiw')
  h.cursor(1, 16)
  child.type_keys('2ghiw')
  h.cursor(1, 10)
  child.type_keys('5ghiw')
  h.settle(30)
  child.type_keys('r')
  h.settle(30)
  eq(labels(1), { '5' })
  h.cursor(1, 16)
  child.type_keys('.')
  h.settle(30)
  eq(#h.floats(), 0)
  local all = child.lua_get('vim.tbl_map(function(x) return x.annotation.values[1].label .. #x.annotation.values end, require("earmark").list(0))')
  eq(all, { '51', '51' })
end

T['Esc cancels and changes nothing'] = function()
  h.open()
  h.cursor(1, 10)
  child.type_keys('2ghiw')
  child.type_keys('5ghiw')
  h.settle(30)
  child.type_keys('<Esc>')
  h.settle(30)
  eq(labels(), { '2' })
  eq(#h.floats(), 0)
end

T['the label prompt path asks too'] = function()
  h.open()
  h.cursor(1, 10)
  child.type_keys('2ghiw')
  child.type_keys('ghiw')
  h.settle(50)
  child.type_keys('7', '<CR>')
  h.settle(50)
  local s = shown()
  eq(s ~= nil and s:find('Already labelled', 1, true) ~= nil, true)
  child.type_keys('a')
  h.settle(30)
  eq(labels(), { '2', '7' })
end

T['no question for new text, or with confirm_stack = false'] = function()
  h.open()
  h.cursor(1, 10)
  child.type_keys('2ghiw')
  h.settle(30)
  eq(#h.floats(), 0)
  child.lua('require("earmark.config").options.prompt.confirm_stack = false')
  child.type_keys('5ghiw')
  h.settle(30)
  eq(#h.floats(), 0)
  eq(labels(), { '2', '5' })
end

return T
