-- The key list (`<leader>m?`, `:Earmark help`): every earmark key, grouped by what it's for,
-- showing the keys as you configured them. <CR> on a row runs it. The same groups give
-- which-key its descriptions and icons.
local actions = require('earmark.actions')
local config = require('earmark.config')

local api = vim.api
local M = {}

M.ns = api.nvim_create_namespace('earmark_keys')

-- Rows: `a` is an action name, or a list of two shown as "a / b". `fmt` wraps the key
-- ('{count}%s{motion}'). Rows with `k` are fixed keys, not actions.
M.sections = {
  {
    title = 'Annotate',
    icon = { icon = '', color = 'yellow' },
    rows = {
      { a = 'operator', fmt = '{count}%s{motion}', text = 'annotate with label {count}: 3ghiw' },
      { a = 'operator', fmt = '%s{motion}', text = 'annotate, choosing the label in a prompt' },
      { a = 'line', fmt = '{count}%s', text = 'annotate the line' },
      { a = 'operator', fmt = '{Visual}%s', text = 'annotate the selection', mode = 'x' },
      { k = '.', text = 'repeat with the same label' },
      { a = 'occurrences', text = 'same labels on every other copy of the text' },
    },
  },
  {
    title = 'Change the annotation under the cursor',
    icon = { icon = '', color = 'orange' },
    rows = {
      { a = 'relabel', text = 'change its label' },
      { a = 'add_value', text = 'add another label' },
      { a = 'rename', text = 'name its label in this file' },
      { a = 'regrow', fmt = '%s{motion}', text = 'move it onto a motion (or a selection)' },
      { a = 'erase', text = 'erase it (Visual: all in the selection)' },
      { a = 'clear', text = 'erase all in this file', icon = { icon = '', color = 'red' } },
      { a = 'restore', text = 'bring back the last erased' },
    },
  },
  {
    title = 'Notes and tags',
    icon = { icon = '', color = 'green' },
    rows = {
      { a = 'note', text = 'open or close its note' },
      { a = 'tags', text = 'add or remove tags' },
      { a = 'peek', text = 'show its details and move into them' },
      { a = 'toggle_hover', text = 'details when the cursor stops: on / off' },
      { a = 'toggle_indicators', text = '#tags at line ends: on / off' },
    },
  },
  {
    title = 'Move',
    icon = { icon = '', color = 'blue' },
    rows = {
      { a = { 'next', 'prev' }, text = 'next / previous annotation' },
      { a = { 'next_same', 'prev_same' }, text = 'next / previous with the same label' },
      { a = 'jump', text = 'jump to one on screen' },
    },
  },
  {
    title = 'Find and review',
    icon = { icon = '', color = 'azure' },
    rows = {
      { a = 'pick', text = 'pick one in this file' },
      { a = 'pick_all', text = 'pick one in the project' },
      { a = 'qf', text = "this file's annotations in the quickfix list" },
      { a = 'review', text = 'the ones whose text changed or is gone' },
      { a = 'reanchor', fmt = '{Visual}%s', text = 'attach the one chosen in review here', mode = 'x' },
      { a = 'diff', text = 'its original text next to the current text' },
    },
  },
  {
    title = 'Label sets',
    icon = { icon = '', color = 'purple' },
    rows = {
      { a = 'cycle_set', text = 'next set' },
      { a = 'pick_set', text = 'choose a set' },
      { a = 'palette', text = "the set's colours: pick one, name one" },
    },
  },
  {
    title = 'Export and zk',
    icon = { icon = '', color = 'cyan' },
    rows = {
      { a = 'export', text = "this file's annotations as Markdown" },
      { a = 'zk', text = 'make a zk note from it, or open its note' },
      { a = 'help', text = 'this list' },
    },
  },
  {
    title = 'In the label prompt',
    rows = {
      { k = '<CR>', text = 'apply' },
      { k = '<Tab>', text = 'apply, then name the label' },
      { k = '<S-Tab>', text = 'back a step' },
      { k = '<C-n> <C-p>', text = 'move through the list' },
      { k = '<C-s>', text = 'next set' },
      { k = '<Esc>', text = 'Normal mode; again to cancel' },
    },
  },
  {
    title = 'In the palette',
    rows = {
      { k = '<CR>', text = 'offer this label first' },
      { k = '1-9', text = 'go to that key' },
      { k = 'r', text = 'name it' },
      { k = '<Tab>', text = 'next set' },
    },
  },
  {
    title = 'In a note',
    rows = {
      { k = 'q', text = 'save and close' },
      { k = '<C-s>', text = 'save' },
      { k = '<localleader>s', text = 'move to a split (f: back to a float)' },
    },
  },
  {
    title = 'Label already on that exact text',
    rows = {
      { k = 'a', text = 'add as another label' },
      { k = 'r', text = 'replace the label' },
    },
  },
}

