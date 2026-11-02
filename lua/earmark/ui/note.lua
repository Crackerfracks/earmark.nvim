-- The note editor: a Markdown buffer `earmark://note/<id>` in a float next to the annotation
-- (or a split, `,s` / `,f`). `:w`, `<C-s>`, `q` and closing the window by any route save
-- it, through `buffer.set_note` only. An unmodified editor never writes, so a stale buffer
-- can't overwrite a note changed elsewhere.
local buffer = require('earmark.buffer')
local config = require('earmark.config')
local log = require('earmark.log')
local place = require('earmark.ui.place')
local sets = require('earmark.sets')

local api = vim.api
local M = {}

--- The open editor: { buf, src_buf, id, win, layout = 'float'|'split' }, or nil.
M.active = nil

local function notify(msg, level)
  vim.notify('earmark: ' .. msg, level or vim.log.levels.INFO)
end

local function name_for(id)
  return 'earmark://note/' .. id
end

local function text_of(E)
  return table.concat(api.nvim_buf_get_lines(E.buf, 0, -1, false), '\n')
end

local function colour(E)
  local a = buffer.annotation(E.src_buf, E.id)
  local S = buffer.state[E.src_buf]
  return a and sets.color(a.values[1], S and S.colors) or nil
end

local function title(E, mark)
  local a = buffer.annotation(E.src_buf, E.id)
  local icon = vim.g.have_nerd_font == false and '*' or '✎'
  local name = a and buffer.display_name(E.src_buf, a.values[1]) or '?'
  return (' %s %s %s'):format(icon, name, mark and (mark .. ' ') or '')
end

local function footer(E)
  local a = buffer.annotation(E.src_buf, E.id)
  if not a then return nil end
  local q = (a.quote or ''):gsub('%s+', ' ')
  if vim.fn.strchars(q) > 30 then q = vim.fn.strcharpart(q, 0, 29) .. '…' end
  local ll = vim.g.maplocalleader or '\\'
  ll = ll == ' ' and '<Space>' or ll
  return (' "%s" · %ss split '):format(q, ll)
end

--- Save the editor's text to the annotation if it changed. Returns true when saved.
function M.save(E, quiet)
  E = E or M.active
  if not E or not api.nvim_buf_is_valid(E.buf) then return false end
  if not vim.bo[E.buf].modified then return false end
  local ok = buffer.annotation(E.src_buf, E.id) and buffer.set_note(E.src_buf, E.id, text_of(E))
  if not ok then
    if buffer.set_trashed_note(E.src_buf, E.id, text_of(E)) then
      vim.bo[E.buf].modified = false
      notify(('this annotation was erased; the note is kept with it (%s brings both back)'):format(
        (config.options.keys and config.options.keys.restore) or ':Earmark restore'))
      return true
    end
    notify('the annotation for this note is gone; note not saved', vim.log.levels.WARN)
    return false
  end
  vim.bo[E.buf].modified = false
  if quiet then return true end
  if E.layout == 'float' and E.win and api.nvim_win_is_valid(E.win) then
    -- a brief tick in the title instead of a message
    pcall(api.nvim_win_set_config, E.win, { title = title(E, '✓'), title_pos = 'left' })
    vim.defer_fn(function()
      if E.win and api.nvim_win_is_valid(E.win) and E.layout == 'float' then
        pcall(api.nvim_win_set_config, E.win, { title = title(E), title_pos = 'left' })
      end
    end, 800)
  else
    notify('note saved')
  end
  return true
end

