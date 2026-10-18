-- zk notes for annotations, through the zk command line (github.com/zk-org/zk); zk-nvim is
-- not needed. Promoting writes a note with the annotated text as a quote, the annotation's
-- note and a link back to the source line, under frontmatter earmark writes itself. The
-- annotation remembers the note (`a.zk`, relative to the notebook), so the same key opens it
-- next time, and from inside a note it lists the annotations linked to it.
local buffer = require('earmark.buffer')
local config = require('earmark.config')
local sets = require('earmark.sets')
local store = require('earmark.store')
local tags = require('earmark.tags')

local api = vim.api
local uv = vim.uv
local M = {}

local MISSING = 'zk not found (Arch: sudo pacman -S zk)'

local function notify(msg, level)
  vim.notify('earmark: ' .. msg, level or vim.log.levels.INFO)
end

local function opts_()
  return config.options.zk
end

local function real(path)
  path = vim.fs.normalize(path)
  return uv.fs_realpath(path) or path
end

local function is_abs(path)
  return path:sub(1, 1) == '/' or path:match('^%a:[/\\]') ~= nil
end

--- Run a command: cb({ code, stdout, stderr, missing? }) on the main loop. Tests replace it.
function M._run(argv, opts, cb)
  if vim.fn.executable(argv[1]) == 0 then return cb({ code = 127, stdout = '', stderr = '', missing = true }) end
  local ok, err = pcall(vim.system, argv, { cwd = opts.cwd, stdin = opts.stdin, text = true }, vim.schedule_wrap(cb))
  if not ok then cb({ code = -1, stdout = '', stderr = tostring(err) }) end
end

--- The result of `_run` is usable; otherwise say why not (once).
local function succeeded(res, what)
  if res.missing then
    notify(MISSING, vim.log.levels.WARN)
    return false
  end
  if res.code ~= 0 then
    local msg = vim.trim(res.stderr or '')
    notify(('zk could not %s: %s'):format(what, msg ~= '' and msg or ('exit code ' .. tostring(res.code))),
      vim.log.levels.ERROR)
    return false
  end
  return true
end

---------------------------------------------------------------------------
-- Where notes are
---------------------------------------------------------------------------

--- Path of a buffer's file, or nil for scratch buffers.
local function file_of(where)
  if type(where) == 'string' then return where end
  local buf = (where == nil or where == 0) and api.nvim_get_current_buf() or where
  local doc = store.doc(buf)
  return doc and doc.path or nil
end

--- The zk notebook for a buffer (0 = current) or a file path: the `zk.notebook` option,
--- else the nearest directory with `.zk` above the file, else $ZK_NOTEBOOK_DIR.
--- Returns the path, or nil and why not.
function M.notebook(where)
  local o = opts_().notebook
  if type(o) == 'string' and o ~= '' then return real(vim.fn.expand(o)) end
  local file = file_of(where)
  local nb = file and vim.fs.root(file, '.zk')
  if nb then return real(nb) end
  local env = vim.env.ZK_NOTEBOOK_DIR
  if env and env ~= '' then return real(env) end
  return nil, 'no zk notebook for this file: run `zk init` in your notes folder, or set zk.notebook'
end

--- Absolute path of an annotation's note (`a.zk` is relative to the notebook of the file it
--- annotates; absolute values are read as they are). `where`: buffer or file path.
function M.path(a, where)
  if not a or type(a.zk) ~= 'string' or a.zk == '' then return nil end
  if is_abs(a.zk) then return a.zk end
  local nb = M.notebook(where)
  return nb and vim.fs.normalize(nb .. '/' .. a.zk) or nil
end

