-- Reviewing annotations whose text changed: the list of stale, ambiguous and detached ones
-- with what to do about each, and a float comparing what was annotated with what the text
-- says now.
local buffer = require('earmark.buffer')
local compat = require('earmark.compat')
local config = require('earmark.config')
local picker = require('earmark.ui.picker')
local place = require('earmark.ui.place')

local api = vim.api
local M = {}

M.ns = api.nvim_create_namespace('earmark_diff')

--- Annotation waiting for `:Earmark reanchor` on a selection: { buf, id }.
M.pending = nil

local function notify(msg, level)
  vim.notify('earmark: ' .. msg, level)
end

---------------------------------------------------------------------------
-- Diff float
---------------------------------------------------------------------------

local function chars(s)
  return vim.fn.split(s, '\\zs')
end

--- Character ranges that differ between `a` and `b`: { a = { {s, e} ... }, b = { ... } }
--- as 0-based byte ranges, end-exclusive.
function M.char_diff(a, b)
  local ca, cb = chars(a), chars(b)
  local function offsets(cs)
    local off, o = { [1] = 0 }, 0
    for i, c in ipairs(cs) do
      o = o + #c
      off[i + 1] = o
    end
    return off
  end
  local oa, ob = offsets(ca), offsets(cb)
  local hunks = compat.diff(table.concat(ca, '\n') .. '\n', table.concat(cb, '\n') .. '\n', { result_type = 'indices' })
  local out = { a = {}, b = {} }
  for _, h in ipairs(hunks or {}) do
    local sa, na, sb, nb = h[1], h[2], h[3], h[4]
    if na > 0 then out.a[#out.a + 1] = { oa[sa], oa[sa + na] } end
    if nb > 0 then out.b[#out.b + 1] = { ob[sb], ob[sb + nb] } end
  end
  return out
end

local function flat(s)
  return (s or ''):gsub('\n', '⏎')
end

--- Show what an annotation was made on next to what its text is now.
function M.diff(buf, id)
  if buf == 0 then buf = api.nvim_get_current_buf() end
  local a = buffer.annotation(buf, id)
  if not a then return end
  local was, now = flat(a.original_quote), flat(a.quote)
  local lines = { 'originally', was, a.status == 'detached' and 'now (last seen)' or 'now', now }
  local d = M.char_diff(was, now)
  local fbuf = api.nvim_create_buf(false, true)
  vim.bo[fbuf].bufhidden = 'wipe'
  api.nvim_buf_set_lines(fbuf, 0, -1, false, lines)
  api.nvim_buf_set_extmark(fbuf, M.ns, 0, 0, { end_col = #lines[1], hl_group = 'Comment' })
  api.nvim_buf_set_extmark(fbuf, M.ns, 2, 0, { end_col = #lines[3], hl_group = 'Comment' })
  for _, r in ipairs(d.a) do
    api.nvim_buf_set_extmark(fbuf, M.ns, 1, r[1], { end_col = r[2], hl_group = 'DiffDelete' })
  end
  for _, r in ipairs(d.b) do
    api.nvim_buf_set_extmark(fbuf, M.ns, 3, r[1], { end_col = r[2], hl_group = 'DiffAdd' })
  end
  vim.bo[fbuf].modifiable = false
  local win = api.nvim_get_current_win()
  local W = api.nvim_win_get_width(win)
  local w = math.min(math.max(vim.fn.strdisplaywidth(was), vim.fn.strdisplaywidth(now), 20) + 1, math.floor(W * 0.8))
  local h = 4
  for _, l in ipairs({ was, now }) do
    h = h + math.max(0, math.ceil(vim.fn.strdisplaywidth(l) / w) - 1)
  end
  local S = buffer.state[buf]
  local s, e = buffer.live_pos(buf, S, id)
  local cfg
  if s and api.nvim_win_get_buf(win) == buf then
    cfg = place.for_span(win, s, e, w, h, { bordered = true })
    cfg.side = nil
  else
    cfg = { relative = 'cursor', row = 1, col = 0, width = w, height = h }
  end
  cfg.border = config.options.ui.border
  cfg.title, cfg.title_pos = ' ' .. buffer.display_name(buf, a.values[1]) .. ' ', 'left'
  cfg.style = 'minimal'
  cfg.zindex = 55
  local fwin = api.nvim_open_win(fbuf, true, cfg)
  vim.wo[fwin].wrap = true
  for _, lhs in ipairs({ 'q', '<Esc>' }) do
    vim.keymap.set('n', lhs, '<cmd>close<cr>', { buffer = fbuf, nowait = true, desc = 'earmark: close' })
  end
  api.nvim_create_autocmd('WinLeave', {
    buffer = fbuf,
    once = true,
    callback = function()
      vim.schedule(function()
        if api.nvim_win_is_valid(fwin) then api.nvim_win_close(fwin, true) end
      end)
    end,
  })
  return fwin
end

---------------------------------------------------------------------------
-- Review list
---------------------------------------------------------------------------

--- Places the annotation's text could be now (excluding where it is): { {s, e, text, score} }.
function M.suggestions(buf, a)
  local anchor = require('earmark.anchor')
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local t = anchor.text(lines)
  local S = buffer.state[buf]
  local cur_s = buffer.live_pos(buf, S, a.id)
  local near = (cur_s or a.s) and anchor.pos_to_off(t, (cur_s or a.s)[1], (cur_s or a.s)[2]) or nil
  local item = { quote = a.original_quote, prefix = a.prefix, suffix = a.suffix }
  local out = {}
  for _, c in ipairs(anchor.candidates(t, item, near, 4, { fuzzy = true })) do
    local sr, sc = anchor.off_to_pos(t, c.s)
    local er, ec = anchor.off_to_pos(t, c.e)
    if not (cur_s and cur_s[1] == sr and cur_s[2] == sc) then
      out[#out + 1] = { s = { sr, sc }, e = { er, ec }, text = t.str:sub(c.s + 1, c.e), score = c.score }
    end
  end
  return out
end

local function actions_for(buf, it)
  local a = it.annotation
  local list = {}
  local placed = a.status ~= 'detached'
  if placed then list[#list + 1] = { label = 'Jump to it', run = function() picker.jump_to(it) end } end
  list[#list + 1] = { label = 'Compare original and current text', run = function() M.diff(buf, a.id) end }
  if placed then
    list[#list + 1] = {
      label = 'Accept the current text',
      run = function()
        buffer.accept(buf, a.id)
        notify('accepted the current text')
      end,
    }
  end
  for _, sug in ipairs(M.suggestions(buf, a)) do
    list[#list + 1] = {
      label = ('Move it to line %d: "%s" (%d%%)'):format(sug.s[1] + 1, flat(sug.text):sub(1, 40), math.floor(sug.score * 100 + 0.5)),
      run = function()
        buffer.reanchor(buf, a.id, sug.s, sug.e)
        notify(('moved to line %d'):format(sug.s[1] + 1))
      end,
    }
  end
  list[#list + 1] = {
    label = 'Attach it to a selection…',
    run = function()
      M.pending = { buf = buf, id = a.id }
      notify('select the text it belongs to, then run :Earmark reanchor')
    end,
  }
  list[#list + 1] = {
    label = 'Erase it',
    run = function()
      buffer.erase(buf, { a.id })
      notify('erased 1')
    end,
  }
  return list
end

--- What to do with one reviewed annotation.
function M.act(buf, it)
  local list = actions_for(buf, it)
  vim.ui.select(list, {
    prompt = ('"%s" (%s)'):format(flat(it.annotation.original_quote):sub(1, 40), it.annotation.status),
    kind = 'earmark_review',
    format_item = function(x)
      return x.label
    end,
  }, function(choice)
    if choice then choice.run() end
  end)
end

--- `<leader>md`: annotations in this buffer that are stale, ambiguous or detached.
function M.open(buf)
  if buf == 0 then buf = api.nvim_get_current_buf() end
  local items = vim.tbl_filter(function(it)
    return it.annotation.status ~= 'ok'
  end, picker.doc_items(buf))
  if #items == 0 then return notify('nothing to review: every annotation is attached to its text') end
  picker.pick(items, {
    prompt = 'Review annotations',
    on_choice = function(it)
      M.act(buf, it)
    end,
  })
end

--- `:'<,'>Earmark reanchor`: attach the annotation chosen in the review list (else the one
--- under the cursor) to the selected text.
function M.reanchor_to_selection(buf, s, e)
  if buf == 0 then buf = api.nvim_get_current_buf() end
  local target = M.pending and M.pending.buf == buf and M.pending.id
  if not target then
    local hits = buffer.find(buf, s, e)
    target = hits[1] and hits[1].a.id
  end
  if not target then return notify('choose an annotation in the review list first') end
  M.pending = nil
  if buffer.reanchor(buf, target, s, e) then notify('re-attached') end
end

return M
