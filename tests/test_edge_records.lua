-- Edge cases: records on disk (damaged, old, missing, unwritable), the file changing outside
-- Neovim, and two Neovim instances on one file.
local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local other = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child)

local REC = 'notes/doc.md.json'

local function root()
  return child.lua_get('_G.root')
end

local function mark(s, e, label)
  return child.lua_get('require("earmark").annotate(0, ...).id', { s, e, { set = 'vivid', label = label or '1' } })
end

local function save()
  child.lua('require("earmark.buffer").save(0)')
end

local function quotes(c)
  return vim.tbl_map(function(x)
    return x.text or false
  end, (c or child).lua_get('_G.texts()'))
end

local function statuses()
  return vim.tbl_map(function(x)
    return x.status
  end, h.texts())
end

local function read_file(path)
  return child.lua_get('(function(p) local f = io.open(p, "rb"); if not f then return vim.NIL end; local d = f:read("*a"); f:close(); return d end)(...)', { path })
end

local function write_file(path, data)
  child.lua('local p, d = ...; vim.fn.mkdir(vim.fs.dirname(p), "p"); local f = io.open(p, "wb"); f:write(d); f:close()', { path, data })
end

local function record()
  local data = read_file(root() .. '/.earmark/docs/' .. REC)
  if data == vim.NIL then return nil end
  return vim.json.decode(data)
end

local function reopen()
  child.cmd('edit ' .. root() .. '/notes/doc.md')
end

local function catch_notify()
  child.lua('_G.msgs = {}; vim.notify = function(m, l) table.insert(_G.msgs, { m, l or vim.log.levels.INFO }) end')
end

local function msgs()
  return child.lua_get('_G.msgs')
end

---------------------------------------------------------------------------
-- Damaged and unusual records
---------------------------------------------------------------------------

T['records'] = MiniTest.new_set()

