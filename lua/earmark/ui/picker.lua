-- One picker interface over snacks.nvim, telescope.nvim and vim.ui.select (`picker =
-- 'auto'` tries them in that order). Items are plain tables:
--   { text = 'shown and searched', file = path?, buf = bufnr?, pos = {row, col}? (0-based),
--     end_pos = {row, col}?, annotation = {...}?, ... }
-- plus the annotation lists earmark feeds it and the query grammar used to narrow them.
local buffer = require('earmark.buffer')
local config = require('earmark.config')
local log = require('earmark.log')
local sets = require('earmark.sets')
local store = require('earmark.store')
local tags = require('earmark.tags')

local api = vim.api
local M = {}

---------------------------------------------------------------------------
-- Backends
---------------------------------------------------------------------------

local function snacks(items, opts)
  local ok, Snacks = pcall(require, 'snacks')
  if not ok or not Snacks.picker then return false end
  local list = {}
  for i, it in ipairs(items) do
    list[i] = {
      idx = i,
      text = it.text,
      file = it.file,
      buf = it.buf,
      pos = it.pos and { it.pos[1] + 1, it.pos[2] } or nil,
      end_pos = it.end_pos and { it.end_pos[1] + 1, it.end_pos[2] } or nil,
      item = it,
    }
  end
  Snacks.picker.pick({
    title = opts.prompt,
    items = list,
    format = function(item)
      return { { item.text } }
    end,
    preview = (opts.preview ~= false) and 'file' or 'none',
    confirm = function(picker, item)
      picker:close()
      if item then vim.schedule(function() opts.on_choice(item.item) end) end
    end,
  })
  return true
end

