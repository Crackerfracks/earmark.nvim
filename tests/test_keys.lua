local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child)

T['every action has a <Plug> mapping and every default key points at one'] = function()
  local missing = child.lua_get([[(function()
    local actions = require('earmark.actions')
    local keys = require('earmark.config').options.keys
    local out = {}
    for _, a in ipairs(actions.list) do
      for mode in pairs(a.modes or {}) do
        if vim.fn.maparg(actions.plug(a.name), mode, false, true).callback == nil then
          out[#out + 1] = mode .. ' ' .. actions.plug(a.name)
        end
        local lhs = keys[a.name]
        if lhs then
          local m = vim.fn.maparg(vim.keycode(lhs), mode, false, true)
          if m.rhs ~= actions.plug(a.name) then out[#out + 1] = mode .. ' ' .. lhs end
        end
      end
    end
    for name in pairs(keys) do
      if not actions.by_name[name] then out[#out + 1] = 'key for unknown action ' .. name end
    end
    return out
  end)()]])
  eq(missing, {})
end

T['every subcommand runs on an empty buffer without error'] = function()
  local errs = child.lua_get([[(function()
    local actions = require('earmark.actions')
    local out = {}
    vim.notify = function() end
    for _, name in ipairs(actions.commands()) do
      local ok, err = pcall(vim.cmd, 'Earmark ' .. name)
      if not ok then out[#out + 1] = name .. ': ' .. tostring(err) end
      -- close anything a command opened
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if #vim.api.nvim_list_wins() > 1 then pcall(vim.api.nvim_win_close, w, true) end
      end
    end
    return out
  end)()]])
  eq(errs, {})
end

T['no deprecated or banned APIs in the source'] = function()
  local banned = { 'nvim_buf_add_highlight', 'nvim_buf_set_option', 'nvim_buf_get_option', 'nvim_win_set_option',
    'vim%.tbl_islist', 'vim%.tbl_flatten', 'vim%.highlight%.', 'vim%.diff%(', 'sign_text', 'sign_define' }
  local hits = {}
  for _, f in ipairs(vim.fn.glob('lua/**/*.lua', false, true)) do
    local n = 0
    for line in io.lines(f) do
      n = n + 1
      if not line:match('^%s*%-%-') then
        for _, b in ipairs(banned) do
          if line:find(b) then hits[#hits + 1] = ('%s:%d %s'):format(f, n, b) end
        end
      end
    end
  end
  eq(hits, {})
end

T['find at end of line hits a span ending there'] = function()
  h.open({ 'one two', '' })
  h.cursor(1, 4)
  child.type_keys('3gh$')
  local n = child.lua_get('#require("earmark").at(0, { 0, 7 })')
  eq(n, 1)
  eq(child.lua_get('#require("earmark").at(0, { 0, 6 })'), 1)
end

T['events: specific and generic patterns fire'] = function()
  child.lua([[
    _G.ev = {}
    vim.api.nvim_create_autocmd('User', { pattern = { 'EarmarkAdd', 'EarmarkChanged', 'EarmarkNote' }, callback = function(e)
      _G.ev[#_G.ev + 1] = e.match .. ':' .. e.data.action
    end })
  ]])
  h.open()
  h.cursor(1, 10)
  child.type_keys('2ghiw')
  child.lua([[require('earmark.buffer').set_note(0, require('earmark').list(0)[1].annotation.id, 'n')]])
  eq(child.lua_get('_G.ev'), { 'EarmarkChanged:add', 'EarmarkAdd:add', 'EarmarkChanged:note', 'EarmarkNote:note' })
end

T['a failing event handler does not stop the action'] = function()
  child.lua([[
    vim.api.nvim_create_autocmd('User', { pattern = 'EarmarkAdd', callback = function() error('boom') end })
  ]])
  h.open()
  child.lua([[pcall(require('earmark').annotate, 0, { 0, 4 }, { 0, 9 }, { set = 'vivid', label = '1' })]])
  eq(h.texts(), { { text = 'quick', label = '1', status = 'ok' } })
end

return T