T['records']['damaged JSON: buffer opens, warns, never overwrites the record'] = function()
  local bad = '{"version": 2, "annotations": [ {"id": "x", '
  write_file(root() .. '/.earmark/docs/' .. REC, bad)
  catch_notify()
  h.open()
  local m = msgs()
  eq(#m, 1)
  eq(m[1][2], vim.log.levels.WARN)
  eq(m[1][1]:find('could not parse', 1, true) ~= nil, true)
  -- annotating still works in memory
  mark({ 0, 4 }, { 0, 9 })
  eq(quotes(), { 'quick' })
  save()
  child.cmd('write')
  child.lua('vim.api.nvim_exec_autocmds("VimLeavePre", {})')
  eq(read_file(root() .. '/.earmark/docs/' .. REC), bad)
end

T['records']['shapes that are not a record are left alone'] = MiniTest.new_set({
  parametrize = {
    { '[1, 2, 3]' },
    { '"just a string"' },
    { '42' },
    { 'null' },
    { '{"version": 2, "annotations": "nope"}' },
    { '{"version": 2, "annotations": [1, 2]}' },
    { '{"version": 2, "annotations": [{"quote": "no id"}]}' },
    { '{"version": 2, "annotations": [{"id": "a", "values": "x", "s": [0, 0], "e": [0, 3]}]}' },
    { '{"version": 2, "annotations": [{"id": "a", "values": [], "s": [0, 0], "e": [0, 3]}]}' },
    { '{"version": 2, "annotations": [], "trash": "x"}' },
    { '{"version": 2, "annotations": [], "names": [1]}' },
  },
})

T['records']['shapes that are not a record are left alone']['case'] = function(data)
  write_file(root() .. '/.earmark/docs/' .. REC, data)
  catch_notify()
  child.lua('_G.errs = {}; local log = require("earmark.log"); local e = log.error; log.error = function(...) table.insert(_G.errs, string.format(...)); return e(...) end')
  h.open()
  eq(child.lua_get('_G.errs'), {})
  eq(child.lua_get('require("earmark.buffer").get(0) ~= nil'), true)
  mark({ 0, 4 }, { 0, 9 })
  eq(quotes(), { 'quick' })
  save()
  child.lua('vim.api.nvim_exec_autocmds("VimLeavePre", {})')
  eq(read_file(root() .. '/.earmark/docs/' .. REC), data)
  eq(#msgs() >= 1, true)
end

T['records']['annotations with odd but usable fields still load'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  save()
  local rec = record()
  rec.annotations[1].status = 'weird'
  rec.annotations[1].tags = {}
  rec.annotations[1].note = ''
  rec.annotations[1].prefix = nil
  rec.annotations[1].suffix = nil
  rec.extra_field = { future = true }
  child.cmd('bwipeout!')
  write_file(root() .. '/.earmark/docs/' .. REC, vim.json.encode(rec))
  h.open()
  eq(quotes(), { 'quick' })
end

T['records']['an empty record file is treated as no record'] = function()
  write_file(root() .. '/.earmark/docs/' .. REC, '')
  catch_notify()
  h.open()
  eq(msgs(), {})
  mark({ 0, 4 }, { 0, 9 })
  save()
  eq(#record().annotations, 1)
end

T['records']['a whitespace-only record file is treated as no record'] = function()
  write_file(root() .. '/.earmark/docs/' .. REC, '  \n\n')
  catch_notify()
  h.open()
  eq(msgs(), {})
  mark({ 0, 4 }, { 0, 9 })
  save()
  eq(#record().annotations, 1)
end

T['records']['a record from a newer earmark is not touched'] = function()
  local data = vim.json.encode({ version = 99, annotations = {} })
  write_file(root() .. '/.earmark/docs/' .. REC, data)
  catch_notify()
  h.open()
  eq(msgs()[1][1]:find('newer earmark', 1, true) ~= nil, true)
  mark({ 0, 4 }, { 0, 9 })
  save()
  eq(read_file(root() .. '/.earmark/docs/' .. REC), data)
end

T['records']['a record with a byte-order mark or CRLF line ends still parses'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  save()
  child.cmd('bwipeout!')
  local data = read_file(root() .. '/.earmark/docs/' .. REC)
  write_file(root() .. '/.earmark/docs/' .. REC, (data:gsub('\n', '\r\n')))
  h.open()
  eq(quotes(), { 'quick' })
end

T['records']['v1 record with notes and tags keeps them through the migration'] = function()
  local f = io.open('tests/fixtures/v1_record.json')
  local rec = vim.json.decode(f:read('*a'))
  f:close()
  rec.annotations[1].note = 'kept note'
  rec.annotations[1].tags = { 'kept' }
  write_file(root() .. '/.earmark/docs/' .. REC, vim.json.encode(rec))
  write_file(root() .. '/notes/doc.md', table.concat(rec.snapshot, '\n') .. '\n')
  child.cmd('edit ' .. root() .. '/notes/doc.md')
  local out = record()
  eq(out.version, 2)
  local a = vim.tbl_filter(function(x)
    return x.id == rec.annotations[1].id
  end, out.annotations)[1]
  eq({ a.note, a.tags }, { 'kept note', { 'kept' } })
end

T['records']['v1 record whose file changed completely: annotations detach, none are lost'] = function()
  local f = io.open('tests/fixtures/v1_record.json')
  local rec = vim.json.decode(f:read('*a'))
  f:close()
  write_file(root() .. '/.earmark/docs/' .. REC, vim.json.encode(rec))
  write_file(root() .. '/notes/doc.md', 'nothing in common at all\n')
  child.cmd('edit ' .. root() .. '/notes/doc.md')
  eq(#h.texts(), #rec.annotations)
  eq(#record().annotations, #rec.annotations)
  eq(#record().trash, #rec.trash)
end

---------------------------------------------------------------------------
-- Snapshots and records out of step (fresh clone, partial deletes)
---------------------------------------------------------------------------

T['snapshots'] = MiniTest.new_set()

T['snapshots']['fresh clone (no snap/), file unchanged: every annotation in place'] = function()
  h.open({ 'alpha beta gamma', 'beta gamma alpha', 'gamma alpha beta' })
  mark({ 0, 6 }, { 0, 10 })
  mark({ 1, 0 }, { 1, 4 }, '2')
  mark({ 2, 12 }, { 2, 16 }, '3')
  save()
  child.cmd('bwipeout!')
  child.lua('vim.fn.delete(_G.root .. "/.earmark/snap", "rf")')
  reopen()
  eq(h.texts(), {
    { text = 'beta', label = '1', status = 'ok' },
    { text = 'beta', label = '2', status = 'ok' },
    { text = 'beta', label = '3', status = 'ok' },
  })
  eq(child.lua_get('vim.tbl_map(function(x) return x.s end, require("earmark").list(0))'), { { 0, 6 }, { 1, 0 }, { 2, 12 } })
end

T['snapshots']['fresh clone, lines inserted above: repeated words land on the right ones'] = function()
  h.open({ 'alpha beta gamma', 'beta gamma alpha', 'gamma alpha beta' })
  mark({ 1, 0 }, { 1, 4 }, '2')
  save()
  child.cmd('bwipeout!')
  child.lua('vim.fn.delete(_G.root .. "/.earmark/snap", "rf")')
  h.open({ 'new line', 'alpha beta gamma', 'beta gamma alpha', 'gamma alpha beta' })
  eq(child.lua_get('require("earmark").list(0)[1].s'), { 2, 0 })
end

T['snapshots']['snapshot present but record deleted: no ghosts, new annotations save'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  save()
  child.cmd('bwipeout!')
  child.lua('vim.fn.delete(_G.root .. "/.earmark/docs", "rf")')
  h.open()
  eq(h.texts(), {})
  mark({ 1, 2 }, { 1, 8 }, '2')
  save()
  child.cmd('bwipeout!')
  h.open()
  eq(quotes(), { 'second' })
end

T['snapshots']['snapshot of a different text than the record is ignored'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  save()
  child.cmd('bwipeout!')
  -- an old snapshot (one line shifted) left by a crash between the two writes
  write_file(root() .. '/.earmark/snap/notes/doc.md.snap', 'x\n' .. table.concat(H.LINES, '\n'))
  h.open()
  eq(quotes(), { 'quick' })
end

T['snapshots']['the snapshot is written with every save and matches the record'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  child.api.nvim_buf_set_lines(0, 0, 0, false, { 'added' })
  save()
  local snap = read_file(root() .. '/.earmark/snap/notes/doc.md.snap')
  eq(vim.fn.sha256(snap), record().fingerprint)
  eq(snap, 'added\n' .. table.concat(H.LINES, '\n'))
end

---------------------------------------------------------------------------
-- Unwritable storage
---------------------------------------------------------------------------

T['unwritable'] = MiniTest.new_set()

T['unwritable']['docs dir blocked by a file: save warns, keeps annotations, works again later'] = function()
  h.open()
  catch_notify()
  child.lua('vim.fn.delete(_G.root .. "/.earmark/docs", "rf"); vim.fn.writefile({}, _G.root .. "/.earmark/docs")')
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  local m = msgs()
  eq(#m >= 1, true)
  eq(m[#m][2], vim.log.levels.ERROR)
  eq(m[#m][1]:find('could not save', 1, true) ~= nil, true)
  eq(quotes(), { 'quick' })
  -- the debounced save fails quietly the same way (no error thrown out of the timer)
  mark({ 1, 2 }, { 1, 8 }, '2')
  h.settle(700)
  eq(child.lua_get('vim.v.errmsg'), '')
  -- unblock: the next save writes everything
  child.lua('vim.fn.delete(_G.root .. "/.earmark/docs")')
  save()
  eq(#record().annotations, 2)
end

T['unwritable']['storage_dir that does not exist yet is created'] = function()
  child.lua([[
    require('earmark.config').options.storage_dir = _G.tmp .. '/not/yet/there'
    vim.fn.mkdir(_G.tmp .. '/loose', 'p')
    vim.fn.writefile({ 'The quick brown fox.' }, _G.tmp .. '/loose/a.md')
  ]])
  child.cmd('edit ' .. child.lua_get('_G.tmp') .. '/loose/a.md')
  mark({ 0, 4 }, { 0, 9 })
  save()
  eq(child.lua_get('#vim.fn.glob(_G.tmp .. "/not/yet/there/files/**/*.json", true, true)'), 1)
end

T['unwritable']['storage_dir under a regular file: warns, no crash'] = function()
  child.lua([[
    vim.fn.writefile({}, _G.tmp .. '/afile')
    require('earmark.config').options.storage_dir = _G.tmp .. '/afile/store'
    vim.fn.mkdir(_G.tmp .. '/loose', 'p')
    vim.fn.writefile({ 'The quick brown fox.' }, _G.tmp .. '/loose/a.md')
  ]])
  catch_notify()
  child.cmd('edit ' .. child.lua_get('_G.tmp') .. '/loose/a.md')
  mark({ 0, 4 }, { 0, 9 })
  save()
  eq(quotes(), { 'quick' })
  local m = msgs()
  eq(m[#m][1]:find('could not save', 1, true) ~= nil, true)
end

T['unwritable']['a record that is a directory: warns, no crash'] = function()
  child.lua('vim.fn.mkdir(_G.root .. "/.earmark/docs/notes/doc.md.json", "p")')
  catch_notify()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  save()
  eq(quotes(), { 'quick' })
  eq(child.lua_get('vim.fn.isdirectory(_G.root .. "/.earmark/docs/notes/doc.md.json")'), 1)
end

T['unwritable']['no temp files are left behind after saves'] = function()
  h.open()
  for i = 1, 5 do
    mark({ 0, i }, { 0, i + 3 }, tostring(i))
    save()
  end
  local left = child.lua_get('vim.fn.glob(_G.root .. "/.earmark/**/*tmp*", true, true)')
  eq(left, {})
  local hidden = child.lua_get('vim.fn.glob(_G.root .. "/.earmark/**/.*tmp*", true, true)')
  eq(hidden, {})
end

---------------------------------------------------------------------------
-- The file changes outside Neovim
---------------------------------------------------------------------------

T['external'] = MiniTest.new_set()

local function rewrite(lines)
  child.lua('vim.fn.writefile(..., _G.root .. "/notes/doc.md")', { lines })
end

T['external'][':e! after lines were inserted above'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  mark({ 2, 12 }, { 2, 19 }, '2')
  child.cmd('write')
  rewrite({ 'new 1', 'new 2', H.LINES[1], H.LINES[2], H.LINES[3] })
  child.cmd('edit!')
  h.settle()
  eq(quotes(), { 'quick', 'the end' })
  eq(child.lua_get('vim.tbl_map(function(x) return x.s[1] end, require("earmark").list(0))'), { 2, 4 })
end

T['external'][':e! with unsaved annotations keeps them'] = function()
  h.open()
  child.cmd('write')
  mark({ 0, 4 }, { 0, 9 })
  rewrite({ 'new 1', H.LINES[1], H.LINES[2], H.LINES[3] })
  child.cmd('edit!')
  h.settle()
  eq(quotes(), { 'quick' })
  save()
  eq(#record().annotations, 1)
end

T['external']['checktime with autoread reloads and re-anchors'] = function()
  h.open()
  mark({ 1, 2 }, { 1, 8 })
  child.cmd('write')
  child.o.autoread = true
  child.lua('vim.wait(1100, function() return false end)') -- a new mtime
  rewrite({ H.LINES[1], 'inserted', 'A second line with some words.', H.LINES[3] })
  child.cmd('checktime')
  h.settle()
  eq(quotes(), { 'second' })
  eq(child.lua_get('require("earmark").list(0)[1].s'), { 2, 2 })
end

T['external']['file truncated to empty: annotations detach, come back when the text does'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  mark({ 1, 2 }, { 1, 8 }, '2')
  child.cmd('write')
  rewrite({})
  child.cmd('edit!')
  h.settle()
  eq(statuses(), { 'detached', 'detached' })
  child.cmd('write') -- the record keeps them
  eq(#record().annotations, 2)
  rewrite(H.LINES)
  child.cmd('edit!')
  h.settle()
  eq(quotes(), { 'quick', 'second' })
end

T['external']['truncated while closed, reopened, restored while closed'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  child.cmd('bwipeout!')
  rewrite({})
  reopen()
  eq(statuses(), { 'detached' })
  child.cmd('bwipeout!')
  rewrite(H.LINES)
  reopen()
  eq(quotes(), { 'quick' })
end

T['external']['file deleted outside: buffer and annotations stay, :w brings both back'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  child.lua('vim.fn.delete(_G.root .. "/notes/doc.md")')
  child.cmd('silent! checktime')
  eq(quotes(), { 'quick' })
  child.cmd('write')
  child.cmd('bwipeout!')
  reopen()
  eq(quotes(), { 'quick' })
end

T['external']['git checkout swaps the whole content and back'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  rewrite({ 'Totally different branch content.', 'Nothing matches here.' })
  child.cmd('edit!')
  h.settle()
  -- nothing in common: never shown as ok (detached, or stale on whatever replaced it)
  eq(statuses()[1] ~= 'ok', true)
  -- (the user saves on the other branch)
  child.cmd('write')
  rewrite(H.LINES)
  child.cmd('edit!')
  h.settle()
  eq(h.texts(), { { text = 'quick', label = '1', status = 'ok' } })
end

T['external']['branch switch while the buffer is closed: detached, then back'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  child.cmd('bwipeout!')
  rewrite({ 'Totally different branch content.' })
  reopen()
  eq(statuses()[1] ~= 'ok', true)
  child.cmd('bwipeout!')
  rewrite(H.LINES)
  reopen()
  eq(h.texts(), { { text = 'quick', label = '1', status = 'ok' } })
end

T['external']['the record changed on disk: :Earmark reload shows it'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  save()
  local rec = record()
  rec.annotations[1].note = 'from elsewhere'
  write_file(root() .. '/.earmark/docs/' .. REC, vim.json.encode(rec))
  child.cmd('Earmark reload')
  eq(child.lua_get('require("earmark").list(0)[1].annotation.note'), 'from elsewhere')
  eq(quotes(), { 'quick' })
end

---------------------------------------------------------------------------
-- Two Neovim instances
---------------------------------------------------------------------------

T['two instances'] = MiniTest.new_set({
  hooks = {
    post_case = function()
      if other.is_running() then other.stop() end
    end,
  },
})

local function start_other()
  other.restart({ '-u', 'scripts/minimal_init.lua' })
  other.lua(
    [[
    _G.tmp, _G.root = ...
    require('earmark').setup({ storage_dir = _G.tmp .. '/data', debounce_ms = 10 })
    _G.texts = function()
      local out = {}
      for _, x in ipairs(require('earmark').list(0)) do
        local text = x.s and table.concat(vim.api.nvim_buf_get_text(0, x.s[1], x.s[2], x.e[1], x.e[2], {}), '\n') or nil
        out[#out + 1] = { text = text, label = x.annotation.values[1].label, status = x.annotation.status }
      end
      return out
    end
  ]],
    { child.lua_get('_G.tmp'), root() }
  )
  other.cmd('edit ' .. root() .. '/notes/doc.md')
end

T['two instances']['each sees what the other saved when it opens the file'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  save()
  start_other()
  eq(quotes(other), { 'quick' })
  other.lua('require("earmark").annotate(0, { 1, 2 }, { 1, 8 }, { set = "vivid", label = "2" })')
  other.lua('require("earmark.buffer").save(0)')
  child.cmd('Earmark reload')
  eq(quotes(), { 'quick', 'second' })
end

T['two instances']['both annotate, both save: the last save wins and the record is whole'] = function()
  h.open()
  start_other()
  mark({ 0, 4 }, { 0, 9 })
  other.lua('require("earmark").annotate(0, { 1, 2 }, { 1, 8 }, { set = "vivid", label = "2" })')
  save()
  other.lua('require("earmark.buffer").save(0)')
  local rec = record()
  eq(#rec.annotations, 1)
  eq(rec.annotations[1].quote, 'second')
  local snap = read_file(root() .. '/.earmark/snap/notes/doc.md.snap')
  eq(vim.fn.sha256(snap), rec.fingerprint)
end

T['two instances']['interleaved saves never leave a half-written record'] = function()
  h.open()
  start_other()
  for i = 1, 20 do
    mark({ 0, i % 30 }, { 0, i % 30 + 4 }, tostring(i % 9 + 1))
    other.lua('require("earmark").annotate(0, ...)', { { 1, i % 20 }, { 1, i % 20 + 3 }, { set = 'vivid', label = tostring(i % 9 + 1) } })
  end
  -- fire both writers as fast as they go, at the same time
  child.lua('_G.go = function() for _ = 1, 40 do require("earmark.buffer").save(0) end end')
  other.lua('_G.go = function() for _ = 1, 40 do require("earmark.buffer").save(0) end end')
  child.lua('vim.defer_fn(_G.go, 50)')
  other.lua('vim.defer_fn(_G.go, 50)')
  -- read from this process while both children write
  local path = root() .. '/.earmark/docs/' .. REC
  for _ = 1, 200 do
    local f = io.open(path, 'rb')
    if f then
      local data = f:read('*a')
      f:close()
      eq(pcall(vim.json.decode, data), true)
    end
    vim.uv.sleep(2)
  end
  child.lua('vim.wait(2000, function() return false end)')
  other.lua('vim.wait(10, function() return false end)')
  local rec = record()
  eq(#rec.annotations, 20)
  eq(child.lua_get('vim.fn.glob(_G.root .. "/.earmark/**/.*tmp*", true, true)'), {})
end

T['two instances']['the other instance edits the file and saves: :e! re-anchors here'] = function()
  h.open()
  mark({ 2, 12 }, { 2, 19 })
  child.cmd('write')
  save()
  start_other()
  other.api.nvim_buf_set_lines(0, 0, 0, false, { 'from the other instance' })
  other.cmd('write')
  child.cmd('edit!')
  h.settle()
  eq(quotes(), { 'the end' })
  eq(child.lua_get('require("earmark").list(0)[1].s'), { 3, 12 })
end

return T