--- `lhs` as shown: <leader> and <localleader> as their key (Space as ␣).
function M.show_key(lhs)
  local function sub(var)
    local v = vim.g[var]
    if v == nil then v = '\\' end
    return v == ' ' and '␣' or v
  end
  return (lhs:gsub('<[Ll]eader>', function() return sub('mapleader') end)
    :gsub('<[Ll]ocal[Ll]eader>', function() return sub('maplocalleader') end))
end

local function lhs_of(name)
  local keys = config.options.keys
  local lhs = keys and keys[name]
  return type(lhs) == 'string' and lhs or nil
end

--- Each row resolved: { key = shown text, text, action = name|nil, mode, unmapped = bool }.
function M.rows(section)
  local out = {}
  for _, r in ipairs(section.rows) do
    if r.k then
      out[#out + 1] = { key = M.show_key(r.k), text = r.text }
    else
      local names = type(r.a) == 'table' and r.a or { r.a }
      local shown, missing = {}, false
      for _, n in ipairs(names) do
        local lhs = lhs_of(n)
        if lhs then
          shown[#shown + 1] = (r.fmt or '%s'):format(M.show_key(lhs))
        else
          missing = true
          local a = actions.by_name[n]
          shown[#shown + 1] = a and a.cmd ~= false and (':Earmark ' .. n) or actions.plug(n)
        end
      end
      out[#out + 1] = { key = table.concat(shown, ' '), text = r.text, action = names[1], mode = r.mode or 'n', unmapped = missing }
    end
  end
  return out
end

--- Command-only actions (no mapping), as rows.
function M.command_rows()
  local out = {}
  for _, a in ipairs(actions.list) do
    if not a.modes and a.cmd ~= false then out[#out + 1] = { key = ':Earmark ' .. a.name, text = a.desc } end
  end
  return out
end

--- All sections with their rows resolved, in display order.
function M.resolved()
  local out = {}
  for _, s in ipairs(M.sections) do
    out[#out + 1] = { title = s.title, rows = M.rows(s) }
  end
  local cmds = M.command_rows()
  if #cmds > 0 then out[#out + 1] = { title = 'Commands without a key', rows = cmds } end
  return out
end

-- One block of lines per section; `cells` remembers what each line holds.
local function block(section)
  local kw = 0
  for _, r in ipairs(section.rows) do
    kw = math.max(kw, vim.fn.strdisplaywidth(r.key))
  end
  local lines = { { text = section.title, title = true } }
  for _, r in ipairs(section.rows) do
    local pad = string.rep(' ', kw - vim.fn.strdisplaywidth(r.key))
    lines[#lines + 1] = { text = '  ' .. r.key .. pad .. '  ' .. r.text, key = r.key, row = r }
  end
  lines[#lines + 1] = { text = '' }
  return lines
end

--- Lay the sections out in as many columns as fit `width` (at most `max_cols`, default 3).
--- Returns { lines = { string }, cells = { [line] = { {col, width, line_item} } }, width }.
function M.layout(width, max_cols)
  local blocks, total = {}, 0
  for _, s in ipairs(M.resolved()) do
    local b = block(s)
    blocks[#blocks + 1] = b
    total = total + #b
  end
  local gap = 4
  -- fill `n` columns in order, starting a new one once the current one holds its share
  local function split(n)
    local cols, target = { {} }, math.ceil(total / n)
    for _, b in ipairs(blocks) do
      local cur = cols[#cols]
      if #cur > 0 and #cur + #b > target and #cols < n then
        cur = {}
        cols[#cols + 1] = cur
      end
      vim.list_extend(cur, b)
    end
    local widths, sum = {}, 0
    for ci, c in ipairs(cols) do
      while #c > 0 and c[#c].text == '' do c[#c] = nil end
      widths[ci] = 0
      for _, l in ipairs(c) do
        widths[ci] = math.max(widths[ci], vim.fn.strdisplaywidth(l.text))
      end
      sum = sum + widths[ci] + (ci > 1 and gap or 0)
    end
    return cols, widths, sum
  end
  local cols, widths, used
  for n = max_cols or 3, 1, -1 do
    cols, widths, used = split(n)
    if used <= width then break end
  end
  local height = 0
  for _, c in ipairs(cols) do
    height = math.max(height, #c)
  end
  local lines, cells = {}, {}
  for i = 1, height do
    local parts, row_cells, col = {}, {}, 0
    for ci, c in ipairs(cols) do
      local item = c[i] or { text = '' }
      local text = item.text
      if ci < #cols then text = text .. string.rep(' ', widths[ci] - vim.fn.strdisplaywidth(text) + gap) end
      row_cells[#row_cells + 1] = { col = col, bytes = #item.text, item = item }
      parts[#parts + 1] = text
      col = col + #text
    end
    lines[i] = (table.concat(parts):gsub('%s+$', ''))
    cells[i] = row_cells
  end
  return { lines = lines, cells = cells, width = used }
end

M.active = nil --- @type table?

function M.close()
  local K = M.active
  M.active = nil
  if K and api.nvim_win_is_valid(K.win) then api.nvim_win_close(K.win, true) end
end

local function cell_at(K, line, col)
  local best
  for _, c in ipairs(K.layout.cells[line] or {}) do
    if col >= c.col then best = c end
  end
  return best and best.item
end

--- Run the action on the row under the cursor, in the window the list was opened from.
local function run(K)
  local pos = api.nvim_win_get_cursor(K.win)
  local item = cell_at(K, pos[1], pos[2])
  local r = item and item.row
  if not (r and r.action) then return end
  M.close()
  if api.nvim_win_is_valid(K.src_win) then api.nvim_set_current_win(K.src_win) end
  local keys = actions.plug(r.action)
  if r.mode == 'x' then keys = 'gv' .. keys end
  api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true), 'm', false)
end

local function highlight(K)
  local buf = K.buf
  api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  for i, row_cells in ipairs(K.layout.cells) do
    for _, c in ipairs(row_cells) do
      local item = c.item
      if item.title then
        api.nvim_buf_set_extmark(buf, M.ns, i - 1, c.col, { end_col = c.col + c.bytes, hl_group = 'EarmarkKeysTitle' })
      elseif item.key then
        local s = c.col + 2
        local group = item.row.unmapped and 'EarmarkKeysUnmapped' or 'EarmarkKeysKey'
        api.nvim_buf_set_extmark(buf, M.ns, i - 1, s, { end_col = s + #item.key, hl_group = group })
      end
    end
  end
end

function M.apply_highlights()
  api.nvim_set_hl(0, 'EarmarkKeysTitle', { link = 'Title', default = true })
  api.nvim_set_hl(0, 'EarmarkKeysKey', { link = 'Special', default = true })
  api.nvim_set_hl(0, 'EarmarkKeysUnmapped', { link = 'Comment', default = true })
end

--- Open the key list. opts.columns: at most this many columns (default 3).
function M.open(opts)
  opts = opts or {}
  M.close()
  M.apply_highlights()
  local max_w = vim.o.columns - 4
  local layout = M.layout(max_w, opts.columns)
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  api.nvim_buf_set_lines(buf, 0, -1, false, layout.lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = 'earmark-keys'
  local width = math.min(math.max(layout.width + 1, 40), max_w)
  local height = math.min(#layout.lines, math.max(3, vim.o.lines - 6))
  local leader = vim.g.mapleader == ' ' and ' ␣ is <leader> ' or nil
  local K = { buf = buf, layout = layout, src_win = api.nvim_get_current_win() }
  K.win = api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = config.options.ui.border,
    title = ' earmark keys ',
    title_pos = 'center',
    footer = ' <CR> run  / search  q close ' .. (leader and ('·' .. leader) or ''),
    footer_pos = 'center',
    zindex = 60,
  })
  vim.wo[K.win].wrap = false
  vim.wo[K.win].cursorline = true
  M.active = K
  highlight(K)
  local function map(lhs, fn)
    vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true, silent = true })
  end
  map('q', M.close)
  map('<Esc>', M.close)
  map('<CR>', function() run(K) end)
  api.nvim_create_autocmd('WinLeave', { buffer = buf, once = true, callback = function() vim.schedule(M.close) end })
  return K
end

--- which-key specs for every mapped key: plain descriptions and one icon per group.
function M.which_key_spec()
  local spec = {}
  local plain = {}
  for _, s in ipairs(M.sections) do
    for _, r in ipairs(s.rows) do
      local names = r.a and (type(r.a) == 'table' and r.a or { r.a }) or {}
      for _, n in ipairs(names) do
        local a = actions.by_name[n]
        if a and not plain[n] then
          plain[n] = true
          local lhs = lhs_of(n)
          if lhs and a.modes then
            local modes = vim.tbl_keys(a.modes)
            table.sort(modes)
            spec[#spec + 1] = { lhs, desc = a.desc, mode = modes, icon = vim.deepcopy(r.icon or s.icon) }
          end
        end
      end
    end
  end
  return spec
end

return M