--- `path` relative to directory `from` (both absolute), with `..` where needed.
local function relative(from, path)
  local a = vim.split(from, '/', { trimempty = true })
  local b = vim.split(path, '/', { trimempty = true })
  local i = 1
  while a[i] and b[i] and a[i] == b[i] do
    i = i + 1
  end
  local out = {}
  for _ = i, #a do
    out[#out + 1] = '..'
  end
  for j = i, #b do
    out[#out + 1] = b[j]
  end
  return #out > 0 and table.concat(out, '/') or '.'
end

--- Markdown link target; <> keeps spaces and parentheses from ending it.
local function target(path)
  return path:match('[%s()]') and ('<' .. path .. '>') or path
end

--- The note's title from its frontmatter, else its file name.
function M.title(path)
  local ok, lines = pcall(vim.fn.readfile, path, '', 30)
  if ok and lines[1] == '---' then
    for i = 2, #lines do
      if lines[i] == '---' then break end
      local t = lines[i]:match('^title:%s*(.-)%s*$')
      if t and t ~= '' then
        local dok, s = pcall(vim.json.decode, t)
        if dok and type(s) == 'string' then return s end
        return (t:gsub('^[\'"]', ''):gsub('[\'"]$', ''))
      end
    end
  end
  return vim.fn.fnamemodify(path, ':t:r')
end

--- `→ [title](path)` for the export: relative to the export file's folder `dest_dir` when
--- given, else the note's path in the notebook.
function M.export_link(buf, a, dest_dir)
  local path = M.path(a, buf)
  local title = path and M.title(path) or vim.fn.fnamemodify(a.zk, ':t:r')
  local link = a.zk
  if path and dest_dir then link = relative(real(dest_dir), real(path)) end
  return ('→ [%s](%s)'):format(title, target(link))
end

---------------------------------------------------------------------------
-- The note
---------------------------------------------------------------------------

-- JSON strings are valid YAML scalars; escaped slashes would only look odd
local function yaml(v)
  return (vim.json.encode(v):gsub('\\/', '/'))
end

local function slug(s)
  return (s:lower():gsub('[%s%p]+', '-'):gsub('^%-+', ''):gsub('%-+$', ''))
end

--- The label's own name (yours for this file, else the set's), or nil when it has none.
local function label_name(buf, v)
  local n = buffer.names(buf)[buffer.label_key(v)]
  if n then return n end
  local l = sets.label(v)
  return l and l.name or nil
end

--- The note's first line, else the start of the quote.
function M.title_for(a)
  local t = a.note and a.note:match('^%s*#*%s*([^\n]+)')
  t = t and vim.trim(t) or ''
  if t == '' then
    t = vim.trim((a.quote or ''):gsub('%s+', ' '))
    if vim.fn.strchars(t) > 60 then t = vim.trim(vim.fn.strcharpart(t, 0, 60)) end
  end
  return t ~= '' and t or 'earmark'
end

--- Tags for the note: the label, then the annotation's tags (its own and its note's).
function M.tags_for(buf, a)
  local v = a.values[1]
  local name = label_name(buf, v)
  local out, seen = {}, {}
  -- a numbered label's name is its key: "vivid-3" says more than "3"
  local first = (name and name ~= v.label) and slug(name) or ''
  if first == '' then first = slug(v.set .. '-' .. v.label) end
  for _, t in ipairs({ first, unpack((tags.of(a))) }) do
    if t ~= '' and not seen[t] then
      seen[t] = true
      out[#out + 1] = t
    end
  end
  return out
end

--- Everything that goes into a new note for annotation `a` of `buf`.
--- Returns { title, dir, frontmatter, body, extra } (dir relative to the notebook).
function M.compose(buf, a, nb)
  local s = buffer.live_pos(buf, buffer.state[buf], a.id)
  local v = a.values[1]
  local src = file_of(buf)
  local dir = opts_().dir
  if type(dir) == 'function' then
    local label = buffer.display_name(buf, v)
    dir = dir({ buf = buf, annotation = a, value = v, label = label, notebook = nb, source = src })
  end
  dir = type(dir) == 'string' and dir or ''
  if is_abs(dir) then dir = vim.fs.relpath(nb, real(dir)) or dir end
  dir = dir:gsub('^%./', ''):gsub('/+$', '')
  if dir == '' then dir = '.' end
  local note_dir = vim.fs.normalize(nb .. '/' .. dir)
  local line = s and (s[1] + 1) or nil

  local body = {}
  for _, l in ipairs(vim.split(a.quote or '', '\n')) do
    body[#body + 1] = '> ' .. l
  end
  if a.note then
    body[#body + 1] = ''
    body[#body + 1] = a.note
  end
  local source -- the source as the frontmatter records it
  if src then
    local inside = vim.fs.relpath(nb, src)
    source = inside or src
    -- outside the notebook a relative link would depend on where the notebook is
    local link = inside and relative(note_dir, src) or src
    body[#body + 1] = ''
    body[#body + 1] = ('[source](%s)'):format(target(link .. (line and ('#L' .. line) or '')))
  end

  local title = M.title_for(a)
  local fm = { '---', 'title: ' .. yaml(title) }
  fm[#fm + 1] = 'tags: [' .. table.concat(vim.tbl_map(yaml, M.tags_for(buf, a)), ', ') .. ']'
  fm[#fm + 1] = 'earmark:'
  fm[#fm + 1] = '  id: ' .. yaml(a.id)
  fm[#fm + 1] = '  set: ' .. yaml(v.set)
  fm[#fm + 1] = '  key: ' .. yaml(v.label)
  fm[#fm + 1] = '  label: ' .. yaml(buffer.display_name(buf, v))
  if source then fm[#fm + 1] = '  source: ' .. yaml(source) end
  if line then fm[#fm + 1] = '  line: ' .. line end
  fm[#fm + 1] = '---'

  local extra = { 'id=' .. a.id, 'set=' .. v.set, 'key=' .. v.label }
  if line then extra[#extra + 1] = 'line=' .. line end
  return {
    title = title,
    dir = dir,
    frontmatter = table.concat(fm, '\n'),
    body = table.concat(body, '\n'),
    extra = table.concat(extra, ','),
  }
end

local function plugin_template()
  local here = debug.getinfo(1, 'S').source:sub(2)
  return vim.fn.fnamemodify(here, ':p:h:h:h') .. '/templates/earmark.md'
end

--- argv and stdin for `zk new`.
function M.command(note, nb)
  local o = opts_()
  local argv = { o.cmd or 'zk', '--notebook-dir', nb, '--no-input', 'new', note.dir, '-i', '-p', '--title', note.title }
  if o.template then
    -- your template writes the frontmatter; it gets earmark's fields as extras
    vim.list_extend(argv, { '--template', o.template, '--extra', note.extra })
    return argv, note.body .. '\n'
  end
  vim.list_extend(argv, { '--template', plugin_template() })
  return argv, note.frontmatter .. '\n\n' .. note.body .. '\n'
end

---------------------------------------------------------------------------
-- Linking annotations and notes
---------------------------------------------------------------------------

--- Point annotations `ids` of `buf` at the note at `path` (nil unlinks).
local function set_link(buf, ids, nb, path)
  local done = {}
  for _, id in ipairs(ids) do
    local a = buffer.annotation(buf, id)
    if a then
      a.zk = path and (vim.fs.relpath(nb, real(path)) or path) or nil
      a.updated = os.time()
      done[#done + 1] = id
    end
  end
  if #done == 0 then return end
  buffer.schedule_save(buf)
  buffer.emit(buf, 'zk', done)
end

--- Open the note in a split, or go to the window already showing it.
function M.open(path)
  local want = real(path)
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    local name = api.nvim_buf_get_name(api.nvim_win_get_buf(w))
    if name ~= '' and real(name) == want then return api.nvim_set_current_win(w) end
  end
  vim.cmd('vsplit ' .. vim.fn.fnameescape(path))
end

--- After promoting: offer to link the other annotations of this buffer with the same quote
--- and label (e.g. made by `<leader>mo`) to the same note.
local function offer_siblings(buf, a, nb, path)
  local v = a.values[1]
  local ids = {}
  for _, x in ipairs(buffer.list(buf)) do
    local o = x.annotation
    local same = o.quote == a.quote and o.values[1].set == v.set and o.values[1].label == v.label
    if o.id ~= a.id and not o.zk and same then
      ids[#ids + 1] = o.id
    end
  end
  if #ids == 0 then return end
  local q = ('Also link %d other annotation%s with this quote and label?'):format(#ids, #ids == 1 and '' or 's')
  vim.ui.select({ 'Yes', 'No' }, { prompt = q }, function(c)
    if c == 'Yes' then set_link(buf, ids, nb, path) end
  end)
end

local function create(buf, id, opts, cb)
  local a = buffer.annotation(buf, id)
  if not a then return cb('no annotation ' .. tostring(id)) end
  local nb, err = M.notebook(buf)
  if not nb then
    notify(err, vim.log.levels.WARN)
    return cb(err)
  end
  local note = M.compose(buf, a, nb)
  -- zk refuses a folder that doesn't exist yet (zk.dir = 'npcs' on the first note)
  if note.dir ~= '.' then pcall(vim.fn.mkdir, nb .. '/' .. note.dir, 'p') end
  local argv, stdin = M.command(note, nb)
  M._run(argv, { cwd = nb, stdin = stdin }, function(res)
    if not succeeded(res, 'create the note') then return cb(res.missing and MISSING or vim.trim(res.stderr or '')) end
    local out = vim.split(vim.trim(res.stdout or ''), '\n')
    local path = vim.trim(out[#out] or '')
    if path == '' then
      notify('zk did not say where it wrote the note', vim.log.levels.ERROR)
      return cb('no path')
    end
    if not is_abs(path) then path = nb .. '/' .. path end
    path = real(path)
    if not api.nvim_buf_is_valid(buf) or not buffer.annotation(buf, id) then return cb('annotation gone', path) end
    set_link(buf, { id }, nb, path)
    local open = opts.open
    if open == nil then open = opts_().open end
    if open then M.open(path) end
    notify('zk note ' .. vim.fn.fnamemodify(path, ':~:.'))
    if opts.ask then offer_siblings(buf, buffer.annotation(buf, id), nb, path) end
    cb(nil, path)
  end)
end

--- Promote annotation `id` of `buf` to a zk note; cb(err, path) when done.
--- An annotation already linked to a note that exists keeps it (cb gets its path) unless
--- opts.force. opts.open: open the new note (default `zk.open`). opts.ask: what the key does:
--- open an existing note, ask what to do when it's gone, offer to link the same quotes.
function M.promote(buf, id, opts, cb)
  if buf == nil or buf == 0 then buf = api.nvim_get_current_buf() end
  opts, cb = opts or {}, cb or function() end
  local a = buffer.annotation(buf, id)
  if not a then return cb('no annotation ' .. tostring(id)) end
  if a.zk and not opts.force then
    local path = M.path(a, buf)
    if path and uv.fs_stat(path) then
      if opts.ask or opts.open then M.open(path) end
      return cb(nil, path)
    end
    if opts.ask then
      return vim.ui.select({ 'recreate', 'unlink' }, {
        prompt = ('The zk note %s is gone'):format(a.zk),
        format_item = function(c)
          return c == 'recreate' and 'Make a new note' or 'Unlink it from the annotation'
        end,
      }, function(c)
        if c == 'recreate' then return create(buf, id, opts, cb) end
        if not c then return cb('cancelled') end
        set_link(buf, { id }, nil, nil)
        notify('unlinked the zk note')
        cb(nil, nil)
      end)
    end
  end
  create(buf, id, opts, cb)
end

--- `:Earmark zk link`: attach an existing note of the notebook to annotation `id`.
function M.link(buf, id)
  if buf == nil or buf == 0 then buf = api.nvim_get_current_buf() end
  local nb, err = M.notebook(buf)
  if not nb then return notify(err, vim.log.levels.WARN) end
  local argv = { opts_().cmd or 'zk', '--notebook-dir', nb, '--no-input', 'list', '--format', 'json', '-q', '-P' }
  M._run(argv, { cwd = nb }, function(res)
    if not succeeded(res, 'list the notes') then return end
    local ok, notes = pcall(vim.json.decode, res.stdout or '')
    if not ok or type(notes) ~= 'table' then
      notes = {} -- one object per line (jsonl)
      for l in (res.stdout or ''):gmatch('[^\n]+') do
        local lok, n = pcall(vim.json.decode, l)
        if lok and type(n) == 'table' then notes[#notes + 1] = n end
      end
    end
    local items = {}
    for _, n in ipairs(notes) do
      local path = n.absPath or (n.path and (nb .. '/' .. n.path))
      if path then
        local title = (type(n.title) == 'string' and n.title ~= '') and n.title or vim.fn.fnamemodify(path, ':t:r')
        items[#items + 1] = { text = title .. '  ' .. (n.path or path), file = path, pos = { 0, 0 } }
      end
    end
    require('earmark.ui.picker').pick(items, {
      prompt = 'Link to zk note',
      empty = 'no notes in ' .. vim.fn.fnamemodify(nb, ':~'),
      on_choice = function(it)
        set_link(buf, { id }, nb, it.file)
        notify('linked to ' .. vim.fn.fnamemodify(it.file, ':~:.'))
      end,
    })
  end)
end

---------------------------------------------------------------------------
-- Finding them
---------------------------------------------------------------------------

--- `:Earmark zk pick [query]`: annotations in the project with a note; <CR> opens the note.
function M.pick(args)
  local p = require('earmark.ui.picker')
  local q = 'has:zk ' .. table.concat(args or {}, ' ')
  p.pick(p.filter(p.project_items(0), q), {
    prompt = 'Annotations with a zk note',
    empty = 'no annotations with a zk note',
    on_choice = function(it)
      local path = M.path(it.annotation, it.buf or it.file)
      if path and uv.fs_stat(path) then return M.open(path) end
      notify(('the zk note %s is gone'):format(it.annotation.zk), vim.log.levels.WARN)
    end,
  })
end

--- Whether `buf` is a file inside a zk notebook.
function M.is_note(buf)
  local file = file_of(buf)
  local nb = file and M.notebook(file)
  return nb ~= nil and vim.fs.relpath(nb, file) ~= nil
end

--- Project roots that may hold annotations linked to the note in `buf`.
local function roots_for(buf)
  local roots, seen = {}, {}
  local function add(r)
    if r and not seen[r] then
      seen[r] = true
      roots[#roots + 1] = r
    end
  end
  local doc = store.doc(buf)
  add(doc and doc.root)
  for _, S in pairs(buffer.state) do
    add(S.doc.root)
  end
  local cwd = vim.fs.root(uv.cwd(), config.options.root_markers)
  add(cwd and real(cwd))
  -- the source recorded in a note earmark wrote
  for _, l in ipairs(api.nvim_buf_get_lines(buf, 0, 30, false)) do
    local s = l:match('^%s+source:%s*(.-)%s*$')
    if s then
      local ok, src = pcall(vim.json.decode, s)
      src = ok and type(src) == 'string' and src or s
      local nb = M.notebook(buf)
      if not is_abs(src) and nb then src = nb .. '/' .. src end
      local r = vim.fs.root(src, config.options.root_markers)
      add(r and real(r))
      break
    end
  end
  return roots
end

--- Picker items for the annotations linked to the note in `buf`.
function M.source_items(buf)
  if buf == nil or buf == 0 then buf = api.nvim_get_current_buf() end
  local note = real(api.nvim_buf_get_name(buf))
  local p = require('earmark.ui.picker')
  local items, seen = {}, {}
  local function consider(list)
    for _, it in ipairs(list) do
      local a = it.annotation
      if a and a.zk and not seen[a.id] then
        local path = M.path(a, it.buf or it.file)
        if path and real(path) == note then
          seen[a.id] = true
          items[#items + 1] = it
        end
      end
    end
  end
  for _, r in ipairs(roots_for(buf)) do
    consider(p.root_items(r))
  end
  for b, S in pairs(buffer.state) do
    if not S.doc.root then consider(p.doc_items(b)) end
  end
  return items
end

--- `:Earmark zk sources` (or `<leader>mz` in a note): the annotations linked to this note.
function M.sources(buf)
  local p = require('earmark.ui.picker')
  p.pick(M.source_items(buf), {
    prompt = 'Annotations linked to this note',
    empty = 'no annotation links to this file',
    on_choice = p.jump_to,
  })
end

return M
