-- Edge cases of the zk integration: a zk that is missing, broken, slow or chatty; where
-- the notebook is; hostile titles and text; zk.dir; notes that move or vanish; the event.
-- Most cases replace `zk._run`; the "real zk" cases run zk 0.15 in a temp notebook and read
-- the notes back with `zk list --format json`.
local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child)

local function has(s, sub)
  return type(s) == 'string' and s:find(sub, 1, true) ~= nil
end

-- A notebook at the project root and a fake `zk new` that writes stdin to <dir>/<name>.md.
-- _G.respond(argv, opts, cb) replaces the fake when set.
local function fake()
  child.lua([[
    _G.runs, _G.msgs, _G.selects, _G.events = {}, {}, {}, {}
    _G.R = vim.uv.fs_realpath(_G.root)
    vim.fn.mkdir(_G.root .. '/.zk', 'p')
    require('earmark.config').options.zk.open = false
    vim.notify = function(m, l) table.insert(_G.msgs, m) end
    require('earmark').on('Zk', function(d) table.insert(_G.events, { buf = d.buf, action = d.action, ids = d.ids }) end)
    require('earmark.zk')._run = function(argv, opts, cb)
      table.insert(_G.runs, { argv = argv, cwd = opts.cwd, stdin = opts.stdin })
      if _G.respond then return _G.respond(argv, opts, cb) end
      if argv[5] == 'list' then return cb({ code = 0, stdout = _G.list_json or '[]', stderr = '' }) end
      local path = opts.cwd .. '/' .. argv[6] .. '/' .. (_G.next_name or 'note') .. '.md'
      vim.fn.mkdir(vim.fs.dirname(path), 'p')
      vim.fn.writefile(vim.split(opts.stdin, '\n'), path)
      cb({ code = 0, stdout = path .. '\n', stderr = '' })
    end
    vim.ui.select = function(items, opts, on_choice)
      local texts = vim.tbl_map(opts.format_item or tostring, items)
      table.insert(_G.selects, { prompt = opts.prompt, texts = texts })
      if _G.cancel then return on_choice(nil) end
      on_choice(_G.answer and _G.answer(items) or items[1])
    end
    _G.anno = function(s, e, note, label)
      local em = require('earmark')
      local a = em.annotate(0, s, e, { set = 'vivid', label = label or '3' })
      if note then em.set_note(0, a.id, note) end
      return a.id
    end
    _G.zk_of = function(id) return require('earmark').get(0, id).zk end
    _G.promote = function(id, opts)
      _G.done = nil
      require('earmark').zk.promote(0, id, opts or {}, function(err, path) _G.done = { err = err, path = path } end)
      return _G.done
    end
  ]])
end

-- A shell script used as zk (through zk.cmd and the real `_run`).
local function script(lines)
  child.lua([[
    _G.msgs = _G.msgs or {}
    vim.notify = function(m) table.insert(_G.msgs, m) end
    vim.fn.mkdir(_G.root .. '/.zk', 'p')
    _G.R = vim.uv.fs_realpath(_G.root)
    require('earmark.config').options.zk.open = false
    local bin = _G.tmp .. '/bin'
    vim.fn.mkdir(bin, 'p')
    vim.fn.writefile(..., bin .. '/zk')
    vim.fn.setfperm(bin .. '/zk', 'rwxr-xr-x')
    require('earmark.config').options.zk.cmd = bin .. '/zk'
    _G.id = require('earmark').annotate(0, { 0, 4 }, { 0, 9 }, { set = 'vivid', label = '3' }).id
    _G.done = nil
    _G.go = function()
      require('earmark').zk.promote(0, _G.id, {}, function(err, path) _G.done = { err = err, path = path } end)
    end
    _G.wait = function() vim.wait(5000, function() return _G.done ~= nil end, 10) return _G.done end
  ]], { lines })
end

-- The real zk, in a notebook at the project root.
local function real(config)
  if vim.fn.executable('zk') == 0 then MiniTest.skip('zk is not installed') end
  child.lua([[
    vim.fn.mkdir(_G.root .. '/.zk', 'p')
    vim.fn.writefile(..., _G.root .. '/.zk/config.toml')
    _G.R = vim.uv.fs_realpath(_G.root)
    _G.msgs = {}
    vim.notify = function(m) table.insert(_G.msgs, m) end
    require('earmark.config').options.zk.open = false
    _G.promote = function(id, opts)
      _G.done = nil
      require('earmark').zk.promote(0, id, opts or {}, function(err, path) _G.done = { err = err, path = path } end)
      vim.wait(10000, function() return _G.done ~= nil end, 20)
      return _G.done
    end
  ]], { config or { '[note]', 'filename = "{{id}}"' } })
end

-- `zk list` of the notebook: { [path] = note } read by zk itself.
local function zk_list()
  local R = child.lua_get('_G.R')
  local out = vim.system({ vim.fn.exepath('zk'), '--notebook-dir', R, '--no-input', 'list', '--format', 'json', '-q', '-P' },
    { cwd = R, text = true }):wait()
  local by = {}
  for _, n in ipairs(vim.json.decode(out.stdout ~= '' and out.stdout or '[]')) do
    by[n.path] = n
  end
  return by
end

---------------------------------------------------------------------------
-- A broken zk
---------------------------------------------------------------------------

T['zk.cmd that does not exist: one message, nothing linked, cb gets the error'] = function()
  h.open()
  script({ '#!/bin/sh' })
  child.lua('require("earmark.config").options.zk.cmd = _G.tmp .. "/nope/zk"; _G.go()')
  eq(child.lua_get('_G.wait().err'), 'zk not found (Arch: sudo pacman -S zk)')
  eq(child.lua_get('_G.msgs'), { 'earmark: zk not found (Arch: sudo pacman -S zk)' })
  eq(child.lua_get('require("earmark").get(0, _G.id).zk'), vim.NIL)
  eq(child.v.errmsg, '')
end

T['a zk file that is not executable reads as missing'] = function()
  h.open()
  script({ '#!/bin/sh', 'exit 0' })
  child.lua('vim.fn.setfperm(_G.tmp .. "/bin/zk", "rw-r--r--"); _G.go()')
  eq(has(child.lua_get('_G.wait().err'), 'zk not found'), true)
  eq(child.lua_get('require("earmark").get(0, _G.id).zk'), vim.NIL)
