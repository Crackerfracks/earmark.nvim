-- Promote an annotation to a zk note (zk-nvim): a new note with the annotated text as a
-- quote, the annotation's note, and a link back to the source line. The annotation keeps
-- its own note and remembers the zk note's path.
local buffer = require('earmark.buffer')
local config = require('earmark.config')
local store = require('earmark.store')

local api = vim.api
local M = {}

local warned = false

--- Content of the zk note for an annotation.
function M.content(buf, a, s)
  local out = {}
  for _, l in ipairs(vim.split(a.quote or '', '\n')) do
    out[#out + 1] = '> ' .. l
  end
  if a.note then
    out[#out + 1] = ''
    out[#out + 1] = a.note
  end
  local name = api.nvim_buf_get_name(buf)
  if name ~= '' then
    local doc = store.doc(buf)
    local rel = doc and doc.root and vim.fs.relpath(doc.root, doc.path) or vim.fn.fnamemodify(name, ':~')
    out[#out + 1] = ''
    out[#out + 1] = ('[source](%s#L%d)'):format(rel, (s and s[1] or 0) + 1)
  end
  return table.concat(out, '\n')
end

--- Create the zk note for annotation `id` of `buf`.
function M.promote(buf, id)
  if buf == 0 then buf = api.nvim_get_current_buf() end
  local ok, zk_api = pcall(require, 'zk.api')
  if not ok then
    if not warned then
      warned = true
      vim.notify('earmark: promoting needs zk-nvim (github.com/zk-org/zk-nvim)', vim.log.levels.WARN)
    end
    return
  end
  local a = buffer.annotation(buf, id)
  if not a then return end
  local s = buffer.live_pos(buf, buffer.state[buf], id)
  local title = a.note and a.note:match('^%s*#*%s*([^\n]+)') or buffer.display_name(buf, a.values[1])
  local doc = store.doc(buf)
  local notebook = doc and doc.root and vim.uv.fs_stat(doc.root .. '/.zk') and doc.root or nil
  zk_api.new(notebook, { title = vim.trim(title), content = M.content(buf, a, s), dir = config.options.zk.dir },
    function(err, res)
      vim.schedule(function()
        if err or not res or not res.path then
          return vim.notify('earmark: zk could not create the note: ' .. tostring(err), vim.log.levels.ERROR)
        end
        local cur = buffer.annotation(buf, id)
        if cur then
          cur.zk = res.path
          buffer.emit(buf, 'update', { id })
          buffer.schedule_save(buf)
        end
        if config.options.zk.open then vim.cmd('vsplit ' .. vim.fn.fnameescape(res.path)) end
        vim.notify('earmark: zk note ' .. vim.fn.fnamemodify(res.path, ':~:.'))
      end)
    end)
end

return M
