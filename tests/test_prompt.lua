local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child, "{ prompt = { ask_name = 'never' } }")

local function prompt_lines()
  -- the input line plus the virtual candidate rows, as text
  return child.lua_get([[(function()
    local P = require('earmark.ui.prompt').active
    if not P then return nil end
    local out = { table.concat(vim.api.nvim_buf_get_lines(P.buf, 0, -1, false), '') }
    local m = vim.api.nvim_buf_get_extmarks(P.buf, require('earmark.ui.prompt').ns, 0, -1, { details = true })[1]
    for _, vl in ipairs(m and m[4].virt_lines or {}) do
      local t = {}
      for _, c in ipairs(vl) do t[#t + 1] = c[1] end
      out[#out + 1] = table.concat(t)
    end
    return out
  end)()]])
end

local function preview_group()
  return child.lua_get([[(function()
    local P = require('earmark.ui.prompt').active
    local buf = P and P.src_buf or 0
    local m = vim.api.nvim_buf_get_extmarks(buf, require('earmark.ui.prompt').preview_ns, 0, -1, { details = true })[1]
    return m and m[4].hl_group or vim.NIL
  end)()]])
end

T['opens one unlisted float below the span'] = function()
  h.open()
  h.cursor(1, 10)
  child.type_keys('ghiw')
  local fl = h.floats()
  eq(#fl, 1)
  eq(child.lua_get(('vim.bo[%d].buflisted'):format(fl[1].buf)), false)
  eq(fl[1].config.row, 1) -- right under line 1
  eq(fl[1].config.col, 10) -- under the start of the span
  eq(child.api.nvim_get_mode().mode, 'i')
end

T['typing a key previews and applies it'] = function()
  h.open()
  h.cursor(1, 10)
  child.type_keys('ghiw')
  child.type_keys('2', '3')
  eq(preview_group(), child.lua_get([[require('earmark.sets').group({ set = 'vivid', label = '23' })]]))
  child.type_keys('<BS>')
  eq(prompt_lines()[1], '2')
  eq(#h.floats(), 1) -- <BS> edits, it does not cancel
  eq(preview_group(), child.lua_get([[require('earmark.sets').group({ set = 'vivid', label = '2' })]]))
  child.type_keys('<CR>')
  eq(h.texts(), { { text = 'brown', label = '2', status = 'ok' } })
  eq(#h.floats(), 0)
  eq(preview_group(), vim.NIL)
end

T['digits list the other shades of the family'] = function()
  h.open()
  h.cursor(1, 10)
  child.type_keys('ghiw', '3')
  local lines = prompt_lines()
  local keys = {}
  for i = 2, #lines do
    keys[#keys + 1] = lines[i]:match('■ (%d+)')
  end
  eq(keys, { '3', '13', '23', '33', '43', '53', '63', '73' })
end

T['<Esc><Esc> cancels and removes the preview'] = function()
  h.open()
  h.cursor(1, 10)
  child.type_keys('ghiw', '5')
  child.type_keys('<Esc>')
  eq(#h.floats(), 1) -- first <Esc> only leaves Insert mode
  child.type_keys('<Esc>')
  eq(#h.floats(), 0)
  eq(h.texts(), {})
  eq(preview_group(), vim.NIL)
end

T['Normal-mode editing works in the input'] = function()
  h.open()
  h.cursor(1, 10)
  child.type_keys('ghiw', '1', '2', '<Esc>', 'x', 'x', 'i', '4', '<CR>')
  eq(h.texts()[1].label, '4')
end

T['dot-repeat after a prompted line add'] = function()
  h.open()
  h.cursor(1, 3)
  child.type_keys('ghh', '2', '<CR>')
  h.settle()
  h.cursor(3, 0)
  child.type_keys('.')
  eq(h.texts(), {
    { text = H.LINES[1], label = '2', status = 'ok' },
    { text = H.LINES[3], label = '2', status = 'ok' },
  })
end

T['dot-repeat after a prompted visual add covers the same size'] = function()
  h.open()
  h.cursor(1, 4)
  child.type_keys('v', 'e', 'gh', '5', '<CR>')
  h.settle()
  h.cursor(2, 2)
  child.type_keys('.')
  eq(h.texts(), { { text = 'quick', label = '5', status = 'ok' }, { text = 'secon', label = '5', status = 'ok' } })
end

T['dot-repeat after a prompted add repeats silently'] = function()
  h.open()
  h.cursor(1, 10)
  child.type_keys('ghiw', '6', '<CR>')
  h.settle()
  h.cursor(2, 2)
  child.type_keys('.')
  eq(#h.floats(), 0)
  eq(h.texts(), { { text = 'brown', label = '6', status = 'ok' }, { text = 'second', label = '6', status = 'ok' } })
end

T['an operator cancelled before its motion leaves nothing behind'] = function()
  h.open()
  h.cursor(1, 10)
  child.type_keys('gh', '<Esc>')
  h.settle()
  child.type_keys('w', 'w')
  eq(#h.floats(), 0)
  child.type_keys('4ghiw')
  eq(#h.texts(), 1)
end

T['a count never opens the prompt'] = function()
  h.open()
  h.cursor(1, 10)
  child.type_keys('3ghiw')
  eq(#h.floats(), 0)
  eq(h.texts()[1].label, '3')
end

T['names: <Tab> names a label, saved per file and in histories'] = function()
  h.open()
  h.cursor(1, 10)
  child.type_keys('ghiw', '3', '<Tab>')
  eq(prompt_lines()[1], '')
  child.type_keys('Factually Inaccurate', '<CR>')
  eq(h.texts()[1].label, '3')
  eq(child.lua_get([[require('earmark.buffer').display_name(0, { set = 'vivid', label = '3' })]]), 'Factually Inaccurate')
  eq(
    child.lua_get([[require('earmark.store').mru_get(_G.root .. '/.earmark/names.json', 'vivid/3')]]),
    { 'Factually Inaccurate' }
  )
  -- another file in the same project: the name is pre-filled from the project history
  h.open({ 'other text here' }, 'notes/other.md')
  h.cursor(1, 0)
  child.type_keys('ghiw', '3', '<Tab>')
  eq(prompt_lines()[1], 'Factually Inaccurate')
  child.type_keys('<Esc>', '<Esc>')
end

T['names: typed text matches label names'] = function()
  h.open()
  child.lua([[require('earmark.names').save(0, { set = 'vivid', label = '7' }, 'Factually Inaccurate')]])
  h.cursor(1, 10)
  child.type_keys('ghiw', 'fac')
  local lines = prompt_lines()
  eq(lines[2]:find('Factually Inaccurate', 1, true) ~= nil, true)
  child.type_keys('<CR>')
  eq(h.texts()[1].label, '7')
end

T['rename: empty input clears the name for this file'] = function()
  h.open()
  h.cursor(1, 10)
  child.type_keys('3ghiw')
  child.lua([[require('earmark.names').save(0, { set = 'vivid', label = '3' }, 'Vague')]])
  child.type_keys(' mr')
  eq(prompt_lines()[1], 'Vague')
  child.type_keys('<C-u>', '<CR>')
  eq(child.lua_get([[require('earmark.buffer').display_name(0, { set = 'vivid', label = '3' })]]), '3')
end

T['relabel and add a value'] = function()
  h.open()
  h.cursor(1, 10)
  child.type_keys('3ghiw')
  child.type_keys(' ml', '<C-u>', '9', '<CR>')
  eq(h.texts()[1].label, '9')
  child.type_keys(' ma', '<C-u>', '4', '<CR>')
  local values = child.lua_get('require("earmark").list(0)[1].annotation.values')
  eq(values, { { set = 'vivid', label = '9' }, { set = 'vivid', label = '4' } })
end

T['first use of a numbered label asks for a name once'] = function()
  child.lua([[require('earmark.config').options.prompt.ask_name = 'first_use']])
  h.open()
  h.cursor(1, 10)
  child.type_keys('ghiw', '3', '<CR>')
  eq(#h.floats(), 1) -- went on to the name stage
  child.type_keys('<CR>')
  eq(#h.floats(), 0)
  h.cursor(2, 2)
  child.type_keys('ghiw', '3', '<CR>')
  eq(#h.floats(), 0) -- asked already
  eq(#h.texts(), 2)
end

T['visual selection then gh opens the prompt for the selection'] = function()
  h.open()
  h.cursor(1, 4)
  child.type_keys('v', 'e', 'w', 'e', 'gh')
  child.type_keys('8', '<CR>')
  eq(h.texts(), { { text = 'quick brown', label = '8', status = 'ok' } })
end

T['no matching label: <CR> does nothing'] = function()
  h.open()
  h.cursor(1, 10)
  child.type_keys('ghiw', '343')
  local lines = prompt_lines()
  eq(lines[2]:find('no label', 1, true) ~= nil, true)
  child.type_keys('<CR>')
  eq(#h.floats(), 1)
  eq(h.texts(), {})
end

return T