end

T['a zk whose interpreter is missing: an error message, no Lua error'] = function()
  h.open()
  script({ '#!/nonexistent/interpreter', 'exit 0' })
  child.lua('_G.go()')
  eq(child.lua_get('_G.wait().err') ~= vim.NIL, true)
  eq(child.lua_get('require("earmark").get(0, _G.id).zk'), vim.NIL)
  eq(has(child.lua_get('_G.msgs[#_G.msgs]'), 'zk could not create the note'), true)
  eq(child.v.errmsg, '')
end

T['zk exits non-zero: its stderr is shown, nothing is linked'] = function()
  h.open()
  script({ '#!/bin/sh', 'echo "zk: error: something broke" >&2', 'exit 3' })
  child.lua('_G.go()')
  eq(child.lua_get('_G.wait().err'), 'zk: error: something broke')
  eq(child.lua_get('_G.msgs'), { 'earmark: zk could not create the note: zk: error: something broke' })
  eq(child.lua_get('require("earmark").get(0, _G.id).zk'), vim.NIL)
end

T['zk exits non-zero without a word: the exit code is shown'] = function()
  h.open()
  script({ '#!/bin/sh', 'exit 7' })
  child.lua('_G.go(); _G.wait()')
  eq(child.lua_get('_G.msgs'), { 'earmark: zk could not create the note: exit code 7' })
end

