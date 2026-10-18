local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

-- a same-named spec set the project file must override
local T = H.new_set(child, [[{ prompt = { ask_name = 'never' }, sets_dir = false,
  sets = { 'vivid', wf = { labels = { { key = 'x', name = 'from setup' } } } } }]])

local WF = {
  labels = {
    { key = 'q1', name = 'Accuracy', color = '#e06c75',
      choices = { { key = 'a', name = 'Correct' }, { key = 'b', name = 'Minor issue', color = '#e5c07b' }, { key = 'c', name = 'Major issue' } },
      text = { when = { 'b', 'c' }, prompt = 'What is wrong?' } },
    { key = 'q1.1', name = 'Severity reason', requires = { q1 = { 'b', 'c' } } },
    { key = 'q2', name = 'Tone' },
  },
}

local function write_set(name, tbl)
  child.lua(([[
    local dir = _G.root .. '/.earmark/sets'
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile({ vim.json.encode(...) }, dir .. '/%s.json')
  ]]):format(name), { tbl })
end

local function values(id)
  return child.lua_get('require("earmark.buffer").annotation(0, ...).values', { id })
end

local function prompt_rows()
  return child.lua_get([[(function()
    local P = require('earmark.ui.prompt').active
    if not P then return vim.NIL end
    local m = vim.api.nvim_buf_get_extmarks(P.buf, require('earmark.ui.prompt').ns, 0, -1, { details = true })[1]
    local out = {}
    for _, vl in ipairs(m and m[4].virt_lines or {}) do
      local t = {}
      for _, c in ipairs(vl) do t[#t + 1] = c[1] end
      out[#out + 1] = vim.trim(table.concat(t))
    end
    return out
  end)()]])
end

local function use_wf()
  write_set('wf', WF)
  h.open()
  child.lua('require("earmark").use_set("wf")')
end

T['a project set file replaces a same-named set from setup'] = function()
  write_set('wf', WF)
  h.open()
  eq(child.lua_get('require("earmark.sets").by_name.wf.labels[1].name'), 'Accuracy')
  eq(child.lua_get('require("earmark.sets").root'), child.lua_get('vim.uv.fs_realpath(_G.root)'))
end

T['editing the set file reloads it'] = function()
  write_set('wf', WF)
  h.open()
  local changed = vim.deepcopy(WF)
  changed.labels[3].name = 'Tone of voice'
  write_set('wf', changed)
  child.lua('vim.wait(20)')
  child.cmd('doautocmd FocusGained')
  eq(child.lua_get('require("earmark.sets").by_name.wf.by_key.q2.name'), 'Tone of voice')
end

T['project Lua set files run only when trusted'] = function()
  child.lua([[
    local dir = _G.root .. '/.earmark/sets'
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile({ 'return { labels = { "lua label" } }' }, dir .. '/luaset.lua')
    vim.secure.read = function() return nil end
  ]])
  h.open()
  eq(child.lua_get('require("earmark.sets").by_name.luaset == nil'), true)
  child.lua('vim.secure.read = function(p) return table.concat(vim.fn.readfile(p), "\\n") end')
  child.cmd('Earmark reload')
  eq(child.lua_get('require("earmark.sets").by_name.luaset.labels[1].name'), 'lua label')
end

T['a label with choices asks for one; the choice is stored and named'] = function()
  use_wf()
  h.cursor(1, 4)
  child.type_keys('ghiw', 'q1', '<CR>')
  eq(prompt_rows(), { '▸ ██ a  Correct', '██ b  Minor issue', '██ c  Major issue' })
  child.type_keys('a', '<CR>') -- "a": no text asked for
  h.settle()
  local id = child.lua_get('require("earmark").list(0)[1].annotation.id')
  eq(values(id), { { set = 'wf', label = 'q1', choice = 'a' } })
  eq(child.lua_get('require("earmark.buffer").display_name(0, ...)', { values(id)[1] }), 'Accuracy · a Correct')
end

T['text is asked only for the choices that want it'] = function()
  use_wf()
  h.cursor(1, 4)
  child.type_keys('ghiw', 'q1', '<CR>', 'b', '<CR>')
  eq(prompt_rows(), { 'What is wrong?' })
  child.type_keys('wrong animal', '<CR>')
  h.settle()
  local id = child.lua_get('require("earmark").list(0)[1].annotation.id')
  eq(values(id), { { set = 'wf', label = 'q1', choice = 'b', text = 'wrong animal' } })
  -- the choice's own colour
  eq(child.lua_get('require("earmark.sets").color(...)', { values(id)[1] }), '#e5c07b')
end

T['requires keeps a label unavailable until the other value is there'] = function()
  use_wf()
  h.cursor(1, 4)
  child.type_keys('ghiw', 'q1.1')
  local rows = prompt_rows()
  eq(rows[1]:find('needs q1 = b/c', 1, true) ~= nil, true)
  child.type_keys('<CR>') -- disabled: nothing happens
  eq(prompt_rows() ~= vim.NIL, true)
  child.type_keys('<Esc>', '<Esc>')
  h.settle()
  -- annotate with q1 = b, then add q1.1 to it
  child.lua('require("earmark").annotate(0, {0,4}, {0,9}, { set = "wf", label = "q1", choice = "b" })')
  h.cursor(1, 5)
  child.type_keys(' ma', 'q1.1')
  eq(prompt_rows()[1]:find('needs', 1, true), nil)
  child.type_keys('<CR>')
  h.settle()
  local id = child.lua_get('require("earmark").list(0)[1].annotation.id')
  eq(#values(id), 2)
end

T['<S-Tab> goes back from the choice to the label'] = function()
  use_wf()
  h.cursor(1, 4)
  child.type_keys('ghiw', 'q1', '<CR>', '<S-Tab>')
  eq(child.lua_get('require("earmark.ui.prompt").active.stage'), 'label')
  eq(child.lua_get('vim.api.nvim_get_current_line()'), 'q1')
end

T['switching sets shows a short-lived popup'] = function()
  h.open()
  child.type_keys(' ms')
  local fl = h.floats()
  eq(#fl, 1)
  eq(fl[1].lines[1]:find('^ wf  ■ from setup') ~= nil, true)
  child.lua('vim.wait(1700, function() return #vim.tbl_filter(function(w) return vim.api.nvim_win_get_config(w).relative ~= "" end, vim.api.nvim_list_wins()) == 0 end)')
  eq(#h.floats(), 0)
end

T['<leader>mS picks a set'] = function()
  h.open()
  child.lua('vim.ui.select = function(items, opts, cb) _G.offered = vim.tbl_map(opts.format_item, items); cb("wf") end')
  child.type_keys(' mS')
  eq(child.lua_get('require("earmark.sets").current'), 'wf')
  eq(child.lua_get('_G.offered[1]'), 'vivid ✓  (99 labels)')
end

T['statusline shows the next label, counts and coloured digits'] = function()
  h.open()
  eq(child.lua_get('require("earmark").statusline()'):find('vivid·1', 1, true) ~= nil, true)
  local id = child.lua_get('require("earmark").annotate(0, {0,4}, {0,9}, { set = "vivid", label = "3" }).id')
  child.lua('require("earmark.buffer").set_note(0, ..., "n")', { id })
  child.lua('require("earmark.buffer").rename_label(0, { set = "vivid", label = "1" }, "Fact")')
  local s = child.lua_get('require("earmark").statusline()')
  eq(s:find('%#EarmarkStlSwatch', 1, true) ~= nil, true)
  eq(s:find('vivid·1 %#EarmarkStlName#Fact%*', 1, true) ~= nil, true)
  eq(s:find(' 1 ✎1 ', 1, true) ~= nil, true)
  eq(s:find('%#EarmarkStlDigit3#3', 1, true) ~= nil, true)
  -- digit groups have no background of their own beyond the statusline's
  local d = child.lua_get('vim.api.nvim_get_hl(0, { name = "EarmarkStlDigit3" })')
  eq(d.bg, child.lua_get('vim.api.nvim_get_hl(0, { name = "StatusLine", link = false }).bg'))
  -- inside a section with its own background: colours keep it, and it is restored after
  child.lua('vim.api.nvim_set_hl(0, "Sec", { fg = "#ffffff", bg = "#123456" })')
  s = child.lua_get('require("earmark").statusline({ hl = "Sec" })')
  eq(s:find('%*', 1, true), nil)
  eq(s:find('%#EarmarkStlDigit3_Sec#3', 1, true) ~= nil, true)
  eq(s:sub(-6), '%#Sec#')
  eq(child.lua_get('vim.api.nvim_get_hl(0, { name = "EarmarkStlDigit3_Sec" }).bg'), 0x123456)
  -- buffers without earmark state: empty
  child.cmd('enew')
  eq(child.lua_get('require("earmark").statusline()'), '')
end

return T
