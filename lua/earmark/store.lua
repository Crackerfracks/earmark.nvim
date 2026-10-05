-- Document identity and on-disk records.
--
-- File buffers:   <root>/.earmark/docs/<path relative to root>.json, where <root> is the
--                 nearest directory with one of `root_markers`; otherwise
--                 <storage_dir>/files/<absolute path>.json
-- Other buffers:  <storage_dir>/scratch/<id>.json (scratch, unnamed, plugin buffers)
local config = require('earmark.config')

local M = {}

M.VERSION = 1

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
    local dir, key
    if root then
      root = uv.fs_realpath(root) or root
      dir, key = root .. '/.earmark/docs', vim.fs.relpath(root, path)
    end
    if not key then
      root, dir, key = nil, config.options.storage_dir .. '/files', path:gsub('^/', '')
    end
    return { kind = 'file', path = path, key = key, root = root, dir = dir, record = dir .. '/' .. key .. '.json' }
  end
  local id = vim.b[buf].earmark_doc
  if type(id) ~= 'string' then
    id = uuid()
    vim.b[buf].earmark_doc = id
  end
  local dir = config.options.storage_dir .. '/scratch'
  return { kind = 'scratch', key = id, dir = dir, record = dir .. '/' .. id .. '.json' }
end

--- Read a record. Returns record, or nil plus an error message. A record that exists but
--- can't be parsed is reported as an error so callers never overwrite it.
function M.read(path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local data = f:read('*a')
  f:close()
  local ok, rec = pcall(vim.json.decode, data, { luanil = { object = true, array = true } })
  if not ok or type(rec) ~= 'table' then return nil, 'could not parse ' .. path end
  if (rec.version or 0) > M.VERSION then return nil, path .. ' was written by a newer earmark' end
  return rec
end

--- Write a record atomically (temp file + rename). A nil record deletes the file.
function M.write(path, rec)
  if rec == nil then
    os.remove(path)
    return true
  end
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  local tmp = path .. '.tmp' .. tostring(uv.hrtime())
  local f, err = io.open(tmp, 'w')
  if not f then return false, err end
  f:write(vim.json.encode(rec, { indent = '  ', sort_keys = true }), '\n')
  f:close()
  local ok, rerr = os.rename(tmp, path)
  if not ok then
    os.remove(tmp)
    return false, rerr
  end
  M.orphans_dirty(vim.fs.dirname(path))
  return true
end

---------------------------------------------------------------------------
-- Rename detection: records whose file no longer exists, indexed by fingerprint.
---------------------------------------------------------------------------

local orphan_index = {} -- store dir -> { [fingerprint] = record path }

function M.orphans_dirty()
  orphan_index = {}
end

local function source_path(doc_dir, rec)
  if not (rec.doc and rec.doc.key) then return nil end
  if doc_dir:match('/%.earmark/docs$') then return doc_dir:gsub('/%.earmark/docs$', '') .. '/' .. rec.doc.key end
  return '/' .. rec.doc.key
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
          if src and not uv.fs_stat(src) and rec.fingerprint then idx[rec.fingerprint] = path end
        end
      end
    end
    orphan_index[doc.dir] = idx
  end
  return idx[M.fingerprint(lines)]
end

return M