T['zk prints garbage instead of a path: reported, the annotation is not linked to it'] = function()
  h.open()
  script({ '#!/bin/sh', 'cat > /dev/null', 'echo "Welcome to zk! Have a nice day."' })
  child.lua('_G.go()')
  eq(child.lua_get('_G.wait().err') ~= vim.NIL, true)
  eq(child.lua_get('require("earmark").get(0, _G.id).zk'), vim.NIL)
  eq(#child.lua_get('_G.msgs'), 1)
  eq(child.v.errmsg, '')
end

T['zk prints nothing: reported, nothing linked'] = function()
  h.open()
  script({ '#!/bin/sh', 'cat > /dev/null', 'exit 0' })
  child.lua('_G.go()')
  eq(child.lua_get('_G.wait().err'), 'no path')
  eq(child.lua_get('_G.msgs'), { 'earmark: zk did not say where it wrote the note' })
end

T['zk prints warnings before the path: the last line is the path'] = function()
  h.open()
  script({ '#!/bin/sh', 'echo "warning: config is old"', 'cat > "$2/w.md"', 'echo "$2/w.md"' })
  child.lua('_G.go()')
  eq(child.lua_get('_G.wait().err'), vim.NIL)
  eq(child.lua_get('require("earmark").get(0, _G.id).zk'), 'w.md')
end

T['a slow zk does not block, and a second press while it runs makes no second note'] = function()
  h.open()
  script({
    '#!/bin/sh',
    'echo run >> "$2/../runs"',
    'sleep 0.4',
    'cat > "$2/slow.md"',
    'echo "$2/slow.md"',
  })
  child.lua([[
    _G.t0 = vim.uv.hrtime()
    _G.go()
    _G.returned_ms = (vim.uv.hrtime() - _G.t0) / 1e6
    _G.second = nil
    require('earmark').zk.promote(0, _G.id, {}, function(err, path) _G.second = { err = err, path = path } end)
  ]])
  eq(child.lua_get('_G.returned_ms < 300'), true)
  eq(child.lua_get('require("earmark").get(0, _G.id).zk'), vim.NIL) -- still running
  child.lua('_G.wait(); vim.wait(800, function() return false end)')
  eq(child.lua_get('_G.done.err'), vim.NIL)
  eq(child.lua_get('require("earmark").get(0, _G.id).zk'), 'slow.md')
  eq(child.lua_get('#vim.fn.readfile(_G.tmp .. "/runs")'), 1)
  eq(child.lua_get('_G.second ~= nil'), true)
end

T['the buffer is wiped while zk runs: no error, cb says so'] = function()
  h.open()
  script({ '#!/bin/sh', 'sleep 0.3', 'cat > "$2/late.md"', 'echo "$2/late.md"' })
  child.lua([[
    _G.go()
    vim.cmd('enew')
    vim.cmd('bwipeout! ' .. vim.fn.bufnr('doc.md'))
  ]])
  eq(child.lua_get('_G.wait().err'), 'annotation gone')
  eq(child.v.errmsg, '')
end

T['the annotation is erased while zk runs: no error, not resurrected'] = function()
  h.open()
  script({ '#!/bin/sh', 'sleep 0.3', 'cat > "$2/late.md"', 'echo "$2/late.md"' })
  child.lua('_G.go(); require("earmark").erase(0, { _G.id })')
  eq(child.lua_get('_G.wait().err'), 'annotation gone')
  eq(child.lua_get('#require("earmark").list(0)'), 0)
end

T[':Earmark zk link: garbage from zk list gives an empty picker, no error'] = function()
  h.open()
  fake()
  child.lua([[
    _G.list_json = '[1, null, "x", {"path": null, "title": null}, {"title": 5, "path": "a.md"}]'
    _G.id = _G.anno({ 0, 4 }, { 0, 9 })
  ]])
  h.cursor(1, 5)
  child.cmd('Earmark zk link')
  eq(child.v.errmsg, '')
  local sel = child.lua_get('_G.selects[1]')
  eq(sel.texts, { 'a  a.md' })
  child.lua('_G.list_json = "not json at all"; _G.selects = {}')
  child.cmd('Earmark zk link')
  eq(child.v.errmsg, '')
  eq(child.lua_get('_G.msgs[#_G.msgs]'):find('no notes in', 1, true) ~= nil, true)
end

T[':Earmark zk link: zk list printing one object per line works too'] = function()
  h.open()
  fake()
  child.lua([[
    _G.list_json = vim.json.encode({ path = 'a.md', title = 'A' }) .. '\n' .. vim.json.encode({ path = 'b.md', title = 'B' })
    _G.answer = function(items) return items[2] end
    _G.id = _G.anno({ 0, 4 }, { 0, 9 })
  ]])
  h.cursor(1, 5)
  child.cmd('Earmark zk link')
  eq(child.lua_get('_G.selects[1].texts'), { 'A  a.md', 'B  b.md' })
  eq(child.lua_get('_G.zk_of(_G.id)'), 'b.md')
end

---------------------------------------------------------------------------
-- Which notebook
---------------------------------------------------------------------------

T['no notebook anywhere: notebook() says why, promote runs nothing'] = function()
  h.open()
  fake()
  child.lua([[
    vim.fn.delete(_G.root .. '/.zk', 'rf')
    vim.env.ZK_NOTEBOOK_DIR = nil
    _G.id = _G.anno({ 0, 4 }, { 0, 9 })
    _G.nb = { require('earmark.zk').notebook(0) }
    _G.promote(_G.id)
  ]])
  local nb = child.lua_get('_G.nb')
  eq(nb[1], vim.NIL)
  eq(has(nb[2], 'zk init'), true)
  eq(child.lua_get('#_G.runs'), 0)
  eq(has(child.lua_get('_G.done.err'), 'zk init'), true)
  eq(child.lua_get('require("earmark").zk.notebook()'), vim.NIL)
end

T['notebook from .zk above the file, from a deeper folder'] = function()
  h.open(nil, 'a/b/c/deep.md')
  fake()
  eq(child.lua_get('require("earmark").zk.notebook(0)'), child.lua_get('_G.R'))
  child.lua('_G.promote(_G.anno({ 0, 4 }, { 0, 9 }))')
  local r = child.lua_get('_G.runs[1]')
  eq(r.argv[3], child.lua_get('_G.R'))
  eq(has(r.stdin, '[source](a/b/c/deep.md#L1)'), true)
  eq(has(r.stdin, '  source: "a/b/c/deep.md"'), true)
end

T['the nearest .zk wins over one further up'] = function()
  h.open(nil, 'inner/doc.md')
  fake()
  child.lua('vim.fn.mkdir(_G.root .. "/inner/.zk", "p")')
  eq(child.lua_get('require("earmark").zk.notebook(0)'), child.lua_get('_G.R') .. '/inner')
end

T['zk.notebook beats .zk; ~ and a trailing slash are fine'] = function()
  h.open()
  fake()
  child.lua([[
    vim.fn.mkdir(_G.tmp .. '/nb2/.zk', 'p')
    vim.env.HOME = _G.tmp
    require('earmark.config').options.zk.notebook = '~/nb2/'
  ]])
  eq(child.lua_get('require("earmark").zk.notebook(0)'), child.lua_get('vim.uv.fs_realpath(_G.tmp .. "/nb2")'))
end

T['$ZK_NOTEBOOK_DIR is used when nothing else says; a file outside it links absolutely'] = function()
  h.open()
  fake()
  child.lua([[
    vim.fn.delete(_G.root .. '/.zk', 'rf')
    vim.fn.mkdir(_G.tmp .. '/envnb/.zk', 'p')
    vim.env.ZK_NOTEBOOK_DIR = _G.tmp .. '/envnb'
    _G.NB = vim.uv.fs_realpath(_G.tmp .. '/envnb')
    _G.id = _G.anno({ 0, 4 }, { 0, 9 })
    _G.promote(_G.id)
  ]])
  local NB, R = child.lua_get('_G.NB'), child.lua_get('_G.R')
  eq(child.lua_get('require("earmark").zk.notebook(0)'), NB)
  local r = child.lua_get('_G.runs[1]')
  eq(r.argv[3], NB)
  eq(r.cwd, NB)
  eq(has(r.stdin, '[source](' .. R .. '/notes/doc.md#L1)'), true)
  eq(child.lua_get('_G.zk_of(_G.id)'), 'note.md')
  eq(child.lua_get('require("earmark").zk.path(require("earmark").get(0, _G.id))'), NB .. '/note.md')
end

T['an empty $ZK_NOTEBOOK_DIR or zk.notebook counts as unset'] = function()
  h.open()
  fake()
  child.lua([[
    vim.fn.delete(_G.root .. '/.zk', 'rf')
    vim.env.ZK_NOTEBOOK_DIR = ''
    require('earmark.config').options.zk.notebook = ''
  ]])
  eq(child.lua_get('require("earmark").zk.notebook(0)'), vim.NIL)
end

T['a scratch buffer: notebook from zk.notebook, the note has no source link'] = function()
  fake()
  child.lua([[
    vim.fn.mkdir(_G.tmp .. '/nb/.zk', 'p')
    require('earmark.config').options.zk.notebook = _G.tmp .. '/nb'
    vim.cmd('enew')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'scratch text here' })
    _G.id = require('earmark').annotate(0, { 0, 0 }, { 0, 7 }, { set = 'vivid', label = '2' }).id
    _G.promote(_G.id)
  ]])
  local r = child.lua_get('_G.runs[1]')
  eq(has(r.stdin, '[source]'), false)
  eq(has(r.stdin, 'source:'), false)
  eq(has(r.stdin, '  line: 1'), true)
  eq(child.lua_get('_G.zk_of(_G.id)'), 'note.md')
  eq(child.lua_get('_G.done.err'), vim.NIL)
end

T['a source path with spaces and parentheses gets an <angle> link'] = function()
  h.open(nil, 'my notes/a (draft).md')
  fake()
  child.lua('_G.promote(_G.anno({ 0, 4 }, { 0, 9 }))')
  local r = child.lua_get('_G.runs[1]')
  eq(has(r.stdin, '[source](<my notes/a (draft).md#L1>)'), true)
  eq(has(r.stdin, '  source: "my notes/a (draft).md"'), true)
end

---------------------------------------------------------------------------
-- Titles and text
---------------------------------------------------------------------------

local function title_of(note)
  return child.lua_get('require("earmark.zk").title_for({ note = ..., quote = "the quote" })', { note })
end

