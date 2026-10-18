local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child)

local function mark(s, e, label)
  return child.lua_get('require("earmark").annotate(0, ...).id', { s, e, { set = 'vivid', label = label or '3' } })
end

local function cur()
  return child.api.nvim_win_get_cursor(0)
end

local function messages()
  child.lua('_G.msgs = {}; vim.notify = function(m) table.insert(_G.msgs, m) end')
end

local function last_msg()
  return child.lua_get('_G.msgs[#_G.msgs] or vim.NIL')
end

local function setup3()
  h.open()
  mark({ 0, 4 }, { 0, 9 }, '1')
  mark({ 1, 2 }, { 1, 8 }, '2')
  mark({ 2, 0 }, { 2, 5 }, '1')
  messages()
end

T['next/prev move between annotations and wrap with a message'] = function()
  setup3()
  h.cursor(1, 0)
  child.type_keys(' mn')
  eq(cur(), { 1, 4 })
  child.type_keys(' mn')
  eq(cur(), { 2, 2 })
  child.type_keys(' mn', ' mn')
  eq(cur(), { 1, 4 })
  eq(last_msg(), 'earmark: wrapped to top')
  child.type_keys(' mN')
  eq(cur(), { 3, 0 })
  eq(last_msg(), 'earmark: wrapped to bottom')
end

T['a count moves several annotations'] = function()
  setup3()
  h.cursor(1, 0)
  child.type_keys('2 mn')
  eq(cur(), { 2, 2 })
end

T['from inside an annotation, next goes to the next one'] = function()
  setup3()
  h.cursor(1, 6)
  child.type_keys(' mn')
  eq(cur(), { 2, 2 })
  child.type_keys(' mN')
  eq(cur(), { 1, 4 })
end

T['next/prev with the same label skip other labels'] = function()
  setup3()
  h.cursor(1, 5)
  child.type_keys(' m]')
  eq(cur(), { 3, 0 })
  child.type_keys(' m]')
  eq(cur(), { 1, 4 })
  eq(last_msg(), 'earmark: wrapped to top')
  child.type_keys(' m[')
  eq(cur(), { 3, 0 })
end

T['same label with nothing under the cursor says so'] = function()
  setup3()
  h.cursor(1, 0)
  child.type_keys(' m]')
  eq(last_msg(), 'earmark: nothing under the cursor')
end

T['no annotations'] = function()
  h.open()
  messages()
  child.type_keys(' mn')
  eq(last_msg(), 'earmark: no annotations')
end

T['jump without flash falls back to the picker'] = function()
  setup3()
  child.lua([[vim.ui.select = function(items, opts, cb) _G.offered = #items; cb(items[2]) end]])
  h.cursor(1, 0)
  child.type_keys(' mj')
  eq(child.lua_get('_G.offered'), 3)
  eq(cur(), { 2, 2 })
end

T['jump with flash labels each visible annotation'] = function()
  if vim.fn.isdirectory('deps/flash.nvim') == 0 then MiniTest.skip('flash.nvim not in deps/') end
  setup3()
  child.lua('vim.opt.rtp:append("deps/flash.nvim"); require("flash").setup({ label = { uppercase = false } })')
  h.cursor(1, 0)
  child.type_keys(' mj')
  h.settle(50)
  -- labels are drawn before each annotation; read the one before the third
  local label = child.lua_get([[(function()
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, -1, {2, 0}, {2, -1}, { details = true })) do
      local vt = m[4].virt_text
      if vt and vt[1] and vt[1][1]:match('^%a$') then return vt[1][1] end
    end
    return vim.NIL
  end)()]])
  eq(type(label), 'string')
  child.type_keys(label)
  eq(cur(), { 3, 0 })
end

return T
