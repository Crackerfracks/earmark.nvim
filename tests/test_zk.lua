-- zk notes. zk itself is replaced through `zk._run`, by a shell stub on PATH, or (when it is
-- installed) run for real in a temp notebook.
local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child)

-- A notebook at the project root and a fake `zk new` that writes stdin to <dir>/<name>.md.
local function fake()
  child.lua([[
    _G.runs, _G.msgs, _G.selects = {}, {}, {}
    _G.R = vim.uv.fs_realpath(_G.root)
    vim.fn.mkdir(_G.root .. '/.zk', 'p')
    require('earmark.config').options.zk.open = false
    vim.notify = function(m) table.insert(_G.msgs, m) end
    require('earmark.zk')._run = function(argv, opts, cb)
      table.insert(_G.runs, { argv = argv, cwd = opts.cwd, stdin = opts.stdin })
      if argv[5] == 'list' then return cb({ code = 0, stdout = _G.list_json or '[]', stderr = '' }) end
      local path = opts.cwd .. '/' .. argv[6] .. '/' .. (_G.next_name or 'note') .. '.md'
      vim.fn.mkdir(vim.fs.dirname(path), 'p')
      vim.fn.writefile(vim.split(opts.stdin, '\n'), path)
      cb({ code = 0, stdout = path .. '\n', stderr = '' })
    end
    -- vim.ui.select answers with _G.answer(items) (default: the first item)
    vim.ui.select = function(items, opts, on_choice)
      local texts = vim.tbl_map(opts.format_item or tostring, items)
      table.insert(_G.selects, { prompt = opts.prompt, texts = texts })
      on_choice(_G.answer and _G.answer(items) or items[1])
    end
    _G.anno = function(s, e, note, label)
      local em = require('earmark')
      local a = em.annotate(0, s, e, { set = 'vivid', label = label or '3' })
      if note then em.set_note(0, a.id, note) end
      return a.id
    end
    _G.zk_of = function(id) return require('earmark').get(0, id).zk end
  ]])
end

local function run(i)
  return child.lua_get('_G.runs[' .. (i or 1) .. ']')
end

T['promote: zk new with the frontmatter, body and a notebook-relative a.zk'] = function()
  h.open()
  fake()
  child.lua([[
    _G.id = _G.anno({ 0, 4 }, { 0, 9 }, 'Why so fast?\nmore #speed')
    require('earmark').set_tags(0, _G.id, { 'x' })
  ]])
  h.cursor(1, 5)
  child.type_keys(' mz')
  local r = run()
  local R = child.lua_get('_G.R')
  local template = table.remove(r.argv)
  eq(template:match('/templates/earmark%.md$') ~= nil, true)
  eq(vim.fn.readfile(template), { '{{{content}}}' })
  eq(r.argv, { 'zk', '--notebook-dir', R, '--no-input', 'new', '.', '-i', '-p', '--title', 'Why so fast?', '--template' })
  eq(r.cwd, R)
  local id = child.lua_get('_G.id')
  eq(r.stdin, table.concat({
    '---',
    'title: "Why so fast?"',
    'tags: ["vivid-3", "x", "speed"]',
    'earmark:',
    '  id: "' .. id .. '"',
    '  set: "vivid"',
    '  key: "3"',
    '  label: "3"',
    '  source: "notes/doc.md"',
    '  line: 1',
    '---',
    '',
    '> quick',
    '',
    'Why so fast?',
    'more #speed',
    '',
    '[source](notes/doc.md#L1)',
    '',
  }, '\n'))
  eq(child.lua_get('_G.zk_of(_G.id)'), 'note.md')
  eq(child.lua_get('require("earmark").get(0, _G.id).note'), 'Why so fast?\nmore #speed') -- keeps its note
  eq(child.lua_get('require("earmark").zk.path(require("earmark").get(0, _G.id))'), R .. '/note.md')
  eq(child.lua_get('require("earmark").zk.notebook(0)'), R)
  -- saved relative to the notebook too
  child.lua('require("earmark.buffer").save(0)')
  local rec = child.lua_get('vim.json.decode(table.concat(vim.fn.readfile(_G.root .. "/.earmark/docs/notes/doc.md.json"), "\\n"))')
  eq(rec.annotations[1].zk, 'note.md')
  -- the hover names the note
  child.type_keys(' mi')
  local first = child.lua_get('vim.api.nvim_buf_get_lines(require("earmark.ui.hover").shown.buf, 0, 1, false)[1]')
  eq(first:find('↗ zk note', 1, true) ~= nil, true)
end