T['titles: the first line of the note, without #tags, @mentions or a heading mark'] = function()
  eq(title_of('# Heading\nbody'), 'Heading')
  eq(title_of('## Two words #tag'), 'Two words')
  eq(title_of('#todo fix the bug'), 'fix the bug')
  eq(title_of('#todo #later'), 'the quote')
  eq(title_of('@mayor said so'), 'said so')
  eq(title_of('a: b "c" \'d\' \\e'), 'a: b "c" \'d\' \\e')
  eq(title_of('Café — naïve 日本語'), 'Café — naïve 日本語')
  eq(title_of('\n\nfirst real line\nsecond'), 'first real line')
  eq(title_of('   '), 'the quote')
  eq(title_of('C# and F# are languages'), 'C# and F# are languages')
  eq(title_of('issue#12 stays'), 'issue#12 stays')
end

T['titles from the quote: whitespace folded, cut at 60 characters, never empty'] = function()
  local function t(quote)
    return child.lua_get('require("earmark.zk").title_for({ quote = ... })', { quote })
  end
  eq(t('a\r\nb\tc'), 'a b c')
  eq(vim.fn.strchars(t(string.rep('é', 100))), 60)
  eq(t('   '), 'earmark')
  eq(t(nil), 'earmark')
end

T['frontmatter with YAML-hostile text is valid: JSON strings throughout'] = function()
  h.open({ '--- "quoted" \\back: #hash' })
  fake()
  child.lua([[
    _G.id = _G.anno({ 0, 0 }, { 0, 25 }, '"Q": it\'s a \\ test --- yes\n---\n# heading in body\n#tag')
    require('earmark').rename_label(0, { set = 'vivid', label = '3' }, 'NPC: "boss"')
    require('earmark').set_tags(0, _G.id, { 'two words', 'x"y' })
    _G.promote(_G.id)
  ]])
  local stdin = child.lua_get('_G.runs[1].stdin')
  local fm = vim.split(stdin, '\n')
  eq(fm[1], '---')
  eq(fm[2], [[title: "\"Q\": it's a \\ test --- yes"]])
  eq(fm[3], 'tags: ["npc-boss", "two words", "x\\"y", "tag"]')
  eq(fm[8], [[  label: "NPC: \"boss\""]])
  -- every value line decodes as JSON (a JSON string is a YAML string)
  local i = 2
  while fm[i] ~= '---' do
    local v = fm[i]:match('^%s*%w+: (.*)$')
    if v and v ~= '' then eq(pcall(vim.json.decode, v), true) end
    i = i + 1
  end
  -- the body keeps the text as written, quote lines prefixed
  eq(has(stdin, '\n> --- "quoted" \\back: #hash\n'), true)
  eq(has(stdin, '\n---\n# heading in body\n#tag\n'), true)
end

T['a multi-line quote becomes one > line per line'] = function()
  h.open()
  fake()
  child.lua('_G.promote(_G.anno({ 0, 40 }, { 2, 5 }))')
  local stdin = child.lua_get('_G.runs[1].stdin')
  eq(has(stdin, '\n> dog.\n> A second line with some words.\n> Third\n'), true)
  eq(has(stdin, '#L1)'), true)
end

T['the title read back for the export: JSON, YAML-ish, or none'] = function()
  child.lua([[
    local d = _G.tmp
    vim.fn.mkdir(d, 'p')
    vim.fn.writefile({ '---', 'title: "a \\"b\\" \\u00e9"', '---' }, d .. '/j.md')
    vim.fn.writefile({ '---', "title: 'single'", '---' }, d .. '/s.md')
    vim.fn.writefile({ '---', 'title: plain: words', '---' }, d .. '/p.md')
    vim.fn.writefile({ '---', 'tags: [x]', '---', 'title: not frontmatter' }, d .. '/n.md')
    vim.fn.writefile({ 'no frontmatter' }, d .. '/none.md')
    vim.fn.writefile({ '---', 'title:', '---' }, d .. '/empty.md')
  ]])
  local function t(name)
    return child.lua_get('require("earmark.zk").title(_G.tmp .. "/" .. ...)', { name })
  end
  eq(t('j.md'), 'a "b" é')
  eq(t('s.md'), 'single')
  eq(t('p.md'), 'plain: words')
  eq(t('n.md'), 'n')
  eq(t('none.md'), 'none')
  eq(t('empty.md'), 'empty')
  eq(t('missing.md'), 'missing')
end

---------------------------------------------------------------------------
-- zk.dir
---------------------------------------------------------------------------

local function dir_case(dir)
  h.open()
  fake()
  child.lua('require("earmark.config").options.zk.dir = ...', { dir })
  child.lua('_G.id = _G.anno({ 0, 4 }, { 0, 9 }); _G.promote(_G.id)')
end

T['zk.dir as a nested path: the folders are made, a.zk includes them'] = function()
  dir_case('lore/people/npcs')
  eq(child.lua_get('_G.runs[1].argv[6]'), 'lore/people/npcs')
  eq(child.lua_get('_G.zk_of(_G.id)'), 'lore/people/npcs/note.md')
  eq(has(child.lua_get('_G.runs[1].stdin'), '[source](../../../notes/doc.md#L1)'), true)
end

T['zk.dir with ./ and a trailing slash'] = function()
  dir_case('./inbox/')
  eq(child.lua_get('_G.runs[1].argv[6]'), 'inbox')
  eq(child.lua_get('_G.zk_of(_G.id)'), 'inbox/note.md')
end

T['zk.dir as an absolute path inside the notebook is made relative'] = function()
  h.open()
  fake()
  child.lua('require("earmark.config").options.zk.dir = _G.R .. "/abs"')
  child.lua('_G.id = _G.anno({ 0, 4 }, { 0, 9 }); _G.promote(_G.id)')
  eq(child.lua_get('_G.runs[1].argv[6]'), 'abs')
  eq(child.lua_get('_G.zk_of(_G.id)'), 'abs/note.md')
end

T['zk.dir leading out of the notebook: refused before zk runs, no folder made'] = function()
  dir_case('../outside')
  eq(child.lua_get('#_G.runs'), 0)
  eq(child.lua_get('vim.fn.isdirectory(_G.tmp .. "/outside")'), 0)
  eq(child.lua_get('_G.zk_of(_G.id)'), vim.NIL)
  eq(has(child.lua_get('_G.msgs[#_G.msgs]'), 'outside the notebook'), true)
  eq(child.lua_get('_G.done.err') ~= vim.NIL, true)
