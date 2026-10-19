local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child, [[{ keys = { next = '<leader>mf', clear = false } }]])

local function sheet()
  for _, f in ipairs(h.floats()) do
    if f.config.title and vim.inspect(f.config.title):find('earmark keys', 1, true) then return f end
  end
end

local function text(f)
  return table.concat(f.lines, '\n')
end

--- Put the cursor on the line of the key list holding `needle`, at its column.
local function goto_text(needle)
  child.lua([[
    local needle = ...
    for i, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
      local c = l:find(needle, 1, true)
      if c then vim.api.nvim_win_set_cursor(0, { i, c - 1 }) return end
    end
    error('not in the key list: ' .. needle)
  ]], { needle })
end

T['every key of every action is in the list, once'] = function()
  local missing = child.lua_get([[(function()
    local listed = {}
    for _, s in ipairs(require('earmark.ui.keys').sections) do
      for _, r in ipairs(s.rows) do
        for _, n in ipairs(type(r.a) == 'table' and r.a or { r.a }) do listed[n] = true end
      end
    end
    local out = {}
    for _, a in ipairs(require('earmark.actions').list) do
      if a.modes and not listed[a.name] then out[#out + 1] = a.name end
    end
    for n in pairs(listed) do
      if not require('earmark.actions').by_name[n] then out[#out + 1] = 'unknown: ' .. n end
    end
    return out
  end)()]])
  eq(missing, {})
end

T['<leader>m? opens it, with your keys and the leader shown as ␣'] = function()
  h.open()
  child.type_keys(' m?')
  local f = sheet()
  eq(f ~= nil, true)
  local t = text(f)
  eq(t:find('␣mf ␣mN  next / previous annotation', 1, true) ~= nil, true)
  eq(t:find('{count}gh{motion}', 1, true) ~= nil, true)
  -- a key you turned off shows how to reach the action instead
  eq(t:find(':Earmark clear', 1, true) ~= nil, true)
  -- the command-only actions are listed too
  eq(t:find(':Earmark reload', 1, true) ~= nil, true)
  eq(child.api.nvim_get_current_win(), f.win)
  child.type_keys('q')
  eq(sheet(), nil)
end

T[':Earmark help opens it too'] = function()
  h.open()
  child.cmd('Earmark help')
  eq(sheet() ~= nil, true)
end

T['<CR> on a row runs it in the file'] = function()
  h.open()
  h.cursor(2, 2)
  child.type_keys('3ghiw')
  h.cursor(1, 0)
  child.lua('require("earmark.ui.keys").open()')
  goto_text('next / previous annotation')
  child.type_keys('<CR>')
  h.settle()
  eq(sheet(), nil)
  eq(child.api.nvim_win_get_cursor(0), { 2, 2 })
end

T['<CR> in the right-hand column runs that column\'s row'] = function()
  h.open()
  child.o.columns = 200
  h.cursor(1, 4)
  child.type_keys('3ghiw')
  child.lua('require("earmark.ui.keys").open()')
  local f = sheet()
  -- the label sets are in a column to the right
  goto_text('␣ms')
  local before = child.lua_get('require("earmark.sets").current')
  child.type_keys('<CR>')
  h.settle()
  eq(child.lua_get('require("earmark.sets").current') ~= before, true)
  eq(#h.texts(), 1)
  eq(f ~= nil, true)
end

T['<CR> on a heading or a fixed key does nothing'] = function()
  h.open()
  child.lua('require("earmark.ui.keys").open()')
  goto_text('Annotate')
  child.type_keys('<CR>')
  eq(sheet() ~= nil, true)
  goto_text('repeat with the same label')
  child.type_keys('<CR>')
  eq(sheet() ~= nil, true)
end

T['columns follow the width of the editor'] = function()
  local n = child.lua_get([[(function()
    local K = require('earmark.ui.keys')
    return { #K.layout(200).lines, #K.layout(130).lines, #K.layout(60).lines, K.layout(130).width }
  end)()]])
  eq(n[1] < n[2], true)
  eq(n[2] < n[3], true)
  eq(n[4] <= 130, true)
end

T['a small editor still gets a list that scrolls'] = function()
  child.o.lines, child.o.columns = 12, 50
  h.open()
  child.lua('require("earmark.ui.keys").open()')
  local f = sheet()
  eq(f.config.height <= 12, true)
  eq(f.config.width <= 50, true)
  child.type_keys('G')
  eq(child.fn.line('.') > f.config.height, true)
end

T['leaving the window closes it'] = function()
  h.open()
  child.lua('require("earmark.ui.keys").open()')
  child.cmd('wincmd p')
  h.settle()
  eq(sheet(), nil)
end

T['which-key gets plain descriptions and a group icon per key'] = function()
  local by = child.lua_get([=[(function()
    local out = {}
    for _, s in ipairs(require('earmark.ui.keys').which_key_spec()) do
      out[s[1]] = { desc = s.desc, mode = s.mode, icon = s.icon }
    end
    return out
  end)()]=])
  eq(by['<leader>mf'].desc, 'next annotation')
  eq(by['<leader>mN'].icon.color, 'blue')
  eq(by['<leader>mx'].mode, { 'n', 'x' })
  eq(by['<leader>mX'], nil) -- turned off
  eq(by['gh'].mode, { 'n', 'x' })
end

T['with which-key installed, the descriptions reach it'] = function()
  if vim.fn.isdirectory('deps/which-key.nvim') == 0 then MiniTest.skip('which-key.nvim not in deps/') end
  child.restart({ '-u', 'scripts/minimal_init.lua' })
  child.lua([[
    vim.opt.rtp:append('deps/which-key.nvim')
    vim.g.mapleader = ' '
    require('which-key').setup({})
    require('earmark').setup({ storage_dir = vim.fn.tempname() })
  ]])
  h.settle(50)
  local got = child.lua_get([[(function()
    local out = {}
    for _, m in ipairs(require('which-key.config').mappings) do
      if m.desc == 'next annotation' or m.desc == 'earmark' then out[#out + 1] = m.desc end
    end
    table.sort(out)
    return out
  end)()]])
  eq(got, { 'earmark', 'next annotation' })
end

return T
