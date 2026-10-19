-- `<leader>mt`: add or remove tags of an annotation without typing them into its note.
-- A list of every tag you have used (most used first), toggled one at a time with
-- `vim.ui.select` (so it looks like whatever picker you use for that), until "done".
local buffer = require('earmark.buffer')
local tags = require('earmark.tags')

local M = {}

local function clean(t)
  t = vim.trim(t or ''):gsub('^#+', ''):gsub('%s+', '-')
  return t
end

--- Open the tag list for annotation `id` of `buf`.
function M.open(buf, id)
  if buf == 0 then buf = vim.api.nvim_get_current_buf() end
  local a = buffer.annotation(buf, id)
  if not a then return end
  local explicit, from_note = {}, {}
  for _, t in ipairs(a.tags or {}) do
    explicit[t] = true
  end
  for _, t in ipairs(tags.parse(a.note).tags) do
    from_note[t] = true
  end
  local counts, order = {}, {}
  local function add(name, n)
    if not counts[name] then order[#order + 1] = name end
    counts[name] = math.max(counts[name] or 0, n or 0)
  end
  for _, t in ipairs(a.tags or {}) do
    add(t)
  end
  for t in pairs(from_note) do
    add(t)
  end
  -- the tags its label set suggests (and the current set's), before the ones used before
  local sets = require('earmark.sets')
  local seen_set = {}
  for _, name in ipairs({ a.values[1] and a.values[1].set, sets.current }) do
    local set = name and not seen_set[name] and sets.by_name[name]
    if set then
      seen_set[name] = true
      for _, t in ipairs(set.tags or {}) do
        add(t)
      end
    end
  end
  for _, k in ipairs(tags.known()) do
    add(k.name, k.count)
  end
  for t, n in pairs(buffer.all_tags(buf)) do
    add(t, n)
  end
  local items = { { kind = 'new' } }
  for _, name in ipairs(order) do
    items[#items + 1] = { kind = 'tag', name = name }
  end
  items[#items + 1] = { kind = 'done' }
  local quote = (a.quote or ''):gsub('%s+', ' ')
  if vim.fn.strchars(quote) > 30 then quote = vim.fn.strcharpart(quote, 0, 29) .. '…' end

  local function set(list)
    buffer.set_tags(buf, id, list)
    vim.schedule(function()
      M.open(buf, id)
    end)
  end

  vim.ui.select(items, {
    prompt = ('Tags of "%s"'):format(quote),
    kind = 'earmark_tags',
    format_item = function(it)
      if it.kind == 'new' then return '+ new tag…' end
      if it.kind == 'done' then return '  done' end
      local mark = explicit[it.name] and '✓' or (from_note[it.name] and '✎' or ' ')
      local n = counts[it.name] or 0
      return ('%s #%s%s'):format(mark, it.name, n > 0 and ('  (' .. n .. ')') or '')
    end,
  }, function(choice)
    if not choice or choice.kind == 'done' then return end
    local list = vim.list_slice(a.tags or {})
    if choice.kind == 'new' then
      vim.schedule(function()
        vim.ui.input({ prompt = 'New tag: #' }, function(input)
          local t = clean(input)
          if t == '' then return M.open(buf, id) end
          if not explicit[t] then list[#list + 1] = t end
          set(list)
        end)
      end)
      return
    end
    local name = choice.name
    if explicit[name] then
      list = vim.tbl_filter(function(t)
        return t ~= name
      end, list)
      set(list)
    elseif from_note[name] then
      vim.notify(('earmark: "#%s" comes from the note text; edit the note to remove it'):format(name))
      vim.schedule(function()
        M.open(buf, id)
      end)
    else
      list[#list + 1] = name
      set(list)
    end
  end)
end

return M
