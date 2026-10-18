local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child, "{ prompt = { ask_name = 'never' } }")

local function mark(s, e, label)
  return child.lua_get('require("earmark").annotate(0, ...).id', { s, e, { set = 'vivid', label = label or '3' } })
end

local function note(id, text)
  child.lua('require("earmark.buffer").set_note(0, ...)', { id, text })
end

local function export(opts)
  return child.lua_get('require("earmark.export").markdown(0, ...)', { opts or vim.empty_dict() })
end

T['export groups by label with names, notes and a detached section'] = function()
  h.open()
  local a = mark({ 0, 4 }, { 0, 9 }, '3')
  mark({ 1, 2 }, { 1, 8 }, '3')
  local c = mark({ 2, 0 }, { 2, 5 }, '5')
  note(a, 'too vague #style\nsecond line')
  child.lua('require("earmark.buffer").rename_label(0, { set = "vivid", label = "3" }, "Vague")')
  note(c, 'gone soon')
  child.api.nvim_buf_set_lines(0, 2, 3, false, {})
  child.lua('require("earmark.buffer").on_change(0)')
  local out = export()
  eq(out[1]:match('^# doc%.md — earmark export %(%d+%-%d+%-%d+%)$') ~= nil, true)
  eq(vim.list_slice(out, 2), {
    '',
    '## Vague (vivid·3)',
    '- **"quick"** (L1) #style',
    '  too vague #style',
    '  second line',
    '- **"second"** (L2)',
    '',
    '## Detached',
    '- "Third" — 5 — gone soon',
  })
end

T['export by position names each item'] = function()
  h.open()
  mark({ 1, 2 }, { 1, 8 }, '4')
  mark({ 0, 4 }, { 0, 9 }, '3')
  local out = export({ group_by = 'position' })
  eq(vim.list_slice(out, 3), { '- **3** **"quick"** (L1)', '- **4** **"second"** (L2)' })
end

T['<leader>me writes the export to the default path and opens it'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 }, '3')
  child.lua('vim.ui.input = function(opts, cb) _G.default = opts.default; cb(opts.default) end')
  child.type_keys(' me')
  local default = child.lua_get('_G.default')
  local root = child.lua_get('vim.uv.fs_realpath(_G.root)')
  eq(default, root .. '/.earmark/export/proj-notes-doc.md')
  eq(child.fn.filereadable(default), 1)
  eq(child.api.nvim_buf_get_name(0), default)
  eq(#child.api.nvim_list_wins(), 2)
  -- the export itself is never annotated
  eq(child.lua_get('require("earmark.buffer").state[vim.api.nvim_get_current_buf()] == nil'), true)
end

T['export.location = beside, or both: next to the file as well'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 }, '3')
  child.lua('require("earmark.config").options.export.location = { "beside", "project" }')
  child.lua('vim.ui.input = function(opts, cb) _G.default = opts.default; cb(opts.default) end')
  child.type_keys(' me')
  local root = child.lua_get('vim.uv.fs_realpath(_G.root)')
  local beside = root .. '/notes/doc.earmark.md'
  eq(child.lua_get('_G.default'), beside)
  eq(child.fn.filereadable(beside), 1)
  eq(child.fn.filereadable(root .. '/.earmark/export/proj-notes-doc.md'), 1)
  eq(child.fn.readfile(beside), child.fn.readfile(root .. '/.earmark/export/proj-notes-doc.md'))
end

T['<leader>mo annotates the other occurrences with the same labels'] = function()
  h.open({ 'the cat and the dog and the bird', 'the end' })
  local id = mark({ 0, 0 }, { 0, 3 }, '7')
  child.lua('require("earmark.buffer").set_values(0, ..., { {set="vivid",label="7"}, {set="vivid",label="2"} })', { id })
  child.lua('_G.msgs = {}; vim.notify = function(m) table.insert(_G.msgs, m) end')
  h.cursor(1, 1)
  child.type_keys(' mo')
  local list = child.lua_get('vim.tbl_map(function(x) return { x.s, #x.annotation.values } end, require("earmark").list(0))')
  eq(list, { { { 0, 0 }, 2 }, { { 0, 12 }, 2 }, { { 0, 24 }, 2 }, { { 1, 0 }, 2 } })
  eq(child.lua_get('_G.msgs[#_G.msgs]'), 'earmark: annotated 3 more occurrences')
  -- again: nothing new
  child.type_keys(' mo')
  eq(child.lua_get('_G.msgs[#_G.msgs]'), 'earmark: annotated 0 more occurrences')
end

T['<leader>mg moves the annotation onto a motion, keeping its note'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 }, '3') -- "quick"
  note(id, 'keep me')
  h.cursor(1, 6)
  child.type_keys(' mg', 'iW')
  eq(child.lua_get('_G.texts()'), { { text = 'quick', label = '3', status = 'ok' } })
  h.cursor(1, 4)
  child.type_keys(' mg', '3e') -- quick brown fox
  eq(child.lua_get('_G.texts()'), { { text = 'quick brown fox', label = '3', status = 'ok' } })
  eq(child.lua_get('require("earmark.buffer").annotation(0, ...).note', { id }), 'keep me')
  -- Visual
  h.cursor(1, 4)
  child.type_keys('v', 'e', ' mg')
  eq(child.lua_get('_G.texts()')[1].text, 'quick')
end

T[':Earmark color overrides a label colour in this file and persists'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 }, '3')
  h.cursor(1, 5)
  child.cmd('Earmark color #123456')
  local g = child.lua_get('vim.api.nvim_buf_get_extmarks(0, require("earmark.buffer").ns, 0, -1, { details = true })[1][4].hl_group')
  eq(child.lua_get('vim.api.nvim_get_hl(0, { name = ... }).bg', { g }), 0x123456)
  child.lua('require("earmark.buffer").save(0)')
  local rec = child.lua_get('vim.json.decode(table.concat(vim.fn.readfile(_G.root .. "/.earmark/docs/notes/doc.md.json"), "\\n"))')
  eq(rec.colors, { ['vivid/3'] = '#123456' })
  child.cmd('Earmark color reset')
  g = child.lua_get('vim.api.nvim_buf_get_extmarks(0, require("earmark.buffer").ns, 0, -1, { details = true })[1][4].hl_group')
  eq(g:match('^EarmarkLabel') ~= nil, true)
end

T['default_label is offered first before anything was used'] = function()
  child.lua('require("earmark.config").options.default_label = "vivid/12"')
  h.open()
  h.cursor(1, 4)
  child.type_keys('ghiw', '<CR>')
  h.settle()
  eq(child.lua_get('_G.texts()'), { { text = 'quick', label = '12', status = 'ok' } })
end

return T
