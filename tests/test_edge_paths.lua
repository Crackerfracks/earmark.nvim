-- Edge cases: where records live as files are renamed, moved, linked and re-rooted.
local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child)

local function root()
  return child.lua_get('_G.root')
end

local function mark(s, e, label)
  return child.lua_get('require("earmark").annotate(0, ...).id', { s, e, { set = 'vivid', label = label or '1' } })
end

local function save()
  child.lua('require("earmark.buffer").save(0)')
end

--- Record files (relative to `dir`) found under it.
local function records(dir)
  return child.lua_get(
    [[(function(dir)
    local out = {}
    if vim.fn.isdirectory(dir) == 0 then return out end
    for name, t in vim.fs.dir(dir, { depth = 50 }) do
      if t == 'file' and name:match('%.json$') then out[#out + 1] = name end
    end
    table.sort(out)
    return out
  end)(...)]],
    { dir }
  )
end

local function quotes()
  return vim.tbl_map(function(x)
    return x.text or false
  end, h.texts())
end

---------------------------------------------------------------------------
-- Renames inside Neovim
---------------------------------------------------------------------------

T['rename'] = MiniTest.new_set()

T['rename'][':saveas moves record and snapshot, the old ones go'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  child.cmd('saveas ' .. root() .. '/notes/other.md')
  eq(records(root() .. '/.earmark/docs'), { 'notes/other.md.json' })
  eq(child.lua_get([[vim.fn.filereadable(_G.root .. '/.earmark/snap/notes/other.md.snap')]]), 1)
  eq(child.lua_get([[vim.fn.filereadable(_G.root .. '/.earmark/snap/notes/doc.md.snap')]]), 0)
  child.cmd('bwipeout!')
  child.cmd('edit ' .. root() .. '/notes/other.md')
  eq(quotes(), { 'quick' })
end

T['rename'][':file newname before the file exists, then :write'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  mark({ 1, 2 }, { 1, 8 }, '2')
  child.cmd('write')
  child.cmd('file ' .. root() .. '/notes/renamed.md')
  child.cmd('write')
  eq(records(root() .. '/.earmark/docs'), { 'notes/renamed.md.json' })
  child.cmd('bwipeout!')
  child.cmd('edit ' .. root() .. '/notes/renamed.md')
  eq(quotes(), { 'quick', 'second' })
end

T['rename'][':file into a directory that does not exist yet'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  child.cmd('file ' .. root() .. '/new/deeper/doc.md')
  eq(records(root() .. '/.earmark/docs'), { 'new/deeper/doc.md.json' })
  child.fn.mkdir(root() .. '/new/deeper', 'p')
  child.cmd('write')
  child.cmd('bwipeout!')
  child.cmd('edit ' .. root() .. '/new/deeper/doc.md')
  eq(quotes(), { 'quick' })
end

T['rename'][':file out of the project moves the record to storage_dir'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  child.lua('vim.fn.mkdir(_G.tmp .. "/outside", "p")')
  child.cmd('file ' .. child.lua_get('_G.tmp') .. '/outside/doc.md')
  child.cmd('write')
  eq(records(root() .. '/.earmark/docs'), {})
  local key = child.lua_get('(vim.uv.fs_realpath(_G.tmp) .. "/outside/doc.md"):gsub("^/", "")')
  eq(records(child.lua_get('_G.tmp') .. '/data/files'), { key .. '.json' })
  child.cmd('bwipeout!')
  child.cmd('edit ' .. child.lua_get('_G.tmp') .. '/outside/doc.md')
  eq(quotes(), { 'quick' })
end

T['rename'][':saveas! over an annotated file replaces its record'] = function()
  h.open({ 'other file text', 'more' }, 'notes/target.md')
  mark({ 0, 0 }, { 0, 5 }, '3')
  child.cmd('write')
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  child.cmd('bwipeout! ' .. child.lua_get('vim.fn.bufnr(_G.root .. "/notes/target.md")'))
  child.cmd('saveas! ' .. root() .. '/notes/target.md')
  eq(records(root() .. '/.earmark/docs'), { 'notes/target.md.json' })
  child.cmd('bwipeout!')
  child.cmd('edit ' .. root() .. '/notes/target.md')
  eq(h.texts(), { { text = 'quick', label = '1', status = 'ok' } })
end

T['rename'][':write copy.md writes a copy; the record stays with the buffer'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  child.cmd('write ' .. root() .. '/notes/copy.md')
  eq(records(root() .. '/.earmark/docs'), { 'notes/doc.md.json' })
  eq(child.lua_get('vim.fs.basename(vim.api.nvim_buf_get_name(0))'), 'doc.md')
end

T['rename']['an unnamed buffer written to a file takes its annotations along'] = function()
  child.cmd('enew')
  child.api.nvim_buf_set_lines(0, 0, -1, false, H.LINES)
  mark({ 0, 4 }, { 0, 9 })
  save()
  eq(#child.lua_get('vim.fn.glob(_G.tmp .. "/data/scratch/*.json", true, true)'), 1)
  child.fn.mkdir(root() .. '/notes', 'p')
  child.cmd('write ' .. root() .. '/notes/new.md')
  eq(records(root() .. '/.earmark/docs'), { 'notes/new.md.json' })
  eq(#child.lua_get('vim.fn.glob(_G.tmp .. "/data/scratch/*.json", true, true)'), 0)
  child.cmd('bwipeout!')
  child.cmd('edit ' .. root() .. '/notes/new.md')
  eq(quotes(), { 'quick' })
end

T['rename']['a nofile scratch buffer keeps its own record and never touches files'] = function()
  child.lua([[
    _G.sb = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(_G.sb, 0, -1, false, { 'scratch text here' })
    vim.api.nvim_buf_set_name(_G.sb, _G.root .. '/notes/doc.md.preview')
    require('earmark').annotate(_G.sb, { 0, 0 }, { 0, 7 }, { set = 'vivid', label = '1' })
    require('earmark.buffer').save(_G.sb)
  ]])
  eq(records(root() .. '/.earmark/docs'), {})
  eq(#child.lua_get('vim.fn.glob(_G.tmp .. "/data/scratch/*.json", true, true)'), 1)
end

---------------------------------------------------------------------------
-- Renames outside Neovim
---------------------------------------------------------------------------

T['moved outside'] = MiniTest.new_set()

T['moved outside']['mv while open, then :e the new path: annotations follow'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  child.lua('vim.uv.fs_rename(_G.root .. "/notes/doc.md", _G.root .. "/notes/moved.md")')
  child.cmd('edit ' .. root() .. '/notes/moved.md')
  eq(quotes(), { 'quick' })
  eq(records(root() .. '/.earmark/docs'), { 'notes/moved.md.json' })
  -- the old buffer is still listed (hidden); quitting must not bring its record back
  child.lua('vim.api.nvim_exec_autocmds("VimLeavePre", {})')
  eq(records(root() .. '/.earmark/docs'), { 'notes/moved.md.json' })
end

T['moved outside']['mv while open, annotate in the new buffer, wipe the old one'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  local old = child.lua_get('vim.api.nvim_get_current_buf()')
  child.lua('vim.uv.fs_rename(_G.root .. "/notes/doc.md", _G.root .. "/notes/moved.md")')
  child.cmd('edit ' .. root() .. '/notes/moved.md')
  mark({ 1, 2 }, { 1, 8 }, '2')
  save()
  child.cmd('bwipeout! ' .. old)
  eq(records(root() .. '/.earmark/docs'), { 'notes/moved.md.json' })
  child.cmd('bwipeout!')
  child.cmd('edit ' .. root() .. '/notes/moved.md')
  eq(quotes(), { 'quick', 'second' })
end

T['moved outside']['mv to a new directory, then :e the old path shows an empty new file'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  child.lua('vim.fn.mkdir(_G.root .. "/elsewhere", "p")')
  child.lua('vim.uv.fs_rename(_G.root .. "/notes/doc.md", _G.root .. "/elsewhere/doc.md")')
  child.cmd('edit')
  eq(child.lua_get('vim.api.nvim_buf_get_lines(0, 0, -1, false)'), { '' })
  -- nothing was lost: the moved file still finds the record
  child.cmd('bwipeout!')
  child.cmd('edit ' .. root() .. '/elsewhere/doc.md')
  eq(quotes(), { 'quick' })
end

T['moved outside']['mv after another file was opened (rename index already built)'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  child.cmd('bwipeout!')
  h.open({ 'an unannotated file' }, 'notes/plain.md') -- looks for renamed records
  child.lua('vim.uv.fs_rename(_G.root .. "/notes/doc.md", _G.root .. "/notes/moved.md")')
  child.cmd('edit ' .. root() .. '/notes/moved.md')
  eq(quotes(), { 'quick' })
end

T['moved outside']['a copy of an orphaned record\'s text is adopted once only'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  child.cmd('bwipeout!')
  child.lua([[
    vim.fn.writefile(vim.fn.readfile(_G.root .. '/notes/doc.md'), _G.root .. '/notes/a.md')
    vim.fn.writefile(vim.fn.readfile(_G.root .. '/notes/doc.md'), _G.root .. '/notes/b.md')
    vim.fn.delete(_G.root .. '/notes/doc.md')
  ]])
  child.cmd('edit ' .. root() .. '/notes/a.md')
  eq(quotes(), { 'quick' })
  child.cmd('edit ' .. root() .. '/notes/b.md')
  eq(quotes(), {})
  eq(records(root() .. '/.earmark/docs'), { 'notes/a.md.json' })
end

T['moved outside']['a new file with the same text as an annotated, existing file adopts nothing'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  h.open(H.LINES, 'notes/same.md')
  eq(quotes(), {})
  eq(records(root() .. '/.earmark/docs'), { 'notes/doc.md.json' })
end

T['moved outside']['opening files in a project with 2000 records stays fast'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  save()
  local ms = child.lua_get([[(function()
    local data = table.concat(vim.fn.readfile(_G.root .. '/.earmark/docs/notes/doc.md.json'), '\n')
    for i = 1, 2000 do
      local rec = vim.json.decode(data)
      rec.doc.key = ('many/%d.md'):format(i)
      rec.fingerprint = vim.fn.sha256(tostring(i))
      require('earmark.store').write_json(_G.root .. ('/.earmark/docs/many/%d.md.json'):format(i), rec)
    end
    local t0 = vim.uv.hrtime()
    for i = 1, 5 do
      _G.open(('fresh/%d.md'):format(i), { 'unannotated text ' .. i })
      require('earmark').annotate(0, { 0, 0 }, { 0, 3 }, { set = 'vivid', label = '1' })
      require('earmark.buffer').save(0) -- (a write: the next open looks again)
    end
    return (vim.uv.hrtime() - t0) / 1e6 / 5
  end)()]])
  if ms > 2000 then error(('opening a file took %d ms'):format(ms)) end
end

---------------------------------------------------------------------------
-- Awkward path names
---------------------------------------------------------------------------

T['names'] = MiniTest.new_set({
  parametrize = {
    { 'with space/my doc.md' },
    { 'ünïcödé/日本語 ノート.md' },
    { 'brackets/[draft] {v2} (final).md' },
    { 'globs/*star?*.md' },
    { "quotes/it's \"quoted\".md" },
    { 'percent/100% #1 ~tilde.md' },
    { 'dots/.hidden.md' },
    { 'trailing/name.' },
  },
})

T['names']['annotations survive reopen'] = function(rel)
  h.open(nil, rel)
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  eq(records(root() .. '/.earmark/docs'), { rel .. '.json' })
  child.cmd('bwipeout!')
  h.open(nil, rel)
  eq(quotes(), { 'quick' })
  -- and a rename keeps them
  child.fn.mkdir(vim.fs.dirname(root() .. '/renamed/' .. rel), 'p')
  child.cmd('saveas ' .. vim.fn.fnameescape(root() .. '/renamed/' .. rel))
  eq(records(root() .. '/.earmark/docs'), { 'renamed/' .. rel .. '.json' })
end

T['long names'] = MiniTest.new_set()

T['long names']['a 245-byte file name still saves'] = function()
  local name = ('n'):rep(242) .. '.md'
  h.open(nil, name)
  mark({ 0, 4 }, { 0, 9 })
  save()
  eq(records(root() .. '/.earmark/docs'), { name .. '.json' })
  child.cmd('bwipeout!')
  h.open(nil, name)
  eq(quotes(), { 'quick' })
end

T['long names']['a name too long for its record warns and keeps the annotations'] = function()
  local name = ('n'):rep(252) .. '.md'
  h.open(nil, name)
  child.lua('_G.msgs = {}; vim.notify = function(m, l) table.insert(_G.msgs, { m, l }) end')
  mark({ 0, 4 }, { 0, 9 })
  save()
  local msgs = child.lua_get('_G.msgs')
  eq(#msgs >= 1, true)
  eq(msgs[#msgs][1]:match('^earmark: could not save') ~= nil, true)
  eq(quotes(), { 'quick' })
  -- nothing half-written left behind
  eq(child.lua_get([[#vim.fn.glob(_G.root .. '/.earmark/docs/*', true, true)]]), 0)
end

T['long names']['deeply nested path'] = function()
  local parts = {}
  for i = 1, 40 do
    parts[i] = ('dir%02d_%s'):format(i, ('x'):rep(40))
  end
  local rel = table.concat(parts, '/') .. '/doc.md'
  h.open(nil, rel)
  mark({ 0, 4 }, { 0, 9 })
  save()
  child.cmd('bwipeout!')
  h.open(nil, rel)
  eq(quotes(), { 'quick' })
end

---------------------------------------------------------------------------
-- Symlinks
---------------------------------------------------------------------------

T['symlinks'] = MiniTest.new_set()

T['symlinks']['link and real path share one record'] = function()
  h.open()
  child.cmd('bwipeout!')
  child.lua('vim.uv.fs_symlink(_G.root .. "/notes/doc.md", _G.root .. "/link.md")')
  child.cmd('edit ' .. root() .. '/link.md')
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  eq(records(root() .. '/.earmark/docs'), { 'notes/doc.md.json' })
  child.cmd('edit ' .. root() .. '/notes/doc.md')
  mark({ 1, 2 }, { 1, 8 }, '2')
  child.cmd('write')
  eq(records(root() .. '/.earmark/docs'), { 'notes/doc.md.json' })
  child.cmd('%bwipeout!')
  child.cmd('edit ' .. root() .. '/link.md')
  eq(quotes(), { 'quick', 'second' })
end

T['symlinks']['link and target loaded together share a buffer, so nothing is clobbered'] = function()
  h.open()
  child.cmd('bwipeout!')
  child.lua('vim.uv.fs_symlink(_G.root .. "/notes/doc.md", _G.root .. "/link.md")')
  child.lua([[
    _G.b1 = vim.fn.bufadd(_G.root .. '/link.md'); vim.fn.bufload(_G.b1)
    _G.b2 = vim.fn.bufadd(_G.root .. '/notes/doc.md'); vim.fn.bufload(_G.b2)
  ]])
  local n = child.lua_get('_G.b1 == _G.b2 and 1 or 2')
  child.lua([[
    local em = require('earmark')
    em.annotate(_G.b1, { 0, 4 }, { 0, 9 }, { set = 'vivid', label = '1' })
    em.annotate(_G.b2, { 1, 2 }, { 1, 8 }, { set = 'vivid', label = '2' })
    require('earmark.buffer').save(_G.b1)
    require('earmark.buffer').save(_G.b2)
  ]])
  child.cmd('%bwipeout!')
  child.cmd('edit ' .. root() .. '/notes/doc.md')
  eq(n, 1) -- Neovim gives a file one buffer however it is reached (same inode)
  eq(quotes(), { 'quick', 'second' })
end

T['symlinks']['a symlinked project directory'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  child.cmd('bwipeout!')
  child.lua('vim.uv.fs_symlink(_G.root, _G.tmp .. "/alias")')
  child.cmd('edit ' .. child.lua_get('_G.tmp') .. '/alias/notes/doc.md')
  eq(quotes(), { 'quick' })
  mark({ 1, 2 }, { 1, 8 }, '2')
  save()
  eq(records(root() .. '/.earmark/docs'), { 'notes/doc.md.json' })
end

---------------------------------------------------------------------------
-- Outside a project, and roots that come and go
---------------------------------------------------------------------------

T['roots'] = MiniTest.new_set()

T['roots']['a file outside any project keeps its record under storage_dir'] = function()
  child.lua([[
    vim.fn.mkdir(_G.tmp .. '/loose', 'p')
    vim.fn.writefile({ 'The quick brown fox.' }, _G.tmp .. '/loose/a b.md')
  ]])
  child.cmd('edit ' .. vim.fn.fnameescape(child.lua_get('_G.tmp') .. '/loose/a b.md'))
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  local key = child.lua_get('(vim.uv.fs_realpath(_G.tmp) .. "/loose/a b.md"):gsub("^/", "")')
  eq(records(child.lua_get('_G.tmp') .. '/data/files'), { key .. '.json' })
  eq(child.lua_get('vim.fn.filereadable(...)', { child.lua_get('_G.tmp') .. '/data/snap/files/' .. key .. '.snap' }), 1)
  child.cmd('bwipeout!')
  child.cmd('edit ' .. vim.fn.fnameescape(child.lua_get('_G.tmp') .. '/loose/a b.md'))
  eq(quotes(), { 'quick' })
end

T['roots']['outside a project, a renamed file finds its record'] = function()
  child.lua([[
    vim.fn.mkdir(_G.tmp .. '/loose', 'p')
    vim.fn.writefile({ 'The quick brown fox.' }, _G.tmp .. '/loose/a.md')
  ]])
  child.cmd('edit ' .. child.lua_get('_G.tmp') .. '/loose/a.md')
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  child.cmd('bwipeout!')
  child.lua('vim.uv.fs_rename(_G.tmp .. "/loose/a.md", _G.tmp .. "/loose/b.md")')
  child.cmd('edit ' .. child.lua_get('_G.tmp') .. '/loose/b.md')
  eq(quotes(), { 'quick' })
end

T['roots']['a root marker appearing above an annotated file keeps its annotations'] = function()
  child.lua([[
    vim.fn.mkdir(_G.tmp .. '/later/sub', 'p')
    vim.fn.writefile({ 'The quick brown fox.' }, _G.tmp .. '/later/sub/a.md')
  ]])
  child.cmd('edit ' .. child.lua_get('_G.tmp') .. '/later/sub/a.md')
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  child.cmd('bwipeout!')
  child.lua('vim.fn.mkdir(_G.tmp .. "/later/.git", "p")') -- git init
  child.cmd('edit ' .. child.lua_get('_G.tmp') .. '/later/sub/a.md')
  eq(quotes(), { 'quick' })
  save()
  eq(records(child.lua_get('_G.tmp') .. '/later/.earmark/docs'), { 'sub/a.md.json' })
  eq(records(child.lua_get('_G.tmp') .. '/data/files'), {})
end

T['roots']['a .zk below the project root does not move records (.earmark wins)'] = function()
  h.open(nil, 'sub/doc.md')
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  child.cmd('bwipeout!')
  child.lua('vim.fn.mkdir(_G.root .. "/sub/.zk", "p")') -- zk init in a subdirectory
  h.open(nil, 'sub/doc.md')
  eq(quotes(), { 'quick' })
  eq(records(root() .. '/.earmark/docs'), { 'sub/doc.md.json' })
end

T['roots']['a nested .earmark appearing keeps annotations'] = function()
  h.open(nil, 'sub/doc.md')
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  child.cmd('bwipeout!')
  child.lua('vim.fn.mkdir(_G.root .. "/sub/.earmark/sets", "p")') -- e.g. a label set for sub/
  h.open(nil, 'sub/doc.md')
  eq(quotes(), { 'quick' })
  save()
  eq(records(root() .. '/sub/.earmark/docs'), { 'doc.md.json' })
  eq(records(root() .. '/.earmark/docs'), {})
end

T['roots']['a root marker disappearing keeps annotations'] = function()
  child.lua([[
    require('earmark.config').options.root_markers = { '.git' }
    vim.fn.mkdir(_G.tmp .. '/gone/.git', 'p')
    vim.fn.writefile({ 'The quick brown fox.' }, _G.tmp .. '/gone/a.md')
  ]])
  child.cmd('edit ' .. child.lua_get('_G.tmp') .. '/gone/a.md')
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  child.cmd('bwipeout!')
  child.lua('vim.fn.delete(_G.tmp .. "/gone/.git", "rf")')
  child.cmd('edit ' .. child.lua_get('_G.tmp') .. '/gone/a.md')
  eq(quotes(), { 'quick' })
end

T['roots']['the root changing while the buffer is open: saving still works'] = function()
  child.lua([[
    vim.fn.mkdir(_G.tmp .. '/live', 'p')
    vim.fn.writefile({ 'The quick brown fox.' }, _G.tmp .. '/live/a.md')
  ]])
  child.cmd('edit ' .. child.lua_get('_G.tmp') .. '/live/a.md')
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  child.lua('vim.fn.mkdir(_G.tmp .. "/live/.git", "p")')
  mark({ 0, 10 }, { 0, 15 }, '2')
  child.cmd('write')
  child.cmd('bwipeout!')
  child.cmd('edit ' .. child.lua_get('_G.tmp') .. '/live/a.md')
  eq(quotes(), { 'quick', 'brown' })
end

T['roots']['a file inside .earmark is never annotated'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  child.cmd('edit ' .. root() .. '/.earmark/docs/notes/doc.md.json')
  eq(child.lua_get('require("earmark.buffer").get(0) == nil'), true)
  eq(child.lua_get('require("earmark").annotate(0, {1, 0}, {1, 4}, { set = "vivid", label = "1" }) == nil'), true)
end

return T
