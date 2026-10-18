-- The hover: a small float next to the annotation under the cursor showing its label name,
-- tags, status and note. It appears shortly after the cursor settles on an annotation worth
-- showing (named, noted or tagged, by default), stays while the cursor moves within the
-- same annotations, and never takes focus unless asked (`<leader>mi`).
local anchor = require('earmark.anchor')
local buffer = require('earmark.buffer')
local config = require('earmark.config')
local place = require('earmark.ui.place')
local sets = require('earmark.sets')
local tags = require('earmark.tags')

local api = vim.api
local M = {}

M.ns = api.nvim_create_namespace('earmark_hover')

--- The shown hover: { win, buf, src_win, src_buf, key, row, focused }, or nil.
M.shown = nil

local timer

local function opts_()
  return config.options.hover
end

local function nerd()
  return vim.g.have_nerd_font ~= false
end

local function busy()
  local ok_p, prompt = pcall(require, 'earmark.ui.prompt')
  local ok_n, note = pcall(require, 'earmark.ui.note')
  return (ok_p and prompt.active) or (ok_n and note.active)
end

local function cursor_pos(win)
  local c = api.nvim_win_get_cursor(win)
  return { c[1] - 1, c[2] }
end

--- Whether a hit is worth showing on its own (hover.show_when = 'named_or_note').
local function interesting(buf, a)
  if opts_().show_when == 'always' then return true end
  if a.note or (a.tags and #a.tags > 0) or a.status ~= 'ok' then return true end
  local v = a.values[1]
  local name = buffer.display_name(buf, v)
  return name ~= v.label or #a.values > 1
end

local CIRCLED = { '①', '②', '③', '④', '⑤', '⑥', '⑦', '⑧', '⑨' }

--- Lines and highlights for hits (innermost first).
--- Returns lines, marks = { {row, col_start, col_end, group} ... }.
function M.content(buf, hits)
  local S = buffer.state[buf]
  local lines, marks = {}, {}
  local function hl(row, s, e, group)
    marks[#marks + 1] = { row, s, e, group }
  end
  for i, h in ipairs(hits) do
    local a = h.a
    if i > 1 then lines[#lines + 1] = '' end
    local row = #lines
    local parts = {} -- { text, group }
    if #hits > 1 then parts[#parts + 1] = { (CIRCLED[i] or (i .. '.')) .. ' ' } end
    for k, v in ipairs(a.values) do
      local hex = sets.color(v, S and S.colors)
      local g = hex and sets.fg_group(hex, true) or 'EarmarkUnknown'
      if k > 1 then parts[#parts + 1] = { '  + ' } end
      parts[#parts + 1] = { (nerd() and '▍' or '|') .. buffer.display_name(buf, v), g }
      local cname = sets.color_name(v, S and S.colors)
      parts[#parts + 1] = { '  ' .. v.set .. '·' .. v.label .. (cname and (' · ' .. cname) or ''), 'Comment' }
    end
    local hex1 = sets.color(a.values[1], S and S.colors)
    local fg1 = hex1 and sets.fg_group(hex1) or 'Normal'
    local tag_list, idents = tags.of(a)
    if #tag_list > 0 then
      parts[#parts + 1] = { '  ' .. table.concat(vim.tbl_map(function(t) return '#' .. t end, tag_list), ' '), fg1 }
    end
    if #idents > 0 then
      -- written as in the note: Markdown concealing would eat "[A]" brackets here
      parts[#parts + 1] = { '  ' .. table.concat(vim.tbl_map(function(t) return '@' .. t end, idents), ' '), fg1 }
    end
    if a.note then parts[#parts + 1] = { '  ' .. (nerd() and '✎' or '*'), fg1 } end
    if a.zk then
      parts[#parts + 1] = { '  ' .. (nerd() and '↗' or '^') .. ' zk ' .. vim.fn.fnamemodify(a.zk, ':t:r'), 'Comment' }
    end
    if a.status == 'stale' then
      local pct = math.floor(anchor.similarity(a.quote or '', a.original_quote or '') * 100 + 0.5)
      parts[#parts + 1] = { ('  ~ stale (%d%%)'):format(pct), 'DiagnosticWarn' }
    elseif a.status == 'ambiguous' then
      parts[#parts + 1] = { '  ? ambiguous', 'DiagnosticInfo' }
    end
    local line, col = '', 0
    for _, p in ipairs(parts) do
      line = line .. p[1]
      if p[2] then hl(row, col, col + #p[1], p[2]) end
      col = col + #p[1]
    end
    lines[#lines + 1] = line
    for _, v in ipairs(a.values) do
      if v.text then
        lines[#lines + 1] = '› ' .. v.text
        hl(#lines - 1, 0, #'›', fg1)
      end
    end
    if a.status == 'stale' and a.original_quote ~= a.quote then
      local q = (a.original_quote or ''):gsub('%s+', ' ')
      if vim.fn.strchars(q) > 60 then q = vim.fn.strcharpart(q, 0, 59) .. '…' end
      lines[#lines + 1] = 'was: "' .. q .. '"'
      hl(#lines - 1, 0, #lines[#lines], 'Comment')
    end
    if a.note then
      for _, l in ipairs(vim.split(a.note, '\n')) do
        lines[#lines + 1] = l
      end
    end
  end
  return lines, marks
end

--- Close the hover.
function M.hide()
  local H = M.shown
  M.shown = nil
  if timer then timer:stop() end
  if not H then return end
  pcall(api.nvim_del_augroup_by_name, 'earmark_hover_float')
  if api.nvim_win_is_valid(H.win) then pcall(api.nvim_win_close, H.win, true) end
  if api.nvim_buf_is_valid(H.buf) then pcall(api.nvim_buf_delete, H.buf, { force = true }) end
end

local function key_of(hits)
  return table.concat(vim.tbl_map(function(h) return h.a.id .. ':' .. (h.a.updated or 0) end, hits), ',')
end

local function config_for(src_win, hits, lines, focus)
  local o = opts_()
  local H, W = api.nvim_win_get_height(src_win), api.nvim_win_get_width(src_win)
  local longest = 0
  for _, l in ipairs(lines) do
    longest = math.max(longest, vim.fn.strdisplaywidth(l))
  end
  local maxw = math.max(20, math.floor(W * o.max_width))
  local w = math.max(math.min(20, maxw), math.min(longest + 2, maxw))
  -- wrapped lines take more rows
  local rows = 0
  for _, l in ipairs(lines) do
    rows = rows + math.max(1, math.ceil(vim.fn.strdisplaywidth(l) / w))
  end
  local h = math.max(1, math.min(rows, math.floor(H * o.max_height)))
  -- below (or above) every annotation listed, so it never covers one of them
  local s, e = hits[1].s, hits[1].e
  for _, x in ipairs(hits) do
    if x.s[1] < s[1] or (x.s[1] == s[1] and x.s[2] < s[2]) then s = x.s end
    if x.e[1] > e[1] or (x.e[1] == e[1] and x.e[2] > e[2]) then e = x.e end
  end
  local cfg = place.for_span(src_win, s, e, w, h, { bordered = true, min_h = math.min(h, 3) })
  cfg.side = nil
  cfg.zindex = 45
  cfg.focusable = focus or false
  cfg.style = 'minimal'
  cfg.border = config.options.ui.border
  cfg.noautocmd = true
  return cfg
end

--- Show the hover for `hits` in `src_win` (replacing any shown one).
function M.show(src_win, hits, focus)
  local src_buf = api.nvim_win_get_buf(src_win)
  local lines, marks = M.content(src_buf, hits)
  local key = key_of(hits)
  local row = api.nvim_win_get_cursor(src_win)[1]
  local H = M.shown
  if H and not focus and H.key == key and H.src_win == src_win and api.nvim_win_is_valid(H.win) then
    if H.row ~= row then
      H.row = row
      local cfg = config_for(src_win, hits, lines, false)
      cfg.noautocmd, cfg.style = nil, nil
      pcall(api.nvim_win_set_config, H.win, cfg)
    end
    return H
  end
  M.hide()
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  for _, m in ipairs(marks) do
    pcall(api.nvim_buf_set_extmark, buf, M.ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
  end
  vim.bo[buf].modifiable = false
  local win = api.nvim_open_win(buf, false, config_for(src_win, hits, lines, focus))
  vim.wo[win].wrap, vim.wo[win].linebreak = true, true
  local S = buffer.state[src_buf]
  local hex = sets.color(hits[1].a.values[1], S and S.colors)
  if hex then vim.wo[win].winhighlight = 'Normal:NormalFloat,FloatBorder:' .. sets.fg_group(hex) end
  if hits[1].a.note or (hits[2] and hits[2].a.note) then
    pcall(vim.treesitter.start, buf, 'markdown')
    vim.wo[win].conceallevel = 2
  end
  M.shown = { win = win, buf = buf, src_win = src_win, src_buf = src_buf, key = key, row = row, focused = focus }
  if focus then
    api.nvim_set_current_win(win)
    for _, lhs in ipairs({ 'q', '<Esc>' }) do
      vim.keymap.set('n', lhs, M.hide, { buffer = buf, nowait = true, desc = 'earmark: close' })
    end
    local group = api.nvim_create_augroup('earmark_hover_float', { clear = true })
    api.nvim_create_autocmd('WinLeave', {
      group = group,
      buffer = buf,
      callback = function()
        vim.schedule(M.hide)
      end,
    })
  end
  return M.shown
end

--- Hits under the cursor of `win` worth an automatic hover (all of them if any is).
local function auto_hits(win)
  local buf = api.nvim_win_get_buf(win)
  if not buffer.state[buf] then return {} end
  local hits = buffer.find(buf, cursor_pos(win))
  for _, h in ipairs(hits) do
    if interesting(buf, h.a) then return hits end
  end
  return {}
end

--- The cursor settled: show, keep, move or hide the hover.
function M.update()
  local win = api.nvim_get_current_win()
  if M.shown and M.shown.focused then return end
  if not opts_().auto or busy() or api.nvim_get_mode().mode ~= 'n' then return M.hide() end
  if api.nvim_win_get_config(win).relative ~= '' then return end
  local hits = auto_hits(win)
  if #hits == 0 then return M.hide() end
  M.show(win, hits, false)
end

--- CursorMoved: hide at once when the cursor left the shown annotations, then debounce.
function M.on_cursor_moved()
  local H = M.shown
  local win = api.nvim_get_current_win()
  if H and not H.focused then
    local buf = api.nvim_win_get_buf(win)
    local hits = (win == H.src_win) and buffer.find(buf, cursor_pos(win)) or {}
    if key_of(hits) ~= H.key then
      M.hide()
    elseif H.row ~= api.nvim_win_get_cursor(win)[1] then
      M.show(win, hits, false) -- same annotations, new row: re-place
    end
  end
  if not opts_().auto or not buffer.state[api.nvim_get_current_buf()] then return end
  timer = timer or vim.uv.new_timer()
  timer:stop()
  timer:start(opts_().delay, 0, vim.schedule_wrap(function()
    require('earmark.log').guard('hover', M.update)
  end))
end

--- `<leader>mi`: show the hover for everything under the cursor now and enter it; pressed
--- again (while it's shown), focus it.
function M.peek(count)
  local win = api.nvim_get_current_win()
  local buf = api.nvim_get_current_buf()
  local hits = buffer.find(buf, cursor_pos(win))
  if #hits == 0 then
    vim.notify('earmark: nothing under the cursor')
    return
  end
  if count and count > 0 then hits = { hits[math.min(count, #hits)] } end
  M.show(win, hits, true)
end

function M.toggle()
  local o = opts_()
  o.auto = not o.auto
  if not o.auto then M.hide() end
  vim.notify('earmark: hover ' .. (o.auto and 'on' or 'off'))
end

--- Autocmds that hide the hover (Insert mode, scrolling, leaving, Visual/op-pending).
function M.setup(au)
  au('CursorMoved', function()
    place.track()
    M.on_cursor_moved()
  end)
  au({ 'InsertEnter', 'BufLeave' }, function()
    if M.shown and not M.shown.focused then M.hide() end
  end)
  au('WinScrolled', function()
    local H = M.shown
    if not H or H.focused then return end
    local ev = vim.v.event[tostring(H.src_win)]
    if ev and (ev.topline ~= 0 or ev.leftcol ~= 0) then M.hide() end
  end)
  au('ModeChanged', function()
    if M.shown and not M.shown.focused then M.hide() end
  end, { pattern = { '*:no*', '*:[vV\22]*' } })
  au('ModeChanged', function()
    M.on_cursor_moved()
  end, { pattern = 'no*:n' })
end

return M