end

T['zk.dir as an absolute path outside the notebook: refused too'] = function()
  h.open()
  fake()
  child.lua('require("earmark.config").options.zk.dir = _G.tmp .. "/elsewhere"')
  child.lua('_G.id = _G.anno({ 0, 4 }, { 0, 9 }); _G.promote(_G.id)')
  eq(child.lua_get('#_G.runs'), 0)
  eq(child.lua_get('_G.zk_of(_G.id)'), vim.NIL)
  eq(has(child.lua_get('_G.msgs[#_G.msgs]'), 'outside the notebook'), true)
end

T['zk.dir a/../b stays inside: only b is made'] = function()
  dir_case('a/../b')
  eq(child.lua_get('_G.runs[1].argv[6]'), 'b')
  eq(child.lua_get('vim.fn.isdirectory(_G.R .. "/a")'), 0)
  eq(child.lua_get('_G.zk_of(_G.id)'), 'b/note.md')
end

T['zk.dir function returning nil, an empty string, or a number: the notebook root'] = function()
  h.open()
  fake()
  for i, ret in ipairs({ 'nil', '""', '5' }) do
    child.lua(('require("earmark.config").options.zk.dir = function() return %s end'):format(ret))
    child.lua(('_G.next_name = "n%d"; _G.promote(_G.anno({ %d, 0 }, { %d, 1 }))'):format(i, i - 1, i - 1))
    eq(child.lua_get(('_G.runs[%d].argv[6]'):format(i)), '.')
  end
  eq(child.v.errmsg, '')
end

T['zk.dir function gets the context: label, value, notebook, source'] = function()
  h.open()
  fake()
  child.lua([[
    require('earmark.config').options.zk.dir = function(ctx)
      _G.ctx = { label = ctx.label, set = ctx.value.set, key = ctx.value.label, notebook = ctx.notebook,
        source = ctx.source, id = ctx.annotation.id, buf = ctx.buf }
      return '../escape'
    end
    _G.id = _G.anno({ 0, 4 }, { 0, 9 })
    _G.promote(_G.id)
  ]])
  local ctx = child.lua_get('_G.ctx')
  eq(ctx.label, '3')
  eq(ctx.set, 'vivid')
  eq(ctx.key, '3')
  eq(ctx.notebook, child.lua_get('_G.R'))
  eq(ctx.source, child.lua_get('_G.R') .. '/notes/doc.md')
  eq(ctx.id, child.lua_get('_G.id'))
  eq(ctx.buf, child.api.nvim_get_current_buf())
  eq(child.lua_get('#_G.runs'), 0) -- '../escape' is refused
end

---------------------------------------------------------------------------
-- Notes that move or vanish; promoting again
---------------------------------------------------------------------------

T['the note is moved away: ask, unlink clears a.zk and fires EarmarkZk'] = function()
  h.open()
  fake()
  child.lua('_G.id = _G.anno({ 0, 4 }, { 0, 9 })')
  h.cursor(1, 5)
  child.type_keys(' mz')
  child.lua([[
    vim.fn.mkdir(_G.R .. '/moved', 'p')
    vim.uv.fs_rename(_G.R .. '/note.md', _G.R .. '/moved/note.md')
    _G.events = {}
    _G.answer = function(items) return items[2] end
  ]])
  child.type_keys(' mz')
  eq(child.lua_get('_G.selects[1].prompt'), 'The zk note note.md is gone')
  eq(child.lua_get('_G.zk_of(_G.id)'), vim.NIL)
  eq(child.lua_get('_G.events'), { { buf = child.api.nvim_get_current_buf(), action = 'zk', ids = { child.lua_get('_G.id') } } })
  eq(child.lua_get('#_G.runs'), 1)
end

T['the note is gone and the question is cancelled: nothing changes'] = function()
  h.open()
  fake()
  child.lua('_G.id = _G.anno({ 0, 4 }, { 0, 9 })')
  h.cursor(1, 5)
  child.type_keys(' mz')
  child.lua('vim.fn.delete(_G.R .. "/note.md"); _G.cancel = true')
  child.type_keys(' mz')
  eq(child.lua_get('_G.zk_of(_G.id)'), 'note.md')
  eq(child.lua_get('#_G.runs'), 1)
end

T['the notebook is gone (zk.path is nil): ask; recreate says there is no notebook; unlink works'] = function()
  h.open()
  fake()
  child.lua('_G.id = _G.anno({ 0, 4 }, { 0, 9 }); _G.promote(_G.id)')
  child.lua([[
    vim.fn.delete(_G.root .. '/.zk', 'rf')
    vim.env.ZK_NOTEBOOK_DIR = nil
  ]])
  eq(child.lua_get('require("earmark").zk.path(require("earmark").get(0, _G.id))'), vim.NIL)
  h.cursor(1, 5)
  child.type_keys(' mz') -- recreate (the first answer)
  eq(child.lua_get('#_G.runs'), 1)
  eq(has(child.lua_get('_G.msgs[#_G.msgs]'), 'zk init'), true)
  eq(child.lua_get('_G.zk_of(_G.id)'), 'note.md')
  child.lua('_G.answer = function(items) return items[2] end')
  child.type_keys(' mz')
  eq(child.lua_get('_G.zk_of(_G.id)'), vim.NIL)
  eq(child.v.errmsg, '')
end

