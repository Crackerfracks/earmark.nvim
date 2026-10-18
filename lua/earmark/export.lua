-- Markdown export of a buffer's annotations: grouped by label (default), position, tag or
-- time, with notes, and a "Detached" section for annotations whose text is gone.
local buffer = require('earmark.buffer')
local config = require('earmark.config')
local store = require('earmark.store')
local tags = require('earmark.tags')

local api = vim.api
local M = {}

local function one_line(s)
  return vim.trim((s or ''):gsub('%s+', ' '))
end

local function tag_text(a)
  local list, idents = tags.of(a)
  local out = {}
  for _, t in ipairs(list) do
    out[#out + 1] = '#' .. t
  end
  for _, t in ipairs(idents) do
    out[#out + 1] = '@' .. t
  end
  return table.concat(out, ' ')
end

local function lines_ref(x)
  local s, e = x.s[1] + 1, x.e[1] + 1
  if x.e[2] == 0 and x.e[1] > x.s[1] then e = e - 1 end
  return s == e and ('L' .. s) or ('L%d–L%d'):format(s, e)
end

--- One list item for a placed annotation.
local function item(buf, x, with_name)
  local a = x.annotation
  local head = {}
  if with_name then
    head[#head + 1] = '**' .. table.concat(vim.tbl_map(function(v)
      return buffer.display_name(buf, v)
    end, a.values), ' + ') .. '**'
  end
  head[#head + 1] = ('**"%s"**'):format(one_line(a.quote))
  head[#head + 1] = '(' .. lines_ref(x) .. ')'
  local t = tag_text(a)
  if t ~= '' then head[#head + 1] = t end
  local out = { '- ' .. table.concat(head, ' ') }
  for _, v in ipairs(a.values) do
    if v.text then out[#out + 1] = '  > ' .. v.text end
  end
  if a.note then
    for _, l in ipairs(vim.split(a.note, '\n')) do
      out[#out + 1] = l == '' and '' or ('  ' .. l)
    end
  end
  if a.zk then out[#out + 1] = '  ' .. require('earmark.zk').export_link(buf, a) end
  return out
end

--- Markdown lines for the annotations of `buf`.
--- opts.group_by: 'label' (default) | 'position' | 'tag' | 'time';
--- opts.include_detached (default true); opts.format(annotations, ctx) -> lines replaces the
--- body (config `export.format` too).
function M.markdown(buf, opts)
  if buf == 0 then buf = api.nvim_get_current_buf() end
  opts = vim.tbl_extend('force', config.options.export, opts or {})
  local list = buffer.list(buf)
  local placed, detached = {}, {}
  for _, x in ipairs(list) do
    if x.s then placed[#placed + 1] = x else detached[#detached + 1] = x end
  end
  local name = api.nvim_buf_get_name(buf)
  name = name ~= '' and vim.fn.fnamemodify(name, ':t') or '[scratch]'
  local out = { ('# %s — earmark export (%s)'):format(name, os.date('%Y-%m-%d')), '' }
  if opts.format then
    vim.list_extend(out, opts.format(list, { buf = buf, name = name }) or {})
    return out
  end
  local function section(title, xs, with_name)
    if #xs == 0 then return end
    if title then
      out[#out + 1] = '## ' .. title
    end
    for _, x in ipairs(xs) do
      vim.list_extend(out, item(buf, x, with_name))
    end
    out[#out + 1] = ''
  end
  local by = opts.group_by
  if by == 'position' then
    section(nil, placed, true)
  elseif by == 'time' then
    table.sort(placed, function(x, y)
      return (x.annotation.created or 0) < (y.annotation.created or 0)
    end)
    section(nil, placed, true)
  elseif by == 'tag' then
    local groups, order, untagged = {}, {}, {}
    for _, x in ipairs(placed) do
      local list_t = tags.of(x.annotation)
      if #list_t == 0 then untagged[#untagged + 1] = x end
      for _, t in ipairs(list_t) do
        if not groups[t] then
          groups[t] = {}
          order[#order + 1] = t
        end
        table.insert(groups[t], x)
      end
    end
    table.sort(order)
    for _, t in ipairs(order) do
      section('#' .. t, groups[t], true)
    end
    section('Untagged', untagged, true)
  else
    local groups, order = {}, {}
    for _, x in ipairs(placed) do
      local v = x.annotation.values[1]
      local k = v.set .. '/' .. v.label .. (v.choice and ('/' .. v.choice) or '')
      if not groups[k] then
        groups[k] = { title = ('%s (%s·%s)'):format(buffer.display_name(buf, v), v.set, v.label), xs = {} }
        order[#order + 1] = k
      end
      table.insert(groups[k].xs, x)
    end
    for _, k in ipairs(order) do
      section(groups[k].title, groups[k].xs, false)
    end
  end
  if opts.include_detached and #detached > 0 then
    out[#out + 1] = '## Detached'
    for _, x in ipairs(detached) do
      local a = x.annotation
      local parts = { ('"%s"'):format(one_line(a.original_quote)), buffer.display_name(buf, a.values[1]) }
      if a.note then parts[#parts + 1] = one_line(a.note:match('[^\n]*')) end
      out[#out + 1] = '- ' .. table.concat(parts, ' — ')
    end
    out[#out + 1] = ''
  end
  while out[#out] == '' do
    out[#out] = nil
  end
  return out
end

--- Where an export of `buf` goes by default.
function M.default_path(buf)
  local doc = store.doc(buf)
  if doc and doc.kind == 'file' and doc.root then
    local rel = doc.key:gsub('/', '-'):gsub('%.[^.]*$', '')
    return ('%s/.earmark/export/%s-%s.md'):format(doc.root, vim.fn.fnamemodify(doc.root, ':t'), rel)
  end
  local name = api.nvim_buf_get_name(buf)
  local base = name ~= '' and vim.fn.fnamemodify(name, ':t:r') or ('scratch-' .. os.date('%Y%m%d-%H%M%S'))
  return ('%s/export/%s.md'):format(config.options.storage_dir, base)
end

--- `<leader>me`: ask for a file name, write the export there and open it in a split.
function M.run(buf)
  if buf == 0 then buf = api.nvim_get_current_buf() end
  local n = #buffer.list(buf)
  if n == 0 then return vim.notify('earmark: no annotations') end
  vim.ui.input({ prompt = 'Export to: ', default = M.default_path(buf), completion = 'file' }, function(path)
    if not path or vim.trim(path) == '' then return end
    path = vim.fs.normalize(vim.fn.fnamemodify(vim.trim(path), ':p'))
    vim.fn.mkdir(vim.fs.dirname(path), 'p')
    local ok, err = pcall(vim.fn.writefile, M.markdown(buf), path)
    if not ok then
      return vim.notify('earmark: could not write ' .. path .. ': ' .. tostring(err), vim.log.levels.ERROR)
    end
    local open = vim.fn.bufnr(path)
    local win = open > 0 and vim.fn.bufwinid(open) or -1
    if win > 0 then
      api.nvim_set_current_win(win)
    else
      vim.cmd('vsplit ' .. vim.fn.fnameescape(path))
    end
    -- an export opened earlier: show what was just written
    if open > 0 and not vim.bo.modified then vim.cmd('silent edit!') end
    vim.notify(('earmark: exported %d to %s'):format(n, vim.fn.fnamemodify(path, ':~:.')))
  end)
end

return M
