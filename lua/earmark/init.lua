local buffer = require('earmark.buffer')
local config = require('earmark.config')
local log = require('earmark.log')
local sets = require('earmark.sets')

local api = vim.api
local M = {}

local function notify(msg, level)
  vim.notify('earmark: ' .. msg, level or vim.log.levels.INFO)
end

---------------------------------------------------------------------------
-- Operator
---------------------------------------------------------------------------

local pending -- value used by the next (or repeated) operator call
local want_prompt = false -- the next operator call (not a dot-repeat) opens the prompt
-- Dot-repeat after the prompt: typing into the prompt buffer replaces Vim's repeat
-- command, so the keys of the motion are recorded while the operator waits for it and the
-- operator is replayed with the chosen label once the prompt closes.
local capture_ns = api.nvim_create_namespace('earmark_capture')
local op -- { win, cursor, visual, suffix, keys = {} } of the operator waiting for a motion
local replay -- spans the replayed operator must cover
local last_value -- most recently used value; preselected in the prompt
local asked = {} -- [buf]["set/key"] = true once the prompt asked to name that label

local function value_for_count(count)
  local l = sets.resolve(count)
  if not l then
    notify(('no label %d in set "%s"'):format(count, sets.current), vim.log.levels.WARN)
    return nil
  end
  return { set = sets.current, label = l.key }
end

local function first_key()
  if last_value and last_value.set == sets.current and sets.label(last_value) then return last_value.label end
  local set = sets.by_name[sets.current]
  return set and set.labels[1] and set.labels[1].key or nil
end

local function names()
  return require('earmark.names')
end

--- Should the prompt go on to ask for a name after this label was chosen?
local function should_name(buf)
  return function(value)
    local mode = config.options.prompt.ask_name
    if mode == 'never' then return false end
    if mode == 'always' then return true end
    local key = value.set .. '/' .. value.label
    asked[buf] = asked[buf] or {}
    if asked[buf][key] or not sets.is_numbered(value.set) or names().known(buf, value) then return false end
    asked[buf][key] = true
    return true
  end
end

