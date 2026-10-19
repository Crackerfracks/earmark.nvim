-- Document identity and on-disk records.
--
-- File buffers:   <root>/.earmark/docs/<path relative to root>.json, where <root> is the
--                 nearest directory with one of `root_markers`; otherwise
--                 <storage_dir>/files/<absolute path>.json
-- Other buffers:  <storage_dir>/scratch/<id>.json (scratch, unnamed, plugin buffers)
--
-- Each record has a sibling text snapshot (the document text the positions refer to) under
-- `<base>/snap/`, kept out of the JSON so records stay small and diffable. Inside a project
-- `snap/` is gitignored: a fresh clone re-anchors by quote and context alone.
--
-- Schema history: v1 kept the snapshot inline (`snapshot` field). v1 records are read as is
-- and rewritten as v2 on the next save.
local config = require('earmark.config')
local log = require('earmark.log')

local M = {}

M.VERSION = 2

local uv = vim.uv or vim.loop

local function uuid()
  local b = { (uv.random(16)):byte(1, 16) }
  b[7] = bit.bor(bit.band(b[7], 0x0f), 0x40)
  b[9] = bit.bor(bit.band(b[9], 0x3f), 0x80)
  local hex = {}
  for i = 1, 16 do
    hex[i] = string.format('%02x', b[i])
  end
  local h = table.concat(hex)
  return ('%s-%s-%s-%s-%s'):format(h:sub(1, 8), h:sub(9, 12), h:sub(13, 16), h:sub(17, 20), h:sub(21, 32))
end
M.uuid = uuid

function M.fingerprint(lines)
  return vim.fn.sha256(table.concat(lines, '\n'))
end

--- @class earmark.Doc
--- @field kind 'file'|'scratch'
--- @field path string?    absolute path of the file (file docs)
--- @field key string      path relative to the store dir (file) or scratch id
--- @field root string?    project root (file docs inside a project)
--- @field dir string      store directory the record lives under
--- @field record string   absolute path of the record file

