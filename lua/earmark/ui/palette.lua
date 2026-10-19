-- The palette (`<leader>mc`): every label of a set as a large colour patch, drawn exactly as
-- annotated text looks, with your name for it in this file, its colour's name, hex and how
-- often it's used here. <CR> makes it the label `gh` offers first (and the statusline
-- shows); digits jump to a key; r names it; <Tab>/<S-Tab> switch sets.
local buffer = require('earmark.buffer')
local config = require('earmark.config')
local sets = require('earmark.sets')

local api = vim.api
local M = {}

M.ns = api.nvim_create_namespace('earmark_palette')

--- The open palette's state, or nil: { buf, win, src_buf, set, labels, jump, timer }.
M.active = nil

local PATCH = 7 -- columns of each colour patch

local function pad(s, w)
  return s .. string.rep(' ', math.max(0, w - vim.fn.strdisplaywidth(s)))
end

local function uses_in(buf)
  local uses = {}
  for _, x in ipairs(buffer.list(buf)) do
    local v = x.annotation.values[1]
    if v then uses[v.set .. '/' .. v.label] = (uses[v.set .. '/' .. v.label] or 0) + 1 end
  end
  return uses
end

--- Lines and highlights for set `set_name`; returns lines, marks { row, s, e, group }.
local function build(P)
  local set = sets.by_name[P.set]
  local S = buffer.state[P.src_buf]
  local colors = S and S.colors
  local uses = uses_in(P.src_buf)
  local current = require('earmark').next_value()
  local rows, namew, cnamew = {}, 0, 0
  for _, l in ipairs(set.labels) do
    local value = { set = P.set, label = l.key }
    local name = buffer.display_name(P.src_buf, value)
    local r = {
      l = l,
      value = value,
      name = name ~= l.key and name or '',
      cname = sets.color_name(value, colors) or '',
      hex = sets.color(value, colors) or '',
      n = uses[P.set .. '/' .. l.key] or 0,
      current = current and current.set == P.set and current.label == l.key,
    }
    namew = math.max(namew, vim.fn.strdisplaywidth(r.name))
    cnamew = math.max(cnamew, vim.fn.strdisplaywidth(r.cname))
    rows[#rows + 1] = r
  end
  local lines, marks = {}, {}
  for i, r in ipairs(rows) do
    local key = r.l.key
    local left = math.floor((PATCH - vim.fn.strdisplaywidth(key)) / 2)
    local patch = string.rep(' ', left) .. key .. string.rep(' ', PATCH - left - vim.fn.strdisplaywidth(key))
    local head = (r.current and '▸' or ' ') .. ' '
    local line = head .. patch .. '  '
    local ps = #head
    marks[#marks + 1] = { i - 1, ps, ps + #patch, sets.group(r.value, colors) }
    local ns = #line
    line = line .. pad(r.name, namew) .. (namew > 0 and '  ' or '')
    if r.name ~= '' then marks[#marks + 1] = { i - 1, ns, ns + #r.name, 'Normal' } end
    local cs = #line
    line = line .. pad(r.cname, cnamew) .. '  '
    marks[#marks + 1] = { i - 1, cs, cs + #r.cname, r.hex ~= '' and sets.fg_group(r.hex) or 'Comment' }
    local hs = #line
    line = line .. r.hex .. (r.n > 0 and ('  used %d×'):format(r.n) or '')
    marks[#marks + 1] = { i - 1, hs, #line, 'Comment' }
    if r.current then marks[#marks + 1] = { i - 1, 0, #head, 'Special' } end
    lines[i] = line
  end
  P.labels = rows
  return lines, marks
end

local function render(P)
  local lines, marks = build(P)
  vim.bo[P.buf].modifiable = true
  api.nvim_buf_set_lines(P.buf, 0, -1, false, lines)
  vim.bo[P.buf].modifiable = false
  api.nvim_buf_clear_namespace(P.buf, M.ns, 0, -1)
  for _, m in ipairs(marks) do
    api.nvim_buf_set_extmark(P.buf, M.ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
  end
  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  width = math.min(math.max(width + 1, 40), vim.o.columns - 4)
  local height = math.min(#lines, math.max(3, vim.o.lines - 8))
  local cfg = {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    title = (' %s · %d labels '):format(P.set, #lines),
    title_pos = 'center',
    footer = ' <CR> use  digits jump  r name  <Tab> set  q close ',
    footer_pos = 'center',
  }
  if P.win and api.nvim_win_is_valid(P.win) then
    api.nvim_win_set_config(P.win, cfg)
  else
    cfg.style, cfg.border, cfg.zindex = 'minimal', config.options.ui.border, 60
    P.win = api.nvim_open_win(P.buf, true, cfg)
    vim.wo[P.win].cursorline = true
    vim.wo[P.win].wrap = false
  end
end

local function row_of(P, key)
  for i, r in ipairs(P.labels) do
    if r.l.key == key then return i end
  end
end

local function selected(P)
  return P.labels[api.nvim_win_get_cursor(P.win)[1]]
end

function M.close()
  local P = M.active
  if not P then return end
  M.active = nil
  if P.timer then P.timer:close() end
  if P.win and api.nvim_win_is_valid(P.win) then api.nvim_win_close(P.win, true) end
end

local function switch(P, step)
  local list = sets.list(P.src_buf)
  if #list == 0 then return end
  local idx = 1
  for i, n in ipairs(list) do
    if n == P.set then idx = i end
  end
  P.set = list[((idx - 1 + step) % #list) + 1]
  render(P)
  api.nvim_win_set_cursor(P.win, { 1, 0 })
end

local function keymaps(P)
  local function map(lhs, fn)
    vim.keymap.set('n', lhs, fn, { buffer = P.buf, nowait = true, silent = true })
  end
  map('q', M.close)
  map('<Esc>', M.close)
  map('<CR>', function()
    local r = selected(P)
    if not r then return end
    M.close()
    require('earmark').use_value(r.value)
  end)
  map('r', function()
    local r = selected(P)
    if not r then return end
    local cur = r.name
    vim.ui.input({ prompt = ('Name for %s·%s in this file: '):format(P.set, r.l.key), default = cur }, function(name)
      if name == nil then return end
      require('earmark').rename_label(P.src_buf, r.value, vim.trim(name) ~= '' and vim.trim(name) or nil)
      -- an input in its own float (snacks, dressing) closed the palette: the name still counts
      if M.active ~= P or not api.nvim_win_is_valid(P.win) then return end
      local row = api.nvim_win_get_cursor(P.win)[1]
      render(P)
      api.nvim_win_set_cursor(P.win, { row, 0 })
    end)
  end)
  map('<Tab>', function()
    switch(P, 1)
  end)
  map('<S-Tab>', function()
    switch(P, -1)
  end)
  -- digits: jump to that key ("2" then "3" within a moment goes to 23)
  for d = 0, 9 do
    map(tostring(d), function()
      P.jump = (P.jump or '') .. d
      local row = row_of(P, P.jump) or row_of(P, tostring(d))
      if not row_of(P, P.jump) then P.jump = tostring(d) end
      if row then api.nvim_win_set_cursor(P.win, { row, 0 }) end
      P.timer = P.timer or vim.uv.new_timer()
      P.timer:stop()
      P.timer:start(800, 0, function()
        P.jump = nil
      end)
    end)
  end
  api.nvim_create_autocmd({ 'WinLeave', 'BufLeave' }, {
    buffer = P.buf,
    once = true,
    callback = function()
      vim.schedule(function()
        if M.active == P then M.close() end
      end)
    end,
  })
end

--- Open the palette for `set_name` (default: the current set).
function M.open(set_name)
  M.close()
  if require('earmark.ui.place').in_cmdwin() then return end
  local src = api.nvim_get_current_buf()
  set_name = set_name or sets.current
  if not sets.by_name[set_name] then return end
  local P = { src_buf = src, set = set_name, buf = api.nvim_create_buf(false, true) }
  vim.b[P.buf].earmark_ui = true -- never annotated (store.doc)
  vim.bo[P.buf].bufhidden = 'wipe'
  vim.bo[P.buf].filetype = 'earmark_palette'
  M.active = P
  render(P)
  local cur = require('earmark').next_value()
  local row = cur and cur.set == set_name and row_of(P, cur.label) or 1
  api.nvim_win_set_cursor(P.win, { row, 0 })
  keymaps(P)
  return P
end

return M