local function float_config(E)
  local o = config.options.note
  local lines = api.nvim_buf_get_lines(E.buf, 0, -1, false)
  local src_win = E.src_win
  if not (src_win and api.nvim_win_is_valid(src_win)) then src_win = api.nvim_get_current_win() end
  local H, W = api.nvim_win_get_height(src_win), api.nvim_win_get_width(src_win)
  local longest = 0
  for _, l in ipairs(lines) do
    longest = math.max(longest, vim.fn.strdisplaywidth(l))
  end
  local maxw = math.max(20, math.min(o.max_width, math.floor(W * o.width)))
  local w = math.max(math.min(40, maxw), math.min(longest + 4, maxw))
  local maxh = math.max(o.height.min, math.floor(H * o.height.max))
  local h = math.max(o.height.min, math.min(#lines + 1, maxh))
  local s, e = buffer.live_pos(E.src_buf, buffer.state[E.src_buf], E.id)
  local cursor = api.nvim_win_get_cursor(src_win)
  s = s or { cursor[1] - 1, cursor[2] }
  e = e or { s[1], s[2] + 1 }
  local cfg = place.for_span(src_win, s, e, w, h, { bordered = true })
  cfg.side = nil
  cfg.zindex = 50
  local b = place.border_opts(config.options.ui.border, title(E), footer(E))
  cfg.border, cfg.title, cfg.title_pos, cfg.footer, cfg.footer_pos = b.border, b.title, b.title_pos, b.footer, b.footer_pos
  return cfg
end

local function style_window(E)
  local win = E.win
  local hex = colour(E)
  local wo = vim.wo[win]
  wo.wrap, wo.linebreak = true, true
  wo.conceallevel = 2
  wo.number, wo.relativenumber = false, false
  wo.signcolumn = (E.layout == 'float' and config.options.note.gutter) and 'yes:1' or 'no'
  wo.fillchars = 'eob: '
  wo.winblend = E.layout == 'float' and config.options.note.winblend or 0
  if hex and E.layout == 'float' then
    local g = sets.fg_group(hex)
    wo.winhighlight = ('Normal:NormalFloat,FloatBorder:%s,FloatTitle:%s'):format(g, sets.fg_group(hex, true))
  end
end

local function open_float(E)
  E.layout = 'float'
  E.win = api.nvim_open_win(E.buf, true, float_config(E))
  style_window(E)
end

local function open_split(E)
  E.layout = 'split'
  vim.cmd('botright 10split')
  E.win = api.nvim_get_current_win()
  api.nvim_win_set_buf(E.win, E.buf)
  style_window(E)
end

--- Close the editor, saving first if it changed.
function M.close(E)
  E = E or M.active
  if not E or E.closing then return end
  E.closing = true
  local shown = E.win ~= nil and api.nvim_win_is_valid(E.win) and api.nvim_win_get_buf(E.win) == E.buf
  local was_current = shown and api.nvim_get_current_win() == E.win
  M.save(E, true)
  if M.active == E then M.active = nil end
  pcall(api.nvim_del_augroup_by_name, 'earmark_note')
  -- (a window that shows another file now is left alone)
  if shown then
    -- the last window can't be closed; show the source buffer there instead
    if #api.nvim_list_wins() == 1 then
      if api.nvim_buf_is_valid(E.src_buf) then api.nvim_win_set_buf(E.win, E.src_buf) end
    else
      pcall(api.nvim_win_close, E.win, true)
    end
  end
  if api.nvim_buf_is_valid(E.buf) then pcall(api.nvim_buf_delete, E.buf, { force = true }) end
  if was_current and E.src_win and api.nvim_win_is_valid(E.src_win) then pcall(api.nvim_set_current_win, E.src_win) end
end

--- Switch between float and split, keeping the text (and unsaved changes).
function M.toggle_layout(E)
  E = E or M.active
  if not E then return end
  local old = E.win
  E.switching = true
  if E.layout == 'float' then
    if E.src_win and api.nvim_win_is_valid(E.src_win) then api.nvim_set_current_win(E.src_win) end
    open_split(E)
  else
    open_float(E)
  end
  if old and api.nvim_win_is_valid(old) then pcall(api.nvim_win_close, old, true) end
  E.switching = false
end

local function keymaps(E)
  local function map(modes, lhs, fn, desc)
    vim.keymap.set(modes, lhs, fn, { buffer = E.buf, nowait = true, desc = 'earmark: ' .. desc })
  end
  map('n', 'q', function() M.close(E) end, 'save and close note')
  map({ 'n', 'i' }, '<C-s>', function() M.save(E) end, 'save note')
  map('n', '<localleader>s', function() if E.layout == 'float' then M.toggle_layout(E) end end, 'note in a split')
  map('n', '<localleader>f', function() if E.layout == 'split' then M.toggle_layout(E) end end, 'note in a float')
  local key = config.options.keys and config.options.keys.note
  if key then map('n', key, function() M.close(E) end, 'close note') end
end

local function autocmds(E)
  local group = api.nvim_create_augroup('earmark_note', { clear = true })
  api.nvim_create_autocmd('BufWriteCmd', {
    group = group,
    buffer = E.buf,
    callback = function()
      if not M.save(E) then vim.bo[E.buf].modified = false end
    end,
  })
  api.nvim_create_autocmd('QuitPre', {
    group = group,
    buffer = E.buf,
    callback = function()
      M.save(E, true)
    end,
  })
  -- shown in no window any more (another file opened in its window): save it and close
  api.nvim_create_autocmd('BufHidden', {
    group = group,
    buffer = E.buf,
    callback = function()
      if E.switching or E.closing then return end
      vim.schedule(function()
        M.close(E)
      end)
    end,
  })
  api.nvim_create_autocmd('WinClosed', {
    group = group,
    callback = function(ev)
      if E.switching or tonumber(ev.match) ~= E.win then return end
      vim.schedule(function()
        M.close(E)
      end)
    end,
  })
  -- leaving a floating editor (to another window) closes it; a split stays open but saves
  api.nvim_create_autocmd('WinLeave', {
    group = group,
    buffer = E.buf,
    callback = function()
      if E.switching or E.closing then return end
      if E.layout ~= 'float' then return M.save(E, true) end
      local function gone()
        if not E.closing then M.close(E) end
      end
      -- a float closes once you've left it (not while an operator such as a flash remote
      -- yank runs from inside it)
      if vim.fn.mode(1):match('^no') then return place.on_leave(E.win, gone) end
      vim.schedule(function()
        if E.closing or not (E.win and api.nvim_win_is_valid(E.win)) then return end
        local cur = api.nvim_get_current_win()
        if cur == E.win then return end
        -- another float took focus (an emoji or file picker, a completion or input window
        -- opened from the note): stay until focus lands in an ordinary window
        if api.nvim_win_get_config(cur).relative ~= '' then
          E.away = true
          return
        end
        gone()
      end)
    end,
  })
  api.nvim_create_autocmd('WinEnter', {
    group = group,
    callback = function()
      if not E.away or E.closing then return end
      local cur = api.nvim_get_current_win()
      if cur == E.win then
        E.away = false
      elseif api.nvim_win_get_config(cur).relative == '' then
        E.away = false
        vim.schedule(function()
          -- (back in the note by then: a picker that hops through a window on its way back)
          if api.nvim_get_current_win() ~= E.win then M.close(E) end
        end)
      end
    end,
  })
end

--- Open the note of annotation `id` in `src_buf` (closing it if it's already open).
function M.open(src_buf, id, opts)
  opts = opts or {}
  if src_buf == 0 then src_buf = api.nvim_get_current_buf() end
  local a = buffer.lead(src_buf, buffer.annotation(src_buf, id)) -- a block's note is its lead's
  id = a and a.id or id
  if not a or place.in_cmdwin() then return end
  if M.active then
    local same = M.active.id == id
    M.close(M.active)
    if same then return end
  end
  pcall(function()
    require('earmark.ui.hover').hide()
  end)
  local name = name_for(id)
  -- a leftover buffer (crash, :hide) is replaced by fresh text from the store
  local old = vim.fn.bufnr(name)
  if old ~= -1 then pcall(api.nvim_buf_delete, old, { force = true }) end
  local buf = api.nvim_create_buf(false, false)
  vim.b[buf].earmark_ui = true -- never annotated (store.doc)
  local E = { buf = buf, src_buf = src_buf, id = id, src_win = api.nvim_get_current_win() }
  api.nvim_buf_set_name(buf, name)
  local bo = vim.bo[buf]
  -- 'hide', not 'wipe': closing the window (<C-w>c, :close) with unsaved text must not fail
  -- with E37; WinClosed then saves it and M.close() wipes it
  bo.buftype, bo.bufhidden, bo.swapfile, bo.buflisted = 'acwrite', 'hide', false, false
  local ul = bo.undolevels
  bo.undolevels = -1
  api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(a.note or '', '\n'))
  bo.undolevels = ul
  bo.modified = false
  bo.filetype = 'markdown'
  M.active = E
  local ok, err = pcall(function()
    if (opts.layout or config.options.note.layout) == 'split' then
      open_split(E)
    else
      open_float(E)
    end
  end)
  if not ok then
    log.error('note editor: %s', err)
    M.active = nil
    pcall(api.nvim_buf_delete, buf, { force = true })
    return
  end
  keymaps(E)
  autocmds(E)
  if not a.note then
    vim.cmd('startinsert')
  end
  return E
end

return M