T['promote through the API twice: the second returns the same note; force makes another'] = function()
  h.open()
  fake()
  child.lua('_G.id = _G.anno({ 0, 4 }, { 0, 9 })')
  local R = child.lua_get('_G.R')
  child.lua('_G.promote(_G.id)')
  eq(child.lua_get('_G.done'), { path = R .. '/note.md' })
  child.lua('_G.promote(_G.id)')
  eq(child.lua_get('_G.done'), { path = R .. '/note.md' })
  eq(child.lua_get('#_G.runs'), 1)
  eq(#child.api.nvim_list_wins(), 1) -- the API does not open it unless asked
  child.lua('_G.next_name = "forced"; _G.promote(_G.id, { force = true })')
  eq(child.lua_get('_G.done'), { path = R .. '/forced.md' })
  eq(child.lua_get('_G.zk_of(_G.id)'), 'forced.md')
  eq(child.lua_get('vim.fn.filereadable(_G.R .. "/note.md")'), 1) -- the old note stays
end

T['promote of an unknown id: cb gets the error, nothing runs'] = function()
  h.open()
  fake()
  child.lua('_G.promote("no-such-id")')
  eq(child.lua_get('_G.done.err'), 'no annotation no-such-id')
  eq(child.lua_get('#_G.runs'), 0)
end

T['promoting a detached annotation keeps the quote it had'] = function()
  h.open()
  fake()
  child.lua([[
    _G.id = _G.anno({ 1, 2 }, { 1, 8 }, 'Gone now')
    vim.api.nvim_buf_set_lines(0, 1, 2, false, {})
    require('earmark.buffer').on_change(vim.api.nvim_get_current_buf())
    _G.promote(_G.id)
  ]])
  eq(child.lua_get('require("earmark").get(0, _G.id).status'), 'detached')
  local stdin = child.lua_get('_G.runs[1].stdin')
  eq(has(stdin, '> second'), true)
  eq(has(stdin, 'title: "Gone now"'), true)
  eq(has(stdin, '[source](notes/doc.md)'), true)
  eq(child.lua_get('_G.zk_of(_G.id)'), 'note.md')
end

T['a note whose file name zk already used: not linked to someone else\'s note'] = function()
  h.open()
  fake()
  -- zk with a {{slug title}} file name prints the existing file and writes nothing
  child.lua([[
    vim.fn.writefile({ '---', 'title: "quick"', '---', 'an older note' }, _G.R .. '/quick.md')
    vim.uv.fs_utime(_G.R .. '/quick.md', os.time() - 3600, os.time() - 3600)
    _G.respond = function(argv, opts, cb) cb({ code = 0, stdout = _G.R .. '/quick.md\n', stderr = '' }) end
    _G.id = _G.anno({ 0, 4 }, { 0, 9 })
    _G.promote(_G.id)
  ]])
  eq(child.lua_get('_G.zk_of(_G.id)'), vim.NIL)
  eq(child.lua_get('_G.done.err') ~= vim.NIL, true)
  eq(has(child.lua_get('_G.msgs[#_G.msgs]'), 'quick.md'), true)
  eq(child.lua_get('vim.fn.readfile(_G.R .. "/quick.md")[4]'), 'an older note')
end

T['with your own template: an old note handed back is not linked either'] = function()
  h.open()
  fake()
  child.lua([[
    require('earmark.config').options.zk.template = 'mine.md'
    vim.fn.writefile({ 'an older note' }, _G.R .. '/quick.md')
    vim.uv.fs_utime(_G.R .. '/quick.md', os.time() - 3600, os.time() - 3600)
    _G.respond = function(argv, opts, cb) cb({ code = 0, stdout = _G.R .. '/quick.md\n', stderr = '' }) end
    _G.id = _G.anno({ 0, 4 }, { 0, 9 })
    _G.promote(_G.id)
  ]])
  eq(child.lua_get('_G.zk_of(_G.id)'), vim.NIL)
  eq(child.lua_get('_G.done.err'), 'file name taken')
end

T['same text, same label: offered; another label, another note, or "No" are left alone'] = function()
  h.open({ 'the cat and the dog and the bird and the end' })
  fake()
  child.lua([[
    _G.a = _G.anno({ 0, 0 }, { 0, 3 })          -- the
    _G.b = _G.anno({ 0, 12 }, { 0, 15 })        -- the
    _G.c = _G.anno({ 0, 24 }, { 0, 27 }, nil, '4') -- the, another label
    _G.d = _G.anno({ 0, 37 }, { 0, 40 })        -- the, already linked elsewhere
    require('earmark.buffer').annotation(0, _G.d).zk = 'other.md'
    _G.answer = function(items) return items[2] end -- "No"
  ]])
  h.cursor(1, 0)
  child.type_keys(' mz')
  eq(child.lua_get('_G.selects[1].prompt'), 'Also link 1 other annotation with this quote and label?')
  eq(child.lua_get('{ _G.zk_of(_G.a), _G.zk_of(_G.b) or "none", _G.zk_of(_G.c) or "none", _G.zk_of(_G.d) }'),
    { 'note.md', 'none', 'none', 'other.md' })
  -- through the API (no ask): never offered
  child.lua('_G.selects = {}; _G.answer = nil; _G.next_name = "b"; _G.promote(_G.b)')
  eq(child.lua_get('#_G.selects'), 0)
end

T['same text, same label: "Yes" links them all and fires EarmarkZk with their ids'] = function()
  h.open({ 'x x x' })
  fake()
  child.lua([[
    _G.a = _G.anno({ 0, 0 }, { 0, 1 })
    _G.b = _G.anno({ 0, 2 }, { 0, 3 })
    _G.c = _G.anno({ 0, 4 }, { 0, 5 })
  ]])
  h.cursor(1, 2)
  child.type_keys(' mz')
  eq(child.lua_get('_G.selects[1].prompt'), 'Also link 2 other annotations with this quote and label?')
  eq(child.lua_get('{ _G.zk_of(_G.a), _G.zk_of(_G.b), _G.zk_of(_G.c) }'), { 'note.md', 'note.md', 'note.md' })
  local ev = child.lua_get('_G.events')
  eq(#ev, 2)
  eq(ev[1].ids, { child.lua_get('_G.b') })
  local rest = ev[2].ids
  table.sort(rest)
  local want = child.lua_get('{ _G.a, _G.c }')
  table.sort(want)
  eq(rest, want)
end

T['EarmarkZk payload: buf, action and ids, also through a User autocmd'] = function()
  h.open()
  fake()
  child.lua([[
    _G.au = {}
    vim.api.nvim_create_autocmd('User', { pattern = 'EarmarkZk', callback = function(ev)
      table.insert(_G.au, { buf = ev.data.buf, action = ev.data.action, ids = ev.data.ids }) end })
    _G.changed = {}
    vim.api.nvim_create_autocmd('User', { pattern = 'EarmarkChanged', callback = function(ev)
      table.insert(_G.changed, ev.data.action) end })
    _G.id = _G.anno({ 0, 4 }, { 0, 9 })
    _G.changed = {}
    _G.promote(_G.id)
  ]])
  local buf = child.api.nvim_get_current_buf()
  eq(child.lua_get('_G.au'), { { buf = buf, action = 'zk', ids = { child.lua_get('_G.id') } } })
  eq(child.lua_get('_G.changed'), { 'zk' })
  -- a handler that errors does not break promoting
  child.lua([[
    vim.api.nvim_create_autocmd('User', { pattern = 'EarmarkZk', callback = function() error('boom') end })
    _G.next_name = 'two'
    _G.promote(_G.id, { force = true })
  ]])
  eq(child.lua_get('_G.zk_of(_G.id)'), 'two.md')
end

T['a.zk is saved and survives a restart of the buffer'] = function()
  h.open()
  fake()
  child.lua([[
    _G.id = _G.anno({ 0, 4 }, { 0, 9 })
    _G.promote(_G.id)
    require('earmark.buffer').save(0)
    vim.cmd('bwipeout!')
    _G.open('notes/doc.md')
  ]])
  eq(child.lua_get('_G.zk_of(_G.id)'), 'note.md')
end

T['the project with its notebook moved elsewhere: the note is found at the new place'] = function()
  h.open()
  fake()
  child.lua([[
    _G.id = _G.anno({ 0, 4 }, { 0, 9 })
    _G.promote(_G.id)
    require('earmark.buffer').save(0)
    vim.cmd('%bwipeout!')
    vim.fn.system({ 'cp', '-r', _G.root, _G.tmp .. '/moved' })
    vim.fn.delete(_G.root, 'rf')
    vim.cmd('edit ' .. _G.tmp .. '/moved/notes/doc.md')
    _G.M = vim.uv.fs_realpath(_G.tmp .. '/moved')
  ]])
  local M = child.lua_get('_G.M')
  eq(child.lua_get('_G.zk_of(_G.id)'), 'note.md')
  eq(child.lua_get('require("earmark").zk.path(require("earmark").get(0, _G.id))'), M .. '/note.md')
  h.cursor(1, 5)
  child.type_keys(' mz') -- opens the note there, makes none
  eq(child.lua_get('#_G.runs'), 1)
  eq(child.lua_get('vim.api.nvim_buf_get_name(0)'), M .. '/note.md')
end

---------------------------------------------------------------------------
-- From inside a note
---------------------------------------------------------------------------

T['in a note: an annotation under the cursor is promoted, elsewhere the sources are listed'] = function()
  h.open()
  fake()
  child.lua([[
    _G.src = _G.anno({ 0, 4 }, { 0, 9 })
    _G.promote(_G.src)
    vim.cmd('edit ' .. _G.R .. '/note.md')
    for i, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
      if l:match('^> ') and not _G.row then _G.row = i end
    end
    _G.inner = require('earmark').annotate(0, { _G.row - 1, 2 }, { _G.row - 1, 7 }, { set = 'vivid', label = '5' }).id
    _G.next_name = 'inner'
  ]])
  child.lua('vim.api.nvim_win_set_cursor(0, { _G.row, 3 })')
  child.type_keys(' mz')
  eq(child.lua_get('#_G.runs'), 2)
  eq(child.lua_get('_G.zk_of(_G.inner)'), 'inner.md')
  eq(has(child.lua_get('_G.runs[2].stdin'), '[source](note.md#L'), true)
  -- elsewhere in the note: the annotations linked to it
  h.cursor(1, 0)
  child.type_keys(' mz')
  eq(#child.lua_get('_G.selects'), 1)
end

T['sources of a note in a subfolder'] = function()
  h.open()
  fake()
  child.lua([[
    require('earmark.config').options.zk.dir = 'deep/er'
    _G.id = _G.anno({ 0, 4 }, { 0, 9 })
    _G.promote(_G.id)
    vim.cmd('edit ' .. _G.R .. '/deep/er/note.md')
    _G.items = #require('earmark.zk').source_items(0)
  ]])
  eq(child.lua_get('_G.items'), 1)
end

T['sources: a note no one links to, and a file with no frontmatter, list nothing'] = function()
  h.open()
  fake()
  child.lua([[
    _G.open('plain.md', { 'just text', '  source: "nowhere/at/all.md"' })
    require('earmark.zk').sources(0)
  ]])
  eq(child.lua_get('_G.msgs[#_G.msgs]'), 'earmark: no annotation links to this file')
  eq(child.v.errmsg, '')
end

T['is_note: only files inside a notebook'] = function()
  h.open()
  fake()
  eq(child.lua_get('require("earmark.zk").is_note(0)'), true)
  child.lua('vim.fn.delete(_G.root .. "/.zk", "rf"); vim.env.ZK_NOTEBOOK_DIR = nil')
  eq(child.lua_get('require("earmark.zk").is_note(0)'), false)
  child.cmd('enew')
  eq(child.lua_get('require("earmark.zk").is_note(0)'), false)
end

---------------------------------------------------------------------------
-- The export link
---------------------------------------------------------------------------

T['export link: a deleted note or a lost notebook still gives a link, never nil'] = function()
  h.open()
  fake()
  child.lua([[
    _G.id = _G.anno({ 0, 4 }, { 0, 9 }, 'Titled')
    _G.next_name = 'titled'
    _G.promote(_G.id)
  ]])
  local lines = child.lua_get('require("earmark").export(0)')
  eq(vim.tbl_contains(lines, '  → [Titled](titled.md)'), true)
  child.lua('vim.fn.delete(_G.R .. "/titled.md")')
  lines = child.lua_get('require("earmark").export(0)')
  eq(vim.tbl_contains(lines, '  → [titled](titled.md)'), true)
  child.lua('vim.fn.delete(_G.root .. "/.zk", "rf"); vim.env.ZK_NOTEBOOK_DIR = nil')
  lines = child.lua_get('require("earmark").export(0)')
  eq(vim.tbl_contains(lines, '  → [titled](titled.md)'), true)
  eq(has(table.concat(lines, '\n'), 'nil'), false)
end

T['export link: brackets in the title do not break the link'] = function()
  h.open()
  fake()
  child.lua([[
    _G.id = _G.anno({ 0, 4 }, { 0, 9 }, 'See [1] and ]this[')
    _G.promote(_G.id)
  ]])
  local lines = child.lua_get('require("earmark").export(0)')
  eq(vim.tbl_contains(lines, [[  → [See \[1\] and \]this\[](note.md)]]), true)
end

---------------------------------------------------------------------------
-- The real zk
---------------------------------------------------------------------------

T['real zk: hostile titles, tags and text parse back through zk list'] = function()
  h.open({ 'He said: "stop" -- or else \\ #not-a-tag', 'Café 日本語 line' })
  real()
  child.lua([[
    local em = require('earmark')
    local function anno(s, e, label, note, tags)
      local a = em.annotate(0, s, e, { set = 'vivid', label = label })
      if note then em.set_note(0, a.id, note) end
      if tags then em.set_tags(0, a.id, tags) end
      return a.id
    end
    em.rename_label(0, { set = 'vivid', label = '3' }, 'NPC: "boss"')
    _G.ids = {
      anno({ 0, 0 }, { 0, 39 }, '3', '"Quoted": colon \\ back --- yes #why', { 'two words', 'x:y' }),
      anno({ 1, 0 }, { 1, 20 }, '4'),
      anno({ 0, 9 }, { 0, 15 }, '5', '#leading tag then title\n---\nbody --- line'),
    }
    _G.paths = {}
    for i, id in ipairs(_G.ids) do
      _G.paths[i] = _G.promote(id).path
    end
  ]])
  local R = child.lua_get('_G.R')
  local paths = child.lua_get('_G.paths')
  local list = zk_list()
  local function note(i)
    return list[paths[i]:sub(#R + 2)]
  end
  eq(note(1).title, '"Quoted": colon \\ back --- yes')
  eq(note(1).metadata.tags, { 'npc-boss', 'two words', 'x:y', 'why' })
  eq(note(1).metadata.earmark.label, 'NPC: "boss"')
  eq(note(1).metadata.earmark.source, 'notes/doc.md')
  eq(note(1).metadata.earmark.line, 1)
  eq(note(2).title, 'Café 日本語 line')
  eq(note(2).metadata.earmark.key, '4')
  eq(note(3).title, 'tag then title')
  eq(note(3).metadata.tags, { 'vivid-5', 'leading' })
  -- the body kept the --- lines, and zk still read the frontmatter
  eq(has(note(3).body, '---\nbody --- line'), true)
  eq(child.lua_get('_G.msgs[#_G.msgs]'):find('zk note', 1, true) ~= nil, true)
end

T['real zk: a very long note line still makes a note (default file names)'] = function()
  h.open()
  real()
  child.lua([[
    local em = require('earmark')
    _G.id = em.annotate(0, { 0, 4 }, { 0, 9 }, { set = 'vivid', label = '3' }).id
    em.set_note(0, _G.id, string.rep('long ', 200))
    _G.res = _G.promote(_G.id)
  ]])
  local res = child.lua_get('_G.res')
  eq(res.err, nil)
  local R = child.lua_get('_G.R')
  local n = zk_list()[res.path:sub(#R + 2)]
  eq(vim.trim(n.title), vim.trim(string.rep('long ', 200)))
end

T['real zk: a title too long for a {{slug title}} file name is reported, not linked'] = function()
  h.open()
  real({ '[note]', 'filename = "{{slug title}}"' })
  child.lua([[
    local em = require('earmark')
    _G.id = em.annotate(0, { 0, 4 }, { 0, 9 }, { set = 'vivid', label = '3' }).id
    em.set_note(0, _G.id, string.rep('w', 300))
    _G.res = _G.promote(_G.id)
  ]])
  eq(has(child.lua_get('_G.res.err'), 'file name too long'), true)
  eq(child.lua_get('require("earmark").get(0, _G.id).zk'), vim.NIL)
  eq(child.v.errmsg, '')
end

T['real zk: two annotations whose titles share a file name do not share the note'] = function()
  h.open({ 'the cat and the dog' })
  real({ '[note]', 'filename = "{{slug title}}"' })
  child.lua([[
    local em = require('earmark')
    _G.a = em.annotate(0, { 0, 0 }, { 0, 3 }, { set = 'vivid', label = '3' }).id
    _G.b = em.annotate(0, { 0, 12 }, { 0, 15 }, { set = 'vivid', label = '4' }).id
    _G.ra = _G.promote(_G.a)
    _G.rb = _G.promote(_G.b)
  ]])
  eq(child.lua_get('_G.ra.err'), vim.NIL)
  eq(child.lua_get('require("earmark").get(0, _G.a).zk'), 'the.md')
  -- zk handed back the.md for b too, without writing it: b must not point at a's note
  eq(child.lua_get('require("earmark").get(0, _G.b).zk'), vim.NIL)
  eq(child.lua_get('_G.rb.err') ~= vim.NIL, true)
  eq(has(child.lua_get('_G.msgs[#_G.msgs]'), 'the.md'), true)
end

T['real zk: zk.dir folder that does not exist yet, and a source outside the notebook'] = function()
  h.open()
  real()
  child.lua([[
    -- the notebook is a subfolder: the project file is outside it
    vim.fn.delete(_G.root .. '/.zk', 'rf')
    vim.fn.mkdir(_G.tmp .. '/nb/.zk', 'p')
    require('earmark.config').options.zk.notebook = _G.tmp .. '/nb'
    require('earmark.config').options.zk.dir = 'new/folder'
    _G.R = vim.uv.fs_realpath(_G.tmp .. '/nb')
    local em = require('earmark')
    _G.id = em.annotate(0, { 0, 4 }, { 0, 9 }, { set = 'vivid', label = '3' }).id
    _G.res = _G.promote(_G.id)
  ]])
  local res = child.lua_get('_G.res')
  eq(res.err, nil)
  local R = child.lua_get('_G.R')
  eq(vim.startswith(res.path, R .. '/new/folder/'), true)
  local n = zk_list()[res.path:sub(#R + 2)]
  local P = child.lua_get('vim.uv.fs_realpath(_G.root)')
  eq(n.metadata.earmark.source, P .. '/notes/doc.md')
  eq(has(n.body, '[source](' .. P .. '/notes/doc.md#L1)'), true)
end

return T
