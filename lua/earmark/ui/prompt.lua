-- The label prompt: a one-line editable buffer in a float next to the span being
-- annotated. Typing narrows the candidate labels (shown under the input as virtual lines,
-- so editing can never touch them), the span previews the selected label's colour live,
-- and <Tab> moves on to naming the label for this document, with history.
--
-- It is a real buffer: Insert and Normal mode editing, pasting and flash all work. <BS>
-- edits, <Esc> leaves Insert mode, <Esc>/q in Normal mode cancels, <CR> applies.
local buffer = require('earmark.buffer')
local config = require('earmark.config')
local names = require('earmark.names')
local place = require('earmark.ui.place')
local sets = require('earmark.sets')

local api = vim.api
local M = {}

M.ns = api.nvim_create_namespace('earmark_prompt')
M.preview_ns = api.nvim_create_namespace('earmark_preview')

--- The open prompt's state, or nil.
M.active = nil

local function opts_()
  return config.options.prompt
end

local function swatch()
  return '██'
end

local function uses_in(buf)
  local uses = {}
  for _, x in ipairs(buffer.list(buf)) do
    local v = x.annotation.values[1]
    if v then uses[v.set .. '\0' .. v.label] = (uses[v.set .. '\0' .. v.label] or 0) + 1 end
  end
  return uses
end

local function input_text(P)
  local lines = api.nvim_buf_get_lines(P.buf, 0, -1, false)
  return table.concat(lines, ' ')
end