local function telescope(items, opts)
  local ok = pcall(require, 'telescope')
  if not ok then return false end
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local state = require('telescope.actions.state')
  pickers
    .new({}, {
      prompt_title = opts.prompt,
      finder = finders.new_table({
        results = items,
        entry_maker = function(it)
          return {
            value = it,
            display = it.text,
            ordinal = it.text,
            filename = it.file,
            bufnr = it.buf,
            lnum = it.pos and it.pos[1] + 1 or nil,
            col = it.pos and it.pos[2] + 1 or nil,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      previewer = (opts.preview ~= false) and conf.grep_previewer({}) or nil,
      attach_mappings = function(prompt_buf)
        actions.select_default:replace(function()
          local entry = state.get_selected_entry()
          actions.close(prompt_buf)
          if entry then vim.schedule(function() opts.on_choice(entry.value) end) end
        end)
        return true
      end,
    })
    :find()
  return true
end

local function select(items, opts)
  vim.ui.select(items, {
    prompt = opts.prompt,
    kind = 'earmark',
    format_item = function(it)
      return it.text
    end,
  }, function(choice)
    if choice then opts.on_choice(choice) end
  end)
  return true
end

M.backends = { snacks = snacks, telescope = telescope, select = select }

--- Let the user pick one of `items`; opts = { prompt, on_choice(item), preview = bool }.
function M.pick(items, opts)
  if #items == 0 then
    vim.notify('earmark: ' .. (opts.empty or 'no annotations'))
    return
  end
  local want = config.options.picker
  local order = want == 'auto' and { 'snacks', 'telescope', 'select' } or { want, 'select' }
  for _, name in ipairs(order) do
    local fn = M.backends[name]
    if fn then
      local ok, res = pcall(fn, items, opts)
      if ok and res then return name end
      if not ok then log.warn('picker %s failed: %s', name, res) end
    end
  end
end

---------------------------------------------------------------------------
-- Annotation items
---------------------------------------------------------------------------

local function one_line(s, max)
  s = (s or ''):gsub('%s+', ' ')
  if max and vim.fn.strchars(s) > max then s = vim.fn.strcharpart(s, 0, max - 1) .. '…' end
  return s
end

--- Display text for an annotation: name, quote, tags, note.
local function describe(a, display_name, where)
  local parts = {}
  if where then parts[#parts + 1] = where end
  local names = {}
  for _, v in ipairs(a.values) do
    names[#names + 1] = display_name(v)
  end
  parts[#parts + 1] = table.concat(names, ' + ')
  parts[#parts + 1] = '"' .. one_line(a.quote, 50) .. '"'
  if a.status ~= 'ok' then parts[#parts + 1] = '[' .. a.status .. ']' end
  local list, idents = tags.of(a)
  if #list > 0 then parts[#parts + 1] = table.concat(vim.tbl_map(function(t) return '#' .. t end, list), ' ') end
  if #idents > 0 then parts[#parts + 1] = table.concat(vim.tbl_map(function(t) return '@' .. t end, idents), ' ') end
  if a.note then parts[#parts + 1] = '✎ ' .. one_line(a.note:match('[^\n]*'), 40) end
  return table.concat(parts, '  ')
end

--- Picker items for the annotations of a loaded buffer.
function M.doc_items(buf)
  if buf == 0 then buf = api.nvim_get_current_buf() end
  local file = api.nvim_buf_get_name(buf)
  file = file ~= '' and file or nil
  local items = {}
  for _, x in ipairs(buffer.list(buf)) do
    local a = x.annotation
    local where = x.s and ('%d:%d'):format(x.s[1] + 1, x.s[2] + 1) or 'detached'
    items[#items + 1] = {
      text = describe(a, function(v) return buffer.display_name(buf, v) end, where),
      buf = buf,
      file = file,
      pos = x.s,
      end_pos = x.e,
      annotation = a,
      names = buffer.names(buf),
    }
  end
  return items
end

--- Every record under a project root: { { key, file, record } ... }.
function M.records(root)
  local dir = root .. '/.earmark/docs'
  local out = {}
  for _, path in ipairs(vim.fn.globpath(dir, '**/*.json', false, true)) do
    local rec = store.read(path)
    if rec and rec.annotations then
      local key = vim.fs.relpath(dir, path):gsub('%.json$', '')
      out[#out + 1] = { key = key, file = root .. '/' .. key, record = rec }
    end
  end
  table.sort(out, function(x, y) return x.key < y.key end)
  return out
end

--- Picker items for every annotation in the project of `buf` (loaded buffers live, others
--- from their records).
function M.project_items(buf)
  if buf == 0 then buf = api.nvim_get_current_buf() end
  local doc = store.doc(buf)
  if not doc or not doc.root then return M.doc_items(buf) end
  for b in pairs(buffer.state) do
    buffer.save(b) -- records on disk match what's on screen
  end
  local loaded = {}
  for b, S in pairs(buffer.state) do
    if S.doc.root == doc.root then loaded[S.doc.key] = b end
  end
  local items = {}
  for _, r in ipairs(M.records(doc.root)) do
    local b = loaded[r.key]
    if b then
      for _, it in ipairs(M.doc_items(b)) do
        it.text = r.key .. ':' .. it.text
        items[#items + 1] = it
      end
    else
      local names = r.record.names or {}
      local function display(v)
        local n = names[v.set .. '/' .. v.label]
        if n then return n end
        local l = sets.label(v)
        return l and l.name or v.label
      end
      for _, a in ipairs(r.record.annotations) do
        a.status = a.status or 'ok'
        local where = a.s and ('%d:%d'):format(a.s[1] + 1, a.s[2] + 1) or 'detached'
        items[#items + 1] = {
          text = describe(a, display, r.key .. ':' .. where),
          file = r.file,
          pos = a.status ~= 'detached' and a.s or nil,
          end_pos = a.e,
          annotation = a,
          names = names,
        }
      end
    end
  end
  return items
end

---------------------------------------------------------------------------
-- Query grammar: #tag  @ident  label:3  set:vivid  status:stale  has:note  free text
---------------------------------------------------------------------------

function M.parse_query(q)
  local f = { tags = {}, idents = {}, text = {} }
  for word in (q or ''):gmatch('%S+') do
    local k, v = word:match('^(%a+):(.+)$')
    if word:sub(1, 1) == '#' and #word > 1 then
      f.tags[#f.tags + 1] = word:sub(2):lower()
    elseif word:sub(1, 1) == '@' and #word > 1 then
      f.idents[#f.idents + 1] = word:sub(2):lower()
    elseif k == 'label' or k == 'set' or k == 'status' or k == 'has' then
      f[k] = v:lower()
    else
      f.text[#f.text + 1] = word:lower()
    end
  end
  return f
end

local function matches(it, f)
  local a = it.annotation
  if not a then return false end
  if f.status and (a.status or 'ok') ~= f.status then return false end
  if f.has == 'note' and not a.note then return false end
  if f.has == 'tags' and #tags.of(a) == 0 then return false end
  if f.set or f.label then
    local hit = false
    for _, v in ipairs(a.values) do
      local name = (it.names and it.names[v.set .. '/' .. v.label]) or ''
      if (not f.set or v.set:lower() == f.set)
        and (not f.label or v.label:lower() == f.label or name:lower() == f.label) then
        hit = true
      end
    end
    if not hit then return false end
  end
  if #f.tags > 0 or #f.idents > 0 then
    local list, idents = tags.of(a)
    local have = {}
    for _, t in ipairs(list) do have['#' .. t:lower()] = true end
    for _, t in ipairs(idents) do have['@' .. t:lower()] = true end
    for _, t in ipairs(f.tags) do
      if not have['#' .. t] then return false end
    end
    for _, t in ipairs(f.idents) do
      if not have['@' .. t] then return false end
    end
  end
  if #f.text > 0 then
    local hay = (it.text .. ' ' .. (a.note or '') .. ' ' .. (a.original_quote or '')):lower()
    for _, w in ipairs(f.text) do
      if not hay:find(w, 1, true) then return false end
    end
  end
  return true
end

--- Items matching a query string.
function M.filter(items, query)
  if not query or not query:match('%S') then return items end
  local f = M.parse_query(query)
  return vim.tbl_filter(function(it) return matches(it, f) end, items)
end

---------------------------------------------------------------------------
-- Going to an item
---------------------------------------------------------------------------

--- Open the item's file/buffer and put the cursor on the annotation.
function M.jump_to(it)
  if it.buf and api.nvim_buf_is_valid(it.buf) then
    if api.nvim_get_current_buf() ~= it.buf then api.nvim_set_current_buf(it.buf) end
  elseif it.file then
    vim.cmd('edit ' .. vim.fn.fnameescape(it.file))
  end
  local a = it.annotation
  local buf = api.nvim_get_current_buf()
  local S = buffer.state[buf]
  -- a loaded buffer knows where the annotation is now
  local s = (a and S and S.annos[a.id] and buffer.live_pos(buf, S, a.id)) or it.pos
  if not s then
    vim.notify('earmark: that annotation is detached (its text was not found); :Earmark review lists it')
    return
  end
  vim.cmd("normal! m'")
  pcall(api.nvim_win_set_cursor, 0, { s[1] + 1, s[2] })
  vim.cmd('normal! zv')
end

return M
