-- Names for labels. A name belongs to a label in one document (record.names), and every
-- name you give is remembered in two histories: the project's (`<root>/.earmark/names.json`,
-- the "directory default") and a global one (`<storage_dir>/names.json`). The label prompt
-- pre-fills the name from the document, then the project, then the global history.
local buffer = require('earmark.buffer')
local config = require('earmark.config')
local sets = require('earmark.sets')
local store = require('earmark.store')

local M = {}

local function key(value)
  return value.set .. '/' .. value.label
end

local function project_file(buf)
  local S = buffer.get(buf)
  return S and S.doc.root and (S.doc.base .. '/names.json') or nil
end

local function global_file()
  return config.options.storage_dir .. '/names.json'
end

--- Name history for a label, most relevant first: { { text, source } }, where source is
--- 'this file' | 'project' | 'history' | 'label'.
function M.history(buf, value)
  local out, seen = {}, {}
  local function add(text, source)
    if text and text ~= '' and not seen[text] then
      seen[text] = true
      out[#out + 1] = { text = text, source = source }
    end
  end
  add(buffer.names(buf)[key(value)], 'this file')
  local pf = project_file(buf)
  if pf then
    for _, t in ipairs(store.mru_get(pf, key(value))) do
      add(t, 'project')
    end
  end
  for _, t in ipairs(store.mru_get(global_file(), key(value))) do
    add(t, 'history')
  end
  local l = sets.label(value)
  if l and l.name ~= l.key then add(l.name, 'label') end
  return out
end

--- Whether this label has a name anywhere (document, project or global history).
function M.known(buf, value)
  return #M.history(buf, value) > 0
end

--- Name a label in this document and remember the name in both histories. An empty name
--- clears the document's name (histories keep it for later).
function M.save(buf, value, name)
  name = name and vim.trim(name) or ''
  buffer.rename_label(buf, value, name)
  if name == '' then return end
  local pf = project_file(buf)
  if pf then store.mru_push(pf, key(value), name) end
  store.mru_push(global_file(), key(value), name)
end

return M