T['zk.dir as a function: folder per label, title from the quote, link from the note dir'] = function()
  h.open()
  fake()
  child.lua([[
    local zk = require('earmark.config').options.zk
    zk.dir = function(ctx) return 'people/' .. ctx.label:lower() end
    require('earmark').rename_label(0, { set = 'vivid', label = '3' }, 'NPC')
    _G.id = _G.anno({ 0, 0 }, { 0, 44 })
    require('earmark').zk.promote(0, _G.id)
  ]])
  local r = run()
  eq(r.argv[6], 'people/npc')
  eq(r.argv[10], 'The quick brown fox jumps over the lazy dog.')
  eq(r.stdin:find('tags: ["npc"]', 1, true) ~= nil, true)
  eq(r.stdin:find('  label: "NPC"', 1, true) ~= nil, true)
  eq(r.stdin:find('[source](../../notes/doc.md#L1)', 1, true) ~= nil, true)
  eq(child.lua_get('_G.zk_of(_G.id)'), 'people/npc/note.md')
end

T['a long quote is cut to 60 characters for the title'] = function()
  h.open({ string.rep('word ', 30) })
  fake()
  child.lua('require("earmark").zk.promote(0, _G.anno({ 0, 0 }, { 0, 149 }))')
  eq(child.lua_get('vim.fn.strchars(_G.runs[1].argv[10])'), 59) -- 60, trailing space trimmed
end

T['a detached annotation links to the file without a line'] = function()
  h.open()
  fake()
  child.lua([[
    _G.id = _G.anno({ 0, 4 }, { 0, 9 })
    vim.api.nvim_buf_set_lines(0, 0, 1, false, {})
    require('earmark.buffer').on_change(vim.api.nvim_get_current_buf())
    require('earmark').zk.promote(0, _G.id)
  ]])
  eq(child.lua_get('require("earmark").get(0, _G.id).status'), 'detached')
  local r = run()
  eq(r.stdin:find('[source](notes/doc.md)', 1, true) ~= nil, true)
  eq(r.stdin:find('line:', 1, true), nil)
  eq(r.stdin:find('line=', 1, true), nil)
end

T['a source outside the notebook gets an absolute link'] = function()
  h.open()
  fake()
  child.lua([[
    vim.fn.mkdir(_G.tmp .. '/nb/.zk', 'p')
    _G.NB = vim.uv.fs_realpath(_G.tmp .. '/nb')
    require('earmark.config').options.zk.notebook = _G.tmp .. '/nb'
    _G.id = _G.anno({ 0, 4 }, { 0, 9 })
    require('earmark').zk.promote(0, _G.id)
  ]])
  local r = run()
  local NB, R = child.lua_get('_G.NB'), child.lua_get('_G.R')
  eq(r.argv[3], NB)
  eq(r.stdin:find('[source](' .. R .. '/notes/doc.md#L1)', 1, true) ~= nil, true)
  eq(r.stdin:find('  source: "' .. R .. '/notes/doc.md"', 1, true) ~= nil, true)
  eq(child.lua_get('_G.zk_of(_G.id)'), 'note.md')
  eq(child.lua_get('require("earmark").zk.path(require("earmark").get(0, _G.id))'), NB .. '/note.md')
end

T['your own template gets the body and --extra'] = function()
  h.open()
  fake()
  child.lua([[
    require('earmark.config').options.zk.template = 'mine.md'
    _G.id = _G.anno({ 0, 4 }, { 0, 9 }, 'A note')
    require('earmark').zk.promote(0, _G.id)
  ]])
  local r = run()
  local id = child.lua_get('_G.id')
  eq(vim.list_slice(r.argv, 11), { '--template', 'mine.md', '--extra', 'id=' .. id .. ',set=vivid,key=3,line=1' })
  eq(r.stdin, '> quick\n\nA note\n\n[source](notes/doc.md#L1)\n')
end

