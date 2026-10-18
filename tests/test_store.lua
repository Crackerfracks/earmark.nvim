local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child)

local function fixture()
  local f = io.open('tests/fixtures/v1_record.json')
  local data = f:read('*a')
  f:close()
  return data
end

local function install_v1(lines)
  child.lua(
    [[
    local data, lines = ...
    local rec = vim.json.decode(data)
    vim.fn.mkdir(_G.root .. '/.earmark/docs/notes', 'p')
    vim.fn.writefile(vim.split(data, '\n'), _G.root .. '/.earmark/docs/notes/doc.md.json')
    vim.fn.mkdir(_G.root .. '/notes', 'p')
    vim.fn.writefile(lines or rec.snapshot, _G.root .. '/notes/doc.md')
  ]],
    { fixture(), lines }
  )
end

local function record()
  return child.lua_get([[vim.json.decode(table.concat(vim.fn.readfile(_G.root .. '/.earmark/docs/notes/doc.md.json'), '\n'))]])
end

T['v1 record'] = MiniTest.new_set()

T['v1 record']['opens with annotations and trash, and is rewritten as v2'] = function()
  install_v1()
  child.cmd('edit ' .. child.lua_get('_G.root') .. '/notes/doc.md')
  local quotes = vim.tbl_map(function(x)
    return x.text
  end, h.texts())
  table.sort(quotes)
  eq(quotes, { 'for', 'his sh', 'is', 'test', 'this' })
  local rec = record()
  eq(rec.version, 2)
  eq(rec.snapshot, nil)
  eq(#rec.trash, 5)
  eq(#rec.annotations, 5)
  -- snapshot moved to its own file, ignored by git
  eq(child.lua_get([[vim.fn.filereadable(_G.root .. '/.earmark/snap/notes/doc.md.snap')]]), 1)
  local gi = child.lua_get([[table.concat(vim.fn.readfile(_G.root .. '/.earmark/.gitignore'), '\n')]])
  MiniTest.expect.equality(gi:find('snap/', 1, true) ~= nil, true)
end

T['v1 record']['re-anchors against its inline snapshot after an outside edit'] = function()
  local rec = vim.json.decode(fixture())
  local lines = vim.deepcopy(rec.snapshot)
  table.insert(lines, 1, 'A new first line')
  install_v1(lines)
  child.cmd('edit ' .. child.lua_get('_G.root') .. '/notes/doc.md')
  local rows = child.lua_get('vim.tbl_map(function(x) return x.s[1] end, require("earmark").list(0))')
  eq(rows, { 6, 6, 6, 6, 6 })
end

T['snapshot'] = MiniTest.new_set()

T['snapshot']['missing snapshot file still anchors by quote and context'] = function()
  h.open()
  h.cursor(1, 10)
  child.type_keys('2ghiw')
  child.cmd('write')
  child.lua('require("earmark.buffer").save(0)')
  child.cmd('bwipeout!')
  child.lua([[vim.fn.delete(_G.root .. '/.earmark/snap', 'rf')]])
  -- the file changed while the snapshot was lost
  child.lua([[vim.fn.writefile({ 'Inserted.', 'The quick brown fox jumps over the lazy dog.', 'x' }, _G.root .. '/notes/doc.md')]])
  h.open(nil)
  child.cmd('edit ' .. child.lua_get('_G.root') .. '/notes/doc.md')
  eq(h.texts(), { { text = 'brown', label = '2', status = 'ok' } })
end

T['snapshot']['a stale snapshot is ignored'] = function()
  h.open()
  h.cursor(1, 10)
  child.type_keys('2ghiw')
  child.lua('require("earmark.buffer").save(0)')
  child.cmd('bwipeout!')
  child.lua([[vim.fn.writefile({ 'garbage' }, _G.root .. '/.earmark/snap/notes/doc.md.snap')]])
  child.cmd('edit ' .. child.lua_get('_G.root') .. '/notes/doc.md')
  eq(h.texts(), { { text = 'brown', label = '2', status = 'ok' } })
end

T['mru'] = function()
  child.lua([[
    local store = require('earmark.store')
    local p = _G.tmp .. '/names.json'
    for i = 1, 60 do store.mru_push(p, 'vivid/3', 'n' .. i) end
    store.mru_push(p, 'vivid/3', 'n10')
    _G.res = store.mru_get(p, 'vivid/3')
  ]])
  local res = child.lua_get('_G.res')
  eq(#res, 50)
  eq(res[1], 'n10')
  eq(res[2], 'n60')
  eq(child.lua_get([[#require('earmark.store').mru_get(_G.tmp .. '/names.json', 'nope')]]), 0)
end

T['notes and names persist through reopen'] = function()
  h.open()
  h.cursor(1, 10)
  child.type_keys('2ghiw')
  child.lua([[
    local b = require('earmark.buffer')
    local id = require('earmark').list(0)[1].annotation.id
    b.set_note(0, id, 'my note #tag')
    b.set_tags(0, id, { 'x', 'x', 'y' })
    b.rename_label(0, { set = 'vivid', label = '2' }, 'Factually Inaccurate')
    b.save(0)
  ]])
  child.cmd('bwipeout!')
  child.cmd('edit ' .. child.lua_get('_G.root') .. '/notes/doc.md')
  local a = child.lua_get('require("earmark").list(0)[1].annotation')
  eq(a.note, 'my note #tag')
  eq(a.tags, { 'x', 'y' })
  eq(child.lua_get([[require('earmark.buffer').display_name(0, { set = 'vivid', label = '2' })]]), 'Factually Inaccurate')
  eq(child.lua_get([[require('earmark.buffer').display_name(0, { set = 'vivid', label = '3' })]]), '3')
end

T['copying a file does not take over its record; saveas moves it'] = function()
  h.open()
  h.cursor(1, 10)
  child.type_keys('2ghiw')
  child.cmd('write')
  child.lua([[vim.fn.writefile(vim.fn.readfile(_G.root .. '/notes/doc.md'), _G.root .. '/notes/copy.md')]])
  child.cmd('edit ' .. child.lua_get('_G.root') .. '/notes/copy.md')
  eq(h.texts(), {})
  child.cmd('edit ' .. child.lua_get('_G.root') .. '/notes/doc.md')
  eq(#h.texts(), 1)
  child.cmd('saveas ' .. child.lua_get('_G.root') .. '/notes/moved.md')
  local docs = child.lua_get([[vim.fn.glob(_G.root .. '/.earmark/docs/notes/*.json', false, true)]])
  eq(#docs, 1)
  eq(docs[1]:match('[^/]+$'), 'moved.md.json')
end

return T