local function set_input(P, text)
  api.nvim_buf_set_lines(P.buf, 0, -1, false, { text })
  if api.nvim_get_current_buf() == P.buf then
    pcall(api.nvim_win_set_cursor, P.win, { 1, #text })
  end
end

--- The value the prompt would apply right now (label stage: the selected candidate).
local function current_value(P)
  if P.stage == 'name' or P.stage == 'text' then return P.value end
  if P.stage == 'choice' then
    local c = P.choices[P.sel]
    return c and vim.tbl_extend('force', P.value, { choice = c.key }) or P.value
  end
  local l = P.cands[P.sel]
  return l and { set = P.set, label = l.key } or nil
end

--- Label candidates for the typed text: allowed ones first, then those whose `requires`
--- the annotation doesn't meet (shown dimmed, with the reason).
local function label_cands(P, text)
  local all = sets.resolve_query(P.set, text, P.ctx)
  local ok, blocked = {}, {}
  P.disabled = {}
  for _, l in ipairs(all) do
    local allowed, why = sets.allowed(P.set, l, P.existing)
    if allowed then
      ok[#ok + 1] = l
    else
      P.disabled[l.key] = why
      blocked[#blocked + 1] = l
    end
  end
  return vim.list_extend(ok, blocked)
end

--- Choices of the chosen label matching the typed text.
local function choice_cands(P, text)
  local l = sets.label(P.value)
  local list = l and l.choices or {}
  text = vim.trim(text or '')
  if text == '' then return list end
  local out, seen = {}, {}
  local function add(c)
    if c and not seen[c.key] then
      seen[c.key] = true
      out[#out + 1] = c
    end
  end
  for _, c in ipairs(list) do
    if c.key == text then add(c) end
  end
  for _, c in ipairs(list) do
    if vim.startswith(c.key:lower(), text:lower()) then add(c) end
  end
  local hay = vim.tbl_map(function(c)
    return { text = c.key .. ' ' .. c.name, c = c }
  end, list)
  for _, m in ipairs(vim.fn.matchfuzzy(hay, text, { key = 'text' })) do
    add(m.c)
  end
  return out
end

local function clear_preview(P)
  if api.nvim_buf_is_valid(P.src_buf) then api.nvim_buf_clear_namespace(P.src_buf, M.preview_ns, 0, -1) end
end

local function preview(P, value)
  clear_preview(P)
  if not value or not api.nvim_buf_is_valid(P.src_buf) then return end
  local group = sets.group(value, buffer.get(P.src_buf) and buffer.get(P.src_buf).colors)
  for _, sp in ipairs(P.spans) do
    pcall(api.nvim_buf_set_extmark, P.src_buf, M.preview_ns, sp.s[1], sp.s[2], {
      end_row = sp.e[1],
      end_col = sp.e[2],
      hl_group = group,
      priority = 6000,
      strict = false,
    })
  end
end

--- Virtual lines listing the candidates (label stage) or the name history (name stage).
local function rows(P, width)
  local out = {}
  local max = opts_().max_rows
  if P.stage == 'label' then
    local text = vim.trim(input_text(P))
    if #P.cands == 0 then
      return { { { ('  no label "%s" in %s'):format(text, P.set), 'Comment' } } }
    end
    local first = math.max(1, math.min(P.sel - max + 1, #P.cands - max + 1))
    local keyw = 1
    for i = first, math.min(#P.cands, first + max - 1) do
      keyw = math.max(keyw, vim.fn.strdisplaywidth(P.cands[i].key))
    end
    for i = first, math.min(#P.cands, first + max - 1) do
      local l = P.cands[i]
      local selected = i == P.sel
      local function hl(g)
        return selected and { g, 'CursorLine' } or g
      end
      local value = { set = P.set, label = l.key }
      local name = buffer.display_name(P.src_buf, value)
      local n = P.uses[P.set .. '\0' .. l.key] or 0
      local left = (selected and '▸ ' or '  ')
      local key = l.key .. string.rep(' ', keyw - vim.fn.strdisplaywidth(l.key))
      local shown_name = name ~= l.key and name or ''
      local why = P.disabled and P.disabled[l.key]
      local right = why or (n > 0 and ('used %d×'):format(n) or '')
      if why then
        hl = function()
          return selected and { 'Comment', 'CursorLine' } or 'Comment'
        end
      elseif l.choices then
        shown_name = shown_name .. ' …'
      end
      local colors = buffer.get(P.src_buf) and buffer.get(P.src_buf).colors
      local color = sets.color(value, colors)
      -- the colour's name, after your name for the label when there's room
      local cname = sets.color_name(value, colors)
      if cname then cname = (shown_name ~= '' and ' · ' or '') .. cname end
      local used = vim.fn.strdisplaywidth(left) + 3 + keyw + 2 + vim.fn.strdisplaywidth(shown_name)
      if cname and used + vim.fn.strdisplaywidth(cname) + 1 + vim.fn.strdisplaywidth(right) > width then cname = nil end
      used = used + (cname and vim.fn.strdisplaywidth(cname) or 0)
      local pad = math.max(1, width - used - vim.fn.strdisplaywidth(right))
      out[#out + 1] = {
        { left, hl(selected and 'Special' or 'NormalFloat') },
        { swatch() .. ' ', hl(color and sets.fg_group(color) or 'NormalFloat') },
        { key .. '  ', hl(selected and 'Special' or 'NormalFloat') },
        { shown_name, hl('NormalFloat') },
        { cname or '', hl('Comment') },
        { string.rep(' ', pad) .. right, hl('Comment') },
      }
    end
  elseif P.stage == 'choice' then
    local l = sets.label(P.value)
    if #P.choices == 0 then
      return { { { ('  no choice "%s" for %s'):format(vim.trim(input_text(P)), l and l.name or '?'), 'Comment' } } }
    end
    local first = math.max(1, math.min(P.sel - max + 1, #P.choices - max + 1))
    for i = first, math.min(#P.choices, first + max - 1) do
      local c = P.choices[i]
      local selected = i == P.sel
      local function hl(g)
        return selected and { g, 'CursorLine' } or g
      end
      local hex = sets.color(vim.tbl_extend('force', P.value, { choice = c.key }), buffer.get(P.src_buf) and buffer.get(P.src_buf).colors)
      local line = {
        { selected and '▸ ' or '  ', hl(selected and 'Special' or 'NormalFloat') },
        { swatch() .. ' ', hl(hex and sets.fg_group(hex) or 'NormalFloat') },
        { c.key .. '  ', hl(selected and 'Special' or 'NormalFloat') },
        { c.name, hl('NormalFloat') },
      }
      local used = 2 + 3 + vim.fn.strdisplaywidth(c.key) + 2 + vim.fn.strdisplaywidth(c.name)
      line[#line + 1] = { string.rep(' ', math.max(0, width - used)), hl('NormalFloat') }
      out[#out + 1] = line
    end
  elseif P.stage == 'text' then
    local l = sets.label(P.value)
    local hint = l and l.text and l.text.prompt or 'add a short text (optional)'
    return { { { '  ' .. hint, 'Comment' } } }
  else
    -- say plainly what is being named, in the label's colour, before any earlier names
    local colors = buffer.get(P.src_buf) and buffer.get(P.src_buf).colors
    local hex = sets.color(P.value, colors)
    local cname = sets.color_name(P.value, colors)
    out[#out + 1] = {
      { '  ', 'NormalFloat' },
      { swatch() .. ' ', hex and sets.fg_group(hex) or 'NormalFloat' },
      { ('%s%s'):format(P.value.label, cname and (' ' .. cname) or ''), 'Special' },
      { ': what does it mean?', 'NormalFloat' },
    }
    out[#out + 1] = { { ('  e.g. Claim, NPC. Used for every %s here.'):format(P.value.label), 'Comment' } }
    if #P.hist == 0 then return out end
    out[#out + 1] = { { '  earlier names:', 'Comment' } }
    for i = 1, math.min(#P.hist, max) do
      local h = P.hist[i]
      local selected = i == P.hist_i
      local function hl(g)
        return selected and { g, 'CursorLine' } or g
      end
      out[#out + 1] = {
        { selected and '▸ ' or '  ', hl(selected and 'Special' or 'NormalFloat') },
        { h.text, hl('NormalFloat') },
        { '  (' .. h.source .. ')', hl('Comment') },
      }
    end
  end
  return out
end

local function title(P)
  if P.stage == 'name' then
    return (' Name label %s · %s '):format(P.value.label, P.value.set)
  end
  if P.stage == 'choice' or P.stage == 'text' then
    local l = sets.label(P.value)
    local name = buffer.display_name(P.src_buf, { set = P.value.set, label = P.value.label })
    local c = P.stage == 'text' and P.value.choice and (' · ' .. P.value.choice) or ''
    return (' earmark · %s%s%s '):format(name, c, l and '' or '')
  end
  return (' earmark · %s '):format(P.set)
end

local function footer(P)
  if P.stage == 'name' then
    return P.back_ok and ' ⏎ save name  ↑↓ history  ⇤ back  ␛ cancel ' or ' ⏎ save name  ↑↓ history  ␛ cancel '
  end
  if P.stage == 'choice' then return ' ⏎ choose  ^n/^p  ⇤ back  ␛ cancel ' end
  if P.stage == 'text' then return ' ⏎ apply  ⇤ back  ␛ cancel ' end
  return ' ⏎ apply  ⇥ name  ^n/^p  ^s set  ␛ cancel '
end

local function render(P)
  if not (api.nvim_buf_is_valid(P.buf) and api.nvim_win_is_valid(P.win)) then return end
  local value = current_value(P)
  if P.stage == 'label' or P.stage == 'choice' then preview(P, value) end
  local width = math.min(opts_().width, math.max(20, api.nvim_win_get_width(P.src_win) - 4))
  local vl = rows(P, width)
  api.nvim_buf_clear_namespace(P.buf, M.ns, 0, -1)
  local group = value and sets.group(value, buffer.get(P.src_buf) and buffer.get(P.src_buf).colors) or nil
  local mark = {
    virt_text = { { '› ', group or 'Special' } },
    virt_text_pos = 'inline',
    right_gravity = false,
    virt_lines = vl,
    line_hl_group = group,
  }
  api.nvim_buf_set_extmark(P.buf, M.ns, 0, 0, mark)
  local color = value and sets.color(value, buffer.get(P.src_buf) and buffer.get(P.src_buf).colors)
  api.nvim_set_hl(0, 'EarmarkPromptBorder', color and { fg = require('earmark.color').adapt(color) } or { link = 'FloatBorder' })
  local cfg = place.for_span(P.src_win, P.spans[1].s, P.spans[#P.spans].e, width, 1 + #vl, {
    prefer = P.side,
    min_h = 1 + #vl,
    bordered = config.options.ui.border ~= 'none',
  })
  P.side = P.side or cfg.side
  cfg.side = nil
  local b = place.border_opts(config.options.ui.border, title(P), footer(P))
  cfg.border, cfg.title, cfg.title_pos, cfg.footer, cfg.footer_pos = b.border, b.title, b.title_pos, b.footer, b.footer_pos
  api.nvim_win_set_config(P.win, cfg)
end

local function close(P)
  P.closing = true
  clear_preview(P)
  if M.active == P then M.active = nil end
  if api.nvim_win_is_valid(P.win) then api.nvim_win_close(P.win, true) end
  if api.nvim_buf_is_valid(P.buf) then pcall(api.nvim_buf_delete, P.buf, { force = true }) end
  if api.nvim_win_is_valid(P.src_win) then api.nvim_set_current_win(P.src_win) end
end

--- Leave Insert mode, then close and run `fn` once Neovim is back in Normal mode.
local function finish(P, fn)
  if P.closing then return end
  P.closing = true
  vim.cmd('stopinsert')
  vim.schedule(function()
    close(P)
    if fn then fn() end
  end)
end

local function cancel(P)
  finish(P, P.on_cancel)
end

local function enter_name_stage(P, value, back_ok)
  if P.stage == 'label' then P.label_text = input_text(P) end
  P.stage, P.value, P.back_ok = 'name', value, back_ok
  P.hist = names.history(P.src_buf, value)
  P.hist_i = #P.hist > 0 and 1 or 0
  clear_preview(P)
  preview(P, value)
  set_input(P, P.hist[1] and P.hist[1].text or '')
  render(P)
end

--- Apply the label chosen before the name stage, without naming it.
local function skip_name(P)
  local value = P.value
  finish(P, function()
    P.on_accept(value, nil)
  end)
end

local function finish_value(P, value)
  if P.want_name or (P.should_name and P.should_name(value)) then
    P.asked_name = true
    return enter_name_stage(P, value, true)
  end
  finish(P, function()
    P.on_accept(value, nil)
  end)
end

local function enter_text_stage(P, value)
  P.prev_stage = P.stage
  if P.stage == 'label' then P.label_text = input_text(P) end
  P.stage, P.value = 'text', value
  preview(P, value)
  set_input(P, value.text or '')
  render(P)
end

--- After a label (and its choice): ask for text when the label wants it, else finish.
local function after_value(P, value)
  local l = sets.label(value)
  if l and l.text and (not l.text.when or vim.tbl_contains(l.text.when, value.choice)) then
    return enter_text_stage(P, value)
  end
  finish_value(P, value)
end

local function enter_choice_stage(P, value)
  P.label_text = input_text(P)
  P.stage, P.value = 'choice', value
  P.choices = choice_cands(P, '')
  P.sel = 1
  set_input(P, '')
  render(P)
end

local function accept(P)
  if P.stage == 'label' then
    local value = current_value(P)
    if not value then return end
    if P.disabled and P.disabled[value.label] then return end
    local l = sets.label(value)
    if l and l.choices then return enter_choice_stage(P, value) end
    after_value(P, value)
  elseif P.stage == 'choice' then
    local c = P.choices[P.sel]
    if not c then return end
    after_value(P, vim.tbl_extend('force', P.value, { choice = c.key }))
  elseif P.stage == 'text' then
    local text = vim.trim(input_text(P))
    local value = vim.tbl_extend('force', P.value, { text = text ~= '' and text or nil })
    finish_value(P, value)
  else
    local name = vim.trim(input_text(P))
    local value = P.value
    finish(P, function()
      P.on_accept(value, name)
    end)
  end
end

local function move(P, step)
  if P.stage == 'label' then
    if #P.cands == 0 then return end
    P.sel = ((P.sel - 1 + step) % #P.cands) + 1
  elseif P.stage == 'choice' then
    if #P.choices == 0 then return end
    P.sel = ((P.sel - 1 + step) % #P.choices) + 1
  elseif P.stage == 'text' then
    return
  else
    if #P.hist == 0 then return end
    P.hist_i = ((P.hist_i - 1 + step) % #P.hist) + 1
    -- the text change this causes is not typing: keep the history position
    P.moving = true
    set_input(P, P.hist[P.hist_i].text)
  end
  render(P)
end

local function on_text_changed(P)
  if P.closing then return end
  if api.nvim_buf_line_count(P.buf) > 1 then
    -- a paste with newlines: keep it on one line
    local text = input_text(P)
    vim.schedule(function()
      if api.nvim_buf_is_valid(P.buf) then set_input(P, text) end
    end)
    return
  end
  if P.moving then
    P.moving = false
  elseif P.stage == 'label' then
    local text = input_text(P)
    P.cands = label_cands(P, text)
    P.sel = 1
    if #P.cands == 0 and text:match('^%d%d%d+$') then
      -- a third digit replaces the oldest: "34" then "3" reads as "43"
      return vim.schedule(function()
        if api.nvim_buf_is_valid(P.buf) then set_input(P, text:sub(-2)) end
      end)
    end
  elseif P.stage == 'choice' then
    P.choices = choice_cands(P, input_text(P))
    P.sel = 1
  elseif P.stage == 'name' then
    P.hist_i = 0
  end
  render(P)
end

local function keymaps(P)
  local function map(modes, lhs, fn)
    vim.keymap.set(modes, lhs, fn, { buffer = P.buf, nowait = true, silent = true })
  end
  map({ 'i', 'n' }, '<CR>', function()
    accept(P)
  end)
  map({ 'i', 'n' }, '<Tab>', function()
    -- like <CR> (choices and text are still asked for), then the name
    if P.stage ~= 'name' then P.want_name = true end
    accept(P)
  end)
  -- <Esc> while naming a label that was chosen already: keep the label, skip the name
  vim.keymap.set('i', '<Esc>', function()
    if P.stage == 'name' and P.asked_name then
      vim.schedule(function()
        skip_name(P)
      end)
      return ''
    end
    return '<Esc>'
  end, { buffer = P.buf, nowait = true, silent = true, expr = true })
  local function back_to_label()
    P.stage = 'label'
    set_input(P, P.label_text or '')
    P.cands = label_cands(P, P.label_text or '')
    render(P)
  end
  map({ 'i', 'n' }, '<S-Tab>', function()
    if P.stage == 'choice' then
      back_to_label()
    elseif P.stage == 'text' then
      local l = sets.label(P.value)
      if l and l.choices then
        P.stage = 'choice'
        P.value = { set = P.value.set, label = P.value.label }
        set_input(P, '')
        P.choices = choice_cands(P, '')
        render(P)
      else
        back_to_label()
      end
    elseif P.stage == 'name' and P.back_ok then
      back_to_label()
    end
  end)
  for _, k in ipairs({ '<C-n>', '<Down>' }) do
    map('i', k, function()
      move(P, 1)
    end)
  end
  for _, k in ipairs({ '<C-p>', '<Up>' }) do
    map('i', k, function()
      move(P, -1)
    end)
  end
  map('n', 'j', function()
    move(P, 1)
  end)
  map('n', 'k', function()
    move(P, -1)
  end)
  map({ 'i', 'n' }, '<C-s>', function()
    if P.stage ~= 'label' or #sets.order < 2 then return end
    local idx = 1
    for i, n in ipairs(sets.order) do
      if n == P.set then idx = i end
    end
    P.set = sets.order[(idx % #sets.order) + 1]
    P.cands = label_cands(P, input_text(P))
    P.sel = 1
    render(P)
  end)
  map('n', '<Esc>', function()
    if P.stage == 'name' and P.asked_name then return skip_name(P) end
    cancel(P)
  end)
  map('n', 'q', function()
    cancel(P)
  end)
end

--- Open the prompt.
--- opts.buf/win: the annotated buffer and its window; opts.spans: { {s=, e=} } to preview;
--- opts.set: label set to start in; opts.first: key preselected when nothing is typed;
--- opts.stage: 'label' (default) or 'name' (opts.value then names that label);
--- opts.should_name(value) -> true to go on to the name stage after a label is chosen;
--- opts.existing: values already on the annotation (for labels' `requires`);
--- opts.on_accept(value, name|nil); opts.on_cancel().
function M.open(opts)
  if M.active then close(M.active) end
  local src_win = opts.win or api.nvim_get_current_win()
  local P = {
    src_buf = opts.buf or api.nvim_get_current_buf(),
    src_win = src_win,
    spans = opts.spans,
    set = opts.set or sets.current,
    stage = 'label',
    sel = 1,
    cands = {},
    hist = {},
    hist_i = 0,
    on_accept = opts.on_accept,
    on_cancel = opts.on_cancel,
    should_name = opts.should_name,
    existing = opts.existing or {},
    choices = {},
  }
  P.uses = uses_in(P.src_buf)
  P.ctx = {
    first = opts.first,
    uses = setmetatable({}, {
      __index = function(_, k)
        return P.uses[P.set .. '\0' .. k]
      end,
    }),
    name = function(l)
      return buffer.display_name(P.src_buf, { set = P.set, label = l.key })
    end,
  }
  P.cands = label_cands(P, '')
  P.buf = api.nvim_create_buf(false, true)
  vim.bo[P.buf].bufhidden = 'wipe'
  vim.bo[P.buf].swapfile = false
  vim.bo[P.buf].filetype = 'earmark_prompt'
  vim.b[P.buf].completion = false -- blink.cmp
  vim.b[P.buf].minipairs_disable = true
  vim.b[P.buf].cmp_enabled = false
  local cfg = place.for_span(src_win, P.spans[1].s, P.spans[#P.spans].e, opts_().width, 2, {
    bordered = config.options.ui.border ~= 'none',
  })
  P.side = cfg.side
  cfg.side = nil
  cfg.style = 'minimal'
  cfg.zindex = 60
  local b = place.border_opts(config.options.ui.border, title(P), footer(P))
  cfg.border, cfg.title, cfg.title_pos, cfg.footer, cfg.footer_pos = b.border, b.title, b.title_pos, b.footer, b.footer_pos
  P.win = api.nvim_open_win(P.buf, true, cfg)
  vim.wo[P.win].winhighlight = 'Normal:NormalFloat,FloatBorder:EarmarkPromptBorder,FloatTitle:EarmarkPromptBorder'
  vim.wo[P.win].wrap = false
  vim.wo[P.win].cursorline = false
  M.active = P
  keymaps(P)
  local group = api.nvim_create_augroup('earmark_prompt', { clear = true })
  api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'TextChangedP' }, {
    group = group,
    buffer = P.buf,
    callback = function()
      on_text_changed(P)
    end,
  })
  api.nvim_create_autocmd('WinLeave', {
    group = group,
    buffer = P.buf,
    callback = function()
      if P.closing then return end
      place.on_leave(P.win, function()
        if P.closing then return end
        P.closing = true
        close(P)
        -- a label already chosen is kept; only the name is skipped
        if P.stage == 'name' and P.asked_name then
          P.on_accept(P.value, nil)
        elseif P.on_cancel then
          P.on_cancel()
        end
      end)
    end,
  })
  if opts.stage == 'name' then
    enter_name_stage(P, opts.value, false)
  else
    render(P)
  end
  vim.cmd('startinsert!')
  return P
end

--- Save a typed name for a value (shared by the prompt's callers).
function M.save_name(buf, value, name)
  if name == nil then return end
  names.save(buf, value, name)
end

return M