T['without a notebook: one message naming zk init'] = function()
  h.open()
  fake()
  child.lua([[
    vim.fn.delete(_G.root .. '/.zk', 'rf')
    vim.env.ZK_NOTEBOOK_DIR = nil
    _G.anno({ 0, 4 }, { 0, 9 })
  ]])
  h.cursor(1, 5)
  child.type_keys(' mz')
  eq(child.lua_get('#_G.runs'), 0)
  local msgs = child.lua_get('_G.msgs')
  eq(#msgs, 1)
  eq(msgs[1]:find('zk init', 1, true) ~= nil, true)
end

T['<leader>mz again opens the note instead of making another'] = function()
  h.open()
  fake()
  child.lua('_G.id = _G.anno({ 0, 4 }, { 0, 9 })')
  h.cursor(1, 5)
  child.type_keys(' mz')
  eq(#child.api.nvim_list_wins(), 1) -- zk.open = false
  child.type_keys(' mz')
  eq(child.lua_get('#_G.runs'), 1)
  eq(#child.api.nvim_list_wins(), 2)
  eq(child.lua_get('vim.fs.basename(vim.api.nvim_buf_get_name(0))'), 'note.md')
  -- from the source again: the window already showing it
  child.cmd('wincmd p')
  child.type_keys(' mz')
  eq(#child.api.nvim_list_wins(), 2)
  eq(child.lua_get('vim.fs.basename(vim.api.nvim_buf_get_name(0))'), 'note.md')
  eq(child.lua_get('#_G.runs'), 1)
end

T[':Earmark zk new makes a new note anyway'] = function()
  h.open()
  fake()
  child.lua('_G.id = _G.anno({ 0, 4 }, { 0, 9 })')
  h.cursor(1, 5)
  child.cmd('Earmark zk')
  child.lua('_G.next_name = "second"')
  child.cmd('Earmark zk new')
  eq(child.lua_get('#_G.runs'), 2)
  eq(child.lua_get('_G.zk_of(_G.id)'), 'second.md')
end

T['a note that is gone: recreate or unlink'] = function()
  h.open()
  fake()
  child.lua('_G.id = _G.anno({ 0, 4 }, { 0, 9 })')
  h.cursor(1, 5)
  child.type_keys(' mz')
  child.lua('vim.fn.delete(_G.R .. "/note.md")')
  child.lua('_G.answer = function(items) return items[2] end') -- unlink
  child.type_keys(' mz')
  local sel = child.lua_get('_G.selects[1]')
  eq(sel.prompt, 'The zk note note.md is gone')
  eq(sel.texts, { 'Make a new note', 'Unlink it from the annotation' })
  eq(child.lua_get('_G.zk_of(_G.id)'), vim.NIL)
  eq(child.lua_get('#_G.runs'), 1)
  -- recreate
  child.type_keys(' mz')
  child.lua('vim.fn.delete(_G.R .. "/note.md")')
  child.lua('_G.answer = nil; _G.next_name = "again"')
  child.type_keys(' mz')
  eq(child.lua_get('#_G.runs'), 3)
  eq(child.lua_get('_G.zk_of(_G.id)'), 'again.md')
end

T['offers to link the other annotations with the same quote and label'] = function()
  h.open()
  fake()
  child.lua([[
    _G.a = _G.anno({ 0, 31 }, { 0, 34 }) -- "the"
    _G.b = _G.anno({ 2, 12 }, { 2, 15 }) -- "the" again
    _G.c = _G.anno({ 0, 0 }, { 0, 3 }, nil, '4') -- "The", another label
  ]])
  h.cursor(1, 32)
  child.type_keys(' mz')
  eq(child.lua_get('_G.selects[1].prompt'), 'Also link 1 other annotation with this quote and label?')
  eq(child.lua_get('{ _G.zk_of(_G.a), _G.zk_of(_G.b), _G.zk_of(_G.c) }'), { 'note.md', 'note.md' })
end

T[':Earmark zk link attaches a note picked from zk list'] = function()
  h.open()
  fake()
  child.lua([[
    _G.list_json = vim.json.encode({
      { path = 'lore/dragons.md', title = 'Dragons', absPath = _G.R .. '/lore/dragons.md' },
      { path = 'lore/elves.md', title = 'Elves', absPath = _G.R .. '/lore/elves.md' },
    })
    _G.answer = function(items) return items[2] end
    _G.id = _G.anno({ 0, 4 }, { 0, 9 })
  ]])
  h.cursor(1, 5)
  child.cmd('Earmark zk link')
  eq(run().argv, { 'zk', '--notebook-dir', child.lua_get('_G.R'), '--no-input', 'list', '--format', 'json', '-q', '-P' })
  eq(child.lua_get('_G.selects[1].texts'), { 'Dragons  lore/dragons.md', 'Elves  lore/elves.md' })
  eq(child.lua_get('_G.zk_of(_G.id)'), 'lore/elves.md')
end

T['has:zk and :Earmark zk pick'] = function()
  h.open()
  fake()
  child.lua([[
    _G.id = _G.anno({ 0, 4 }, { 0, 9 })
    _G.anno({ 1, 2 }, { 1, 8 })
    require('earmark').zk.promote(0, _G.id)
    local p = require('earmark.ui.picker')
    _G.n = #p.filter(p.doc_items(0), 'has:zk')
  ]])
  eq(child.lua_get('_G.n'), 1)
  child.cmd('Earmark zk pick')
  eq(#child.lua_get('_G.selects[1].texts'), 1)
  eq(child.lua_get('vim.fs.basename(vim.api.nvim_buf_get_name(0))'), 'note.md')
end

T['in a note, <leader>mz lists the annotations linked to it'] = function()
  h.open()
  fake()
  child.lua([[
    _G.id = _G.anno({ 1, 2 }, { 1, 8 })
    _G.anno({ 0, 4 }, { 0, 9 })
    require('earmark').zk.promote(0, _G.id)
  ]])
  child.cmd('edit ' .. child.lua_get('_G.R') .. '/note.md')
  h.cursor(1, 0)
  child.type_keys(' mz')
  local sel = child.lua_get('_G.selects[1]')
  eq(#sel.texts, 1)
  eq(sel.texts[1]:find('"second"', 1, true) ~= nil, true)
  -- choosing one goes to it
  eq(child.lua_get('vim.fs.basename(vim.api.nvim_buf_get_name(0))'), 'doc.md')
  eq(child.api.nvim_win_get_cursor(0), { 2, 2 })
  -- the same from a command, and from a note no one links to
  child.cmd('edit ' .. child.lua_get('_G.R') .. '/note.md')
  child.cmd('Earmark zk sources')
  eq(#child.lua_get('_G.selects'), 2)
  child.lua('_G.open("other.md", { "nothing" })')
  child.cmd('Earmark zk sources')
  eq(child.lua_get('_G.msgs[#_G.msgs]'), 'earmark: no annotation links to this file')
end

T['sources are found from a note in a notebook outside the project'] = function()
  h.open()
  fake()
  child.lua([[
    vim.fn.mkdir(_G.tmp .. '/nb/.zk', 'p')
    require('earmark.config').options.zk.notebook = _G.tmp .. '/nb'
    _G.id = _G.anno({ 0, 4 }, { 0, 9 })
    require('earmark').zk.promote(0, _G.id)
    require('earmark.buffer').save(0)
    vim.cmd('%bwipeout!')
    vim.cmd('cd ' .. _G.tmp)
    vim.cmd('edit ' .. _G.tmp .. '/nb/note.md')
  ]])
  child.cmd('Earmark zk sources')
  eq(#child.lua_get('_G.selects[1].texts'), 1)
  eq(child.lua_get('vim.fs.basename(vim.api.nvim_buf_get_name(0))'), 'doc.md')
end

T['User EarmarkZk fires with the ids'] = function()
  h.open()
  fake()
  child.lua([[
    _G.seen = {}
    require('earmark').on('Zk', function(d) table.insert(_G.seen, { action = d.action, ids = d.ids }) end)
    _G.id = _G.anno({ 0, 4 }, { 0, 9 })
    require('earmark').zk.promote(0, _G.id, {}, function(err, path) _G.cb = { err = err, path = path } end)
  ]])
  eq(child.lua_get('_G.seen'), { { action = 'zk', ids = { child.lua_get('_G.id') } } })
  eq(child.lua_get('_G.cb'), { path = child.lua_get('_G.R') .. '/note.md' })
end

T['the export links the note'] = function()
  h.open()
  fake()
  child.lua([[
    _G.id = _G.anno({ 0, 4 }, { 0, 9 }, 'Why so fast?')
    require('earmark.config').options.zk.dir = 'my notes'
    require('earmark').zk.promote(0, _G.id)
  ]])
  -- zk won't make the folder itself
  eq(child.lua_get('vim.fn.isdirectory(_G.R .. "/my notes")'), 1)
  local lines = child.lua_get('require("earmark").export(0)')
  eq(vim.tbl_contains(lines, '  → [Why so fast?](<my notes/note.md>)'), true)
  -- written to a file: the link is relative to that file's folder
  lines = child.lua_get('require("earmark.export").markdown(0, { dest = _G.R .. "/out/x.md" })')
  eq(vim.tbl_contains(lines, '  → [Why so fast?](<../my notes/note.md>)'), true)
end

T[':Earmark zk completes its subcommands'] = function()
  eq(child.lua_get('vim.fn.getcompletion("Earmark zk ", "cmdline")'), { 'new', 'link', 'pick', 'sources' })
  eq(child.lua_get('vim.fn.getcompletion("Earmark zk s", "cmdline")'), { 'sources' })
end

T['zk missing: one message, no Lua error'] = function()
  h.open()
  child.lua([[
    _G.msgs = {}
    vim.notify = function(m) table.insert(_G.msgs, m) end
    vim.fn.mkdir(_G.root .. '/.zk', 'p')
    vim.fn.mkdir(_G.tmp .. '/empty', 'p')
    vim.env.PATH = _G.tmp .. '/empty'
    require('earmark').annotate(0, { 0, 4 }, { 0, 9 }, { set = 'vivid', label = '3' })
  ]])
  h.cursor(1, 5)
  child.type_keys(' mz')
  h.settle()
  eq(child.lua_get('_G.msgs'), { 'earmark: zk not found (Arch: sudo pacman -S zk)' })
  eq(child.v.errmsg, '')
end

T['a stub zk on PATH: promote runs it through vim.system'] = function()
  h.open()
  child.lua([[
    vim.fn.mkdir(_G.root .. '/.zk', 'p')
    require('earmark.config').options.zk.open = false
    local bin = _G.tmp .. '/bin'
    vim.fn.mkdir(bin, 'p')
    vim.fn.writefile({
      '#!/bin/sh',
      'printf "%s\\n" "$@" > "' .. _G.tmp .. '/argv"',
      'mkdir -p "$2/$5"',
      'cat > "$2/$5/stub.md"',
      'echo "$2/$5/stub.md"',
    }, bin .. '/zk')
    vim.fn.setfperm(bin .. '/zk', 'rwxr-xr-x')
    vim.env.PATH = bin .. ':' .. vim.env.PATH
    _G.id = require('earmark').annotate(0, { 0, 4 }, { 0, 9 }, { set = 'vivid', label = '3' }).id
  ]])
  h.cursor(1, 5)
  child.type_keys(' mz')
  child.lua('vim.wait(3000, function() return require("earmark").get(0, _G.id).zk ~= nil end, 20)')
  eq(child.lua_get('require("earmark").get(0, _G.id).zk'), 'stub.md')
  local argv = child.lua_get('vim.fn.readfile(_G.tmp .. "/argv")')
  eq(vim.list_slice(argv, 3, 10), { '--no-input', 'new', '.', '-i', '-p', '--title', 'quick', '--template' })
  local note = child.lua_get('vim.fn.readfile(vim.uv.fs_realpath(_G.root) .. "/stub.md")')
  eq(note[1], '---')
  eq(note[#note], '[source](notes/doc.md#L1)')
end

T['with zk installed: a real notebook'] = function()
  if vim.fn.executable('zk') == 0 then MiniTest.skip('zk is not installed') end
  h.open()
  child.lua([[
    vim.fn.mkdir(_G.root .. '/.zk', 'p')
    vim.fn.writefile({ '[note]', 'filename = "{{slug title}}"' }, _G.root .. '/.zk/config.toml')
    _G.R = vim.uv.fs_realpath(_G.root)
    require('earmark.config').options.zk.open = false
    local em = require('earmark')
    _G.id = em.annotate(0, { 0, 4 }, { 0, 9 }, { set = 'vivid', label = '3' }).id
    em.rename_label(0, { set = 'vivid', label = '3' }, 'NPC')
    em.set_note(0, _G.id, 'Swift Fox\n#beast')
    em.zk.promote(0, _G.id, {}, function(err, path) _G.done = { err = err, path = path } end)
    vim.wait(10000, function() return _G.done ~= nil end, 50)
  ]])
  local done = child.lua_get('_G.done')
  eq(done.err, nil)
  local R = child.lua_get('_G.R')
  eq(done.path, R .. '/swift-fox.md')
  local note = vim.fn.readfile(done.path)
  eq(vim.list_slice(note, 1, 3), { '---', 'title: "Swift Fox"', 'tags: ["npc", "beast"]' })
  eq(vim.tbl_contains(note, '[source](notes/doc.md#L1)'), true)
  local function zk(args)
    local out = vim.system(vim.list_extend({ 'zk', '--notebook-dir', R, '--no-input' }, args), { cwd = R, text = true }):wait()
    return out.stdout or ''
  end
  eq(zk({ 'list', '--link-to', 'notes/doc.md', '--format', '{{path}}', '-q', '-P' }):find('swift-fox.md', 1, true) ~= nil, true)
  local tag_list = zk({ 'tag', 'list', '-q', '-P' })
  eq(tag_list:find('npc', 1, true) ~= nil, true)
  eq(tag_list:find('beast', 1, true) ~= nil, true)
  -- a second promote makes no new file
  local before = #vim.fn.globpath(R, '*.md', false, true)
  child.lua([[
    _G.done = nil
    require('earmark').zk.promote(0, _G.id, {}, function(err, path) _G.done = { err = err, path = path } end)
    vim.wait(10000, function() return _G.done ~= nil end, 50)
  ]])
  eq(child.lua_get('_G.done.path'), done.path)
  eq(#vim.fn.globpath(R, '*.md', false, true), before)
end

return T