--- Identity of a buffer's document, or nil if the buffer can't be annotated.
--- @return earmark.Doc?
function M.doc(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return nil end
  local bt = vim.bo[buf].buftype
  if vim.tbl_contains(config.options.ignore_buftypes, bt) then return nil end
  local name = vim.api.nvim_buf_get_name(buf)
  if bt == '' and name ~= '' and not name:match('^%w[%w+.-]*://') then
    local path = vim.fs.normalize(vim.fn.fnamemodify(name, ':p'))
    path = uv.fs_realpath(path) or path
    if path:match('/%.earmark/') then return nil end -- never annotate our own records
    local root = vim.fs.root(path, config.options.root_markers)
    local base, dir, snapdir, key
    if root then
      root = uv.fs_realpath(root) or root
      key = vim.fs.relpath(root, path)
      base = root .. '/.earmark'
      dir, snapdir = base .. '/docs', base .. '/snap'
    end
    if not key then
      root, key = nil, path:gsub('^/', '')
      base = config.options.storage_dir
      dir, snapdir = base .. '/files', base .. '/snap/files'
    end
    return {
      kind = 'file',
      path = path,
      key = key,
      root = root,
      base = base,
      dir = dir,
      record = dir .. '/' .. key .. '.json',
      snap = snapdir .. '/' .. key .. '.snap',
    }
  end
  local id = vim.b[buf].earmark_doc
  if type(id) ~= 'string' then
    id = uuid()
    vim.b[buf].earmark_doc = id
  end
  local base = config.options.storage_dir
  local dir = base .. '/scratch'
  return {
    kind = 'scratch',
    key = id,
    base = base,
    dir = dir,
    record = dir .. '/' .. id .. '.json',
    snap = base .. '/snap/scratch/' .. id .. '.snap',
  }
end

--- Store directory for project-wide files (names history, label sets): `<root>/.earmark`
--- inside a project, else `storage_dir`.
function M.base_for(doc)
  return doc and doc.base or config.options.storage_dir
end

local function is_pos(p)
  return p == nil or (type(p) == 'table' and type(p[1]) == 'number' and type(p[2]) == 'number')
end

local function is_annotation(a)
  if type(a) ~= 'table' or type(a.id) ~= 'string' then return false end
  if type(a.values) ~= 'table' or type(a.values[1]) ~= 'table' then return false end
  for _, k in ipairs({ 'quote', 'prefix', 'suffix', 'original_quote', 'note' }) do
    if a[k] ~= nil and type(a[k]) ~= 'string' then return false end
  end
  return is_pos(a.s) and is_pos(a.e)
end

--- Whether a decoded record has the shape earmark writes (so loading it can't fail).
local function well_formed(rec)
  if type(rec) ~= 'table' or rec[1] ~= nil then return false end
  for _, k in ipairs({ 'annotations', 'trash', 'names', 'colors', 'doc' }) do
    if rec[k] ~= nil and type(rec[k]) ~= 'table' then return false end
  end
  for _, k in ipairs({ 'names', 'colors' }) do
    if rec[k] and rec[k][1] ~= nil then return false end
  end
  for _, k in ipairs({ 'annotations', 'trash' }) do
    for _, a in ipairs(rec[k] or {}) do
      if not is_annotation(a) then return false end
    end
  end
  return true
end

--- Read a record. Returns record, or nil plus an error message. A record that exists but
--- can't be parsed is reported as an error so callers never overwrite it.
function M.read(path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local data = f:read('*a')
  f:close()
  if not data or not data:match('%S') then return nil end -- empty: nothing in it to keep
  local ok, rec = pcall(vim.json.decode, data, { luanil = { object = true, array = true } })
  if not ok or type(rec) ~= 'table' then return nil, 'could not parse ' .. path end
  if not well_formed(rec) then return nil, path .. ' is not an earmark record' end
  if (rec.version or 0) > M.VERSION then return nil, path .. ' was written by a newer earmark' end
  return rec
end

--- Write `data` (a string) to `path` atomically (temp file + rename).
local function write_atomic(path, data)
  local mok, merr = pcall(vim.fn.mkdir, vim.fs.dirname(path), 'p')
  if not mok then return false, merr end
  -- a short name: a long file name plus a suffix could pass the 255-byte limit
  local tmp = ('%s/.%d.%d.tmp'):format(vim.fs.dirname(path), uv.os_getpid(), uv.hrtime())
  local f, err = io.open(tmp, 'w')
  if not f then return false, err end
  f:write(data)
  f:close()
  local ok, rerr = os.rename(tmp, path)
  if not ok then
    os.remove(tmp)
    return false, rerr
  end
  return true
end
M.write_atomic = write_atomic

--- `<root>/.earmark/.gitignore`, written once, so snapshots and temp files stay out of git.
local function ensure_gitignore(path)
  local base = path:match('^(.*/%.earmark)/')
  if not base or uv.fs_stat(base .. '/.gitignore') then return end
  write_atomic(base .. '/.gitignore', '# written by earmark.nvim\nsnap/\n*.tmp*\nexport/\n')
end

--- Write a record atomically (temp file + rename). A nil record deletes the file.
function M.write(path, rec)
  if rec == nil then
    os.remove(path)
    M.orphans_dirty(vim.fs.dirname(path))
    return true
  end
  ensure_gitignore(path)
  local ok, err = write_atomic(path, vim.json.encode(rec, { indent = '  ', sort_keys = true }) .. '\n')
  if not ok then return false, err end
  M.orphans_dirty(vim.fs.dirname(path))
  return true
end

---------------------------------------------------------------------------
-- Snapshots
---------------------------------------------------------------------------

--- Write a text snapshot (`snap` = its path). nil lines deletes it.
function M.write_snapshot(snap, lines)
  if not snap then return true end
  if lines == nil then
    os.remove(snap)
    return true
  end
  return write_atomic(snap, table.concat(lines, '\n'))
end

--- Snapshot path belonging to a record path.
function M.snap_path(record)
  local base, rest = record:match('^(.*/%.earmark)/docs/(.*)%.json$')
  if base then return base .. '/snap/' .. rest .. '.snap' end
  -- outside a project: <storage_dir>/{files,scratch}/<key>.json (the key itself may contain
  -- directories called "files" or "scratch", so match the storage dir, not the last one)
  local dir = config.options.storage_dir
  for _, kind in ipairs({ 'files', 'scratch' }) do
    local prefix = dir .. '/' .. kind .. '/'
    if record:sub(1, #prefix) == prefix and record:sub(-5) == '.json' then
      return dir .. '/snap/' .. kind .. '/' .. record:sub(#prefix + 1, -6) .. '.snap'
    end
  end
  return nil
end

--- Snapshot lines for a record, or nil when missing or not matching the record's
--- fingerprint (e.g. the JSON came from git but the gitignored snapshot did not).
--- `snap` is the snapshot path (doc.snap, or store.snap_path(record)).
function M.read_snapshot(snap, rec)
  if rec and type(rec.snapshot) == 'table' then return rec.snapshot end -- v1, inline
  if not snap then return nil end
  local f = io.open(snap, 'r')
  if not f then return nil end
  local data = f:read('*a')
  f:close()
  local lines = vim.split(data, '\n', { plain = true })
  if rec and rec.fingerprint and M.fingerprint(lines) ~= rec.fingerprint then
    log.info('snapshot %s does not match its record; anchoring by quote', snap)
    return nil
  end
  return lines
end

---------------------------------------------------------------------------
-- Small JSON maps: most-recently-used histories (label names, tags)
---------------------------------------------------------------------------

local function read_json(path)
  local f = io.open(path, 'r')
  if not f then return {} end
  local data = f:read('*a')
  f:close()
  local ok, t = pcall(vim.json.decode, data, { luanil = { object = true, array = true } })
  if not ok or type(t) ~= 'table' then
    log.warn('could not parse %s', path)
    return {}
  end
  return t
end
M.read_json = read_json

function M.write_json(path, t)
  return write_atomic(path, vim.json.encode(t, { indent = '  ', sort_keys = true }) .. '\n')
end

--- Values recorded under `key` in an MRU file, most recent first.
function M.mru_get(path, key)
  local t = read_json(path)
  return type(t[key]) == 'table' and t[key] or {}
end

--- Record `value` as the most recent under `key` (deduplicated, capped).
function M.mru_push(path, key, value, cap)
  if value == nil or value == '' then return end
  local t = read_json(path)
  local list = type(t[key]) == 'table' and t[key] or {}
  local out = { value }
  for _, v in ipairs(list) do
    if v ~= value and #out < (cap or 50) then out[#out + 1] = v end
  end
  t[key] = out
  M.write_json(path, t)
end

---------------------------------------------------------------------------
-- Rename detection: records whose file no longer exists, indexed by fingerprint.
---------------------------------------------------------------------------

local orphan_index = {} -- store dir -> { [fingerprint] = { { record path, source path } ... } }

function M.orphans_dirty()
  orphan_index = {}
end

local function source_path(doc_dir, rec)
  if not (rec.doc and rec.doc.key) then return nil end
  if doc_dir:match('/%.earmark/docs$') then return doc_dir:gsub('/%.earmark/docs$', '') .. '/' .. rec.doc.key end
  return '/' .. rec.doc.key
end

--- Record for the same file where an earlier root put it: under the `.earmark` of an
--- enclosing directory (a nearer root marker appeared) or under `storage_dir` (it was outside
--- any project, or its root marker went away).
function M.find_rerooted(doc)
  local function found(record)
    return record ~= doc.record and uv.fs_stat(record) and record or nil
  end
  for dir in vim.fs.parents(doc.path) do
    if dir ~= doc.root and uv.fs_stat(dir .. '/.earmark/docs') then
      local rec = found(dir .. '/.earmark/docs/' .. vim.fs.relpath(dir, doc.path) .. '.json')
      if rec then return rec end
    end
  end
  if doc.root then
    return found(config.options.storage_dir .. '/files/' .. doc.path:gsub('^/', '') .. '.json')
  end
end

--- Find a record for a file that was renamed/moved: one in `doc.dir` whose source file is
--- gone and whose recorded text matches `lines` exactly.
function M.find_renamed(doc, lines)
  local idx = orphan_index[doc.dir]
  if not idx then
    idx = {}
    if vim.fn.isdirectory(doc.dir) == 1 then
      for name, type in vim.fs.dir(doc.dir, { depth = 50 }) do
        if type == 'file' and name:match('%.json$') then
          local path = doc.dir .. '/' .. name
          local rec = M.read(path)
          local src = rec and source_path(doc.dir, rec)
          if src and rec.fingerprint then
            idx[rec.fingerprint] = idx[rec.fingerprint] or {}
            table.insert(idx[rec.fingerprint], { path, src })
          end
        end
      end
    end
    orphan_index[doc.dir] = idx
  end
  -- whether the source is gone is checked now: files move outside Neovim without telling us
  for _, it in ipairs(idx[M.fingerprint(lines)] or {}) do
    if not uv.fs_stat(it[2]) and uv.fs_stat(it[1]) then return it[1] end
  end
end

return M