--- Spans [{s, e}] covered by the last operator motion / visual selection.
local function region(motion)
  local ty = ({ char = 'v', line = 'V', block = '\22' })[motion]
  local segs = vim.fn.getregionpos(vim.fn.getpos("'["), vim.fn.getpos("']"), { type = ty, eol = true })
  local lines = api.nvim_buf_get_lines(0, 0, -1, false)
  local function excl_end(row, col1) -- 1-based inclusive byte col -> 0-based exclusive
    local line = lines[row + 1] or ''
    local c = math.min(col1, #line)
    while c < #line and line:byte(c + 1) >= 0x80 and line:byte(c + 1) < 0xC0 do
      c = c + 1
    end
    return c
  end
  if #segs == 0 then return {} end
  if motion == 'block' then
    local out = {}
    for _, p in ipairs(segs) do
      local row = p[1][2] - 1
      out[#out + 1] = { s = { row, p[1][3] - 1 }, e = { row, excl_end(row, p[2][3]) } }
    end
    return out
  end
  local first, last = segs[1], segs[#segs]
  local s = { first[1][2] - 1, motion == 'line' and 0 or first[1][3] - 1 }
  local erow = last[2][2] - 1
  local e = { erow, motion == 'line' and #(lines[erow + 1] or '') or excl_end(erow, last[2][3]) }
  return { { s = s, e = e } }
end

local function apply(buf, spans, value)
  local n = 0
  for _, r in ipairs(spans) do
    if buffer.add(buf, r.s, r.e, value) then n = n + 1 end
  end
  if n > 0 then last_value = value end
  return n
end

--- Open the label prompt for spans of the current buffer; `on_value(value)` runs on accept.
local function prompt_for(spans, on_value, opts)
  local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
  opts = opts or {}
  require('earmark.ui.hover').hide()
  require('earmark.ui.prompt').open({
    buf = buf,
    win = win,
    spans = spans,
    set = opts.set,
    first = opts.first or first_key(),
    stage = opts.stage,
    value = opts.value,
    should_name = opts.stage ~= 'name' and should_name(buf) or nil,
    on_accept = function(value, name)
      if name ~= nil then names().save(buf, value, name) end
      on_value(value, name)
    end,
  })
end

local function same_spans(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    if not vim.deep_equal(a[i], b[i]) then return false end
  end
  return true
end

--- Re-run the operator with `value`, so `.` repeats it (see `op` above). Falls back to
--- annotating `spans` directly if the replay can't reproduce them.
local function replay_operator(o, spans, value)
  pending, want_prompt, replay = value, false, spans
  local ok = pcall(function()
    api.nvim_set_current_win(o.win)
    api.nvim_win_set_cursor(o.win, o.cursor)
    vim.o.operatorfunc = "v:lua.require'earmark'.operatorfunc"
    local keys = o.visual and 'gvg@' or ('g@' .. (o.suffix or '') .. table.concat(o.keys))
    api.nvim_feedkeys(keys, o.visual and 'nx' or 'mx', false)
  end)
  if replay then -- the replay didn't reach operatorfunc
    replay = nil
    if not ok then log.warn('replaying the operator failed') end
    apply(api.nvim_get_current_buf(), spans, value)
  end
end

--- 'operatorfunc' target. Public so it can be referenced as v:lua.
function M.operatorfunc(motion)
  vim.on_key(nil, capture_ns)
  local spans = region(motion)
  if replay then
    local want = replay
    replay = nil
    apply(0, same_spans(spans, want) and spans or want, pending)
    return
  end
  if #spans == 0 then return end
  if want_prompt then
    want_prompt = false
    local o = op
    op = nil
    vim.schedule(function()
      prompt_for(spans, function(value)
        if o then
          replay_operator(o, spans, value)
        else
          pending = value
          apply(api.nvim_get_current_buf(), spans, value)
        end
      end)
    end)
    return
  end
  if pending then apply(0, spans, pending) end
end

local opfunc = "v:lua.require'earmark'.operatorfunc"

--- Expression mapping for the operator. In Normal mode the count picks the label and is
--- dropped before g@, so it doesn't multiply the motion.
function M.operator_expr(suffix)
  local mode = api.nvim_get_mode().mode
  if vim.v.count > 0 then
    local value = value_for_count(vim.v.count)
    if not value then return '<Ignore>' end
    pending, want_prompt = value, false
  else
    want_prompt = true
    op = {
      win = api.nvim_get_current_win(),
      cursor = api.nvim_win_get_cursor(0),
      visual = mode:match('^[vV\22]') ~= nil,
      suffix = suffix,
      keys = {},
      -- the keys this mapping returns (<Esc>g@ + suffix) come through on_key first
      skip = 3 + #(suffix or ''),
    }
    local o = op
    vim.on_key(function(_, typed)
      if o.skip > 0 then
        o.skip = o.skip - 1
        return
      end
      if not api.nvim_get_mode().mode:match('^no') then
        -- the operator was cancelled before a motion completed
        vim.schedule(function()
          if op == o then
            op, want_prompt = nil, false
            vim.on_key(nil, capture_ns)
          end
        end)
        return
      end
      if typed and typed ~= '' then o.keys[#o.keys + 1] = typed end
    end, capture_ns)
  end
  vim.o.operatorfunc = opfunc
  if mode:match('^[vV\22]') then return 'g@' end
  return '<Esc>g@' .. (suffix or '')
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

local function cursor_pos()
  local c = api.nvim_win_get_cursor(0)
  return { c[1] - 1, c[2] }
end

--- Erase the annotation under the cursor (the smallest one, if several overlap).
function M.erase()
  local hits = buffer.find(0, cursor_pos())
  if #hits == 0 then return notify('nothing under the cursor') end
  buffer.erase(0, { hits[1].a.id })
end

--- Erase every annotation overlapping the visual selection.
function M.erase_visual()
  local s, e = vim.fn.getpos('v'), vim.fn.getpos('.')
  if s[2] > e[2] or (s[2] == e[2] and s[3] > e[3]) then s, e = e, s end
  api.nvim_feedkeys(vim.keycode('<Esc>'), 'nx', false)
  local hits = buffer.find(0, { s[2] - 1, s[3] - 1 }, { e[2] - 1, e[3] })
  local ids = vim.tbl_map(function(h)
    return h.a.id
  end, hits)
  notify(('erased %d'):format(buffer.erase(0, ids)))
end

function M.clear()
  local ids = vim.tbl_map(function(x)
    return x.annotation.id
  end, buffer.list(0))
  notify(('erased %d (restore with :Earmark restore)'):format(buffer.erase(0, ids)))
end

function M.restore()
  local n, missing = buffer.restore(0)
  if n == 0 then return notify('nothing to restore') end
  notify(('restored %d%s'):format(n, missing > 0 and (' (%d detached: text not found)'):format(missing) or ''))
end

local function jump(dir)
  local cur = cursor_pos()
  local best
  for _, x in ipairs(buffer.list(0)) do
    if x.s then
      local after = x.s[1] > cur[1] or (x.s[1] == cur[1] and x.s[2] > cur[2])
      local before = x.s[1] < cur[1] or (x.s[1] == cur[1] and x.s[2] < cur[2])
      if dir > 0 and after and not best then best = x end
      if dir < 0 and before then best = x end
    end
  end
  if not best then return notify('no ' .. (dir > 0 and 'next' or 'previous') .. ' annotation') end
  vim.cmd("normal! m'")
  api.nvim_win_set_cursor(0, { best.s[1] + 1, best.s[2] })
end

function M.next()
  jump(1)
end

function M.prev()
  jump(-1)
end

local function hit_under_cursor()
  local hits = buffer.find(0, cursor_pos())
  local n = math.max(1, vim.v.count)
  if #hits == 0 then
    notify('nothing under the cursor')
    return nil
  end
  return hits[math.min(n, #hits)]
end

--- Change the label (first value) of the annotation under the cursor.
function M.relabel()
  local h = hit_under_cursor()
  if not h then return end
  local buf = api.nvim_get_current_buf()
  local v1 = h.a.values[1]
  prompt_for({ { s = h.s, e = h.e } }, function(value)
    local values = vim.deepcopy(h.a.values)
    values[1] = value
    buffer.set_values(buf, h.a.id, values)
    last_value = value
  end, { set = v1.set, first = v1.label })
end

--- Add another label (value) to the annotation under the cursor.
function M.add_value()
  local h = hit_under_cursor()
  if not h then return end
  local buf = api.nvim_get_current_buf()
  prompt_for({ { s = h.s, e = h.e } }, function(value)
    local values = vim.deepcopy(h.a.values)
    for _, v in ipairs(values) do
      if v.set == value.set and v.label == value.label then return notify('it already has that label') end
    end
    values[#values + 1] = value
    buffer.set_values(buf, h.a.id, values)
  end)
end

--- Name the label of the annotation under the cursor for this file (empty clears it).
function M.rename()
  local h = hit_under_cursor()
  if not h then return end
  local v1 = h.a.values[1]
  prompt_for({ { s = h.s, e = h.e } }, function(value, name)
    if name == '' then notify('name cleared for ' .. value.set .. '·' .. value.label) end
  end, { stage = 'name', value = v1 })
end

function M.cycle_set(step)
  local name = sets.cycle(step)
  if name then notify('label set: ' .. name) end
end

function M.use_set(name)
  if not sets.by_name[name] then return notify('no label set "' .. tostring(name) .. '"', vim.log.levels.WARN) end
  sets.current = name
  notify('label set: ' .. name)
end

--- `<leader>mm`: open (or close) the note of the annotation under the cursor; a count
--- picks the n-th overlapping one, innermost first.
function M.note()
  local note = require('earmark.ui.note')
  if note.active then return note.close() end
  local h = hit_under_cursor()
  if h then note.open(0, h.a.id) end
end

function M.peek()
  require('earmark.ui.hover').peek(vim.v.count)
end

function M.toggle_hover()
  require('earmark.ui.hover').toggle()
end

function M.info()
  local hits = buffer.find(0, cursor_pos())
  if #hits == 0 then return notify('nothing under the cursor') end
  local out = {}
  for _, h in ipairs(hits) do
    local a = h.a
    local names = vim.tbl_map(function(v)
      local l = sets.label(v)
      return ('%s:%s'):format(v.set, l and l.name or v.label .. '?')
    end, a.values)
    out[#out + 1] = ('%s  [%s]  %q'):format(table.concat(names, ', '), a.status, a.quote)
    if a.original_quote ~= a.quote then out[#out + 1] = ('  originally: %q'):format(a.original_quote) end
  end
  notify(table.concat(out, '\n'))
end

---------------------------------------------------------------------------
-- Public API (stable surface for other plugins)
---------------------------------------------------------------------------

--- Annotate a range in a buffer. `s`/`e` are 0-based {row, col}, end-exclusive.
--- `value` is { set = <set name>, label = <label key> }.
function M.annotate(buf, s, e, value)
  return buffer.add(buf or 0, s, e, value)
end

--- Annotations in a buffer: list of { annotation, s, e } (s/e nil when detached).
function M.list(buf)
  return buffer.list(buf or 0)
end

--- Annotations at a position (default: cursor), smallest first.
function M.at(buf, pos)
  return buffer.find(buf or 0, pos or cursor_pos())
end

function M.statusline()
  return sets.current or ''
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

local actions = require('earmark.actions')

local function register_actions()
  local A = actions.register
  local function op_expr(suffix)
    return function()
      return M.operator_expr(suffix)
    end
  end
  A({ name = 'operator', desc = 'annotate (count picks the label)', modes = { n = op_expr(), x = op_expr() }, expr = true, cmd = false })
  A({ name = 'line', desc = 'annotate line', modes = { n = op_expr('_') }, expr = true, cmd = false })
  A({ name = 'erase', desc = 'erase annotation(s)', modes = { n = M.erase, x = M.erase_visual } })
  A({ name = 'clear', desc = 'erase all annotations in this buffer', modes = { n = M.clear } })
  A({ name = 'restore', desc = 'restore last erased', modes = { n = M.restore } })
  A({ name = 'next', desc = 'next annotation', modes = { n = M.next } })
  A({ name = 'prev', desc = 'previous annotation', modes = { n = M.prev } })
  A({ name = 'cycle_set', desc = 'next label set', modes = { n = M.cycle_set } })
  A({ name = 'peek', desc = 'show annotation details', modes = { n = M.peek } })
  A({ name = 'note', desc = 'open/close note', modes = { n = M.note } })
  A({ name = 'toggle_hover', desc = 'automatic hover on/off', modes = { n = M.toggle_hover } })
  A({ name = 'info', desc = 'annotation info as a message', cmd = M.info })
  A({ name = 'relabel', desc = 'change label', modes = { n = M.relabel } })
  A({ name = 'add_value', desc = 'add a label', modes = { n = M.add_value } })
  A({ name = 'rename', desc = 'name label for this file', modes = { n = M.rename } })
  A({
    name = 'set',
    desc = 'switch label set',
    cmd = function(args)
      if args[1] then M.use_set(args[1]) else M.cycle_set() end
    end,
    complete = function()
      return sets.order
    end,
  })
  A({
    name = 'reload',
    desc = 'reload annotations from disk',
    cmd = function()
      buffer.reload(api.nvim_get_current_buf())
    end,
  })
  A({ name = 'log', desc = 'show the earmark log', cmd = log.show })
end

local function guard(where, fn)
  return function(ev)
    log.guard(where, fn, ev)
  end
end

local function setup_autocmds()
  local group = api.nvim_create_augroup('earmark', { clear = true })
  local au = function(ev, cb, opts)
    local name = type(ev) == 'table' and table.concat(ev, ',') or ev
    api.nvim_create_autocmd(ev, vim.tbl_extend('force', { group = group, callback = guard(name, cb) }, opts or {}))
  end
  au('BufReadPost', function(ev)
    if buffer.state[ev.buf] then
      buffer.on_change(ev.buf) -- :e! / external reload: repair from the in-memory snapshot
    else
      buffer.get(ev.buf)
    end
  end)
  au('BufWritePost', function(ev)
    if buffer.state[ev.buf] then
      buffer.rename(ev.buf)
      buffer.save(ev.buf)
    end
  end)
  au('BufFilePost', function(ev)
    buffer.rename(ev.buf)
  end)
  local timers = {}
  au({ 'TextChanged', 'TextChangedI', 'TextChangedP' }, function(ev)
    if not buffer.state[ev.buf] then return end
    local t = timers[ev.buf] or vim.uv.new_timer()
    timers[ev.buf] = t
    t:stop()
    t:start(config.options.debounce_ms, 0, vim.schedule_wrap(function()
      log.guard('on_change', buffer.on_change, ev.buf)
    end))
  end)
  au({ 'BufUnload' }, function(ev)
    if buffer.state[ev.buf] then
      buffer.save(ev.buf)
      buffer.forget(ev.buf)
    end
    if timers[ev.buf] then
      timers[ev.buf]:close()
      timers[ev.buf] = nil
    end
  end)
  au('VimLeavePre', function()
    for buf in pairs(buffer.state) do
      buffer.save(buf)
    end
  end)
  require('earmark.ui.hover').setup(au)
  au('ColorScheme', function()
    sets.apply_highlights()
    require('earmark.render').apply_highlights()
  end)
end

function M.setup(opts)
  local compat = require('earmark.compat')
  if not compat.supported() then
    vim.notify('earmark: requires Neovim 0.11 or newer', vim.log.levels.ERROR)
    return
  end
  config.setup(opts)
  sets.load(config.options)
  register_actions()
  actions.apply_keymaps(config.options.keys)
  setup_autocmds()
  require('earmark.render').setup()
  api.nvim_create_user_command('Earmark', actions.run_command, {
    nargs = '*',
    range = true,
    complete = function(_, line)
      local args = vim.split(line, '%s+')
      if #args <= 2 then
        return vim.tbl_filter(function(n)
          return vim.startswith(n, args[2] or '')
        end, actions.commands())
      end
      local a = actions.by_name[args[2]]
      return a and a.complete and a.complete(args) or {}
    end,
  })
  -- Buffers loaded before setup (e.g. the file Neovim was started with).
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == '' and api.nvim_buf_get_name(buf) ~= '' then
      buffer.get(buf)
    end
  end
end

return M
