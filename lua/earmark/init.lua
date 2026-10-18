local buffer = require('earmark.buffer')
local config = require('earmark.config')
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
local last_value -- most recently used value; the default when no count is given

local function value_for_count(count)
  if count and count > 0 then
    local l = sets.resolve(count)
    if not l then
      notify(('no label %d in set "%s"'):format(count, sets.current), vim.log.levels.WARN)
      return nil
    end
    return { set = sets.current, label = l.key }
  end
  if last_value and sets.label(last_value) then return last_value end
  local set = sets.by_name[sets.current]
  return set and set.labels[1] and { set = sets.current, label = set.labels[1].key } or nil
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

--- 'operatorfunc' target. Public so it can be referenced as v:lua.
function M.operatorfunc(motion)
  local value = pending
  if not value then return end
  local n = 0
  for _, r in ipairs(region(motion)) do
    if buffer.add(0, r.s, r.e, value) then n = n + 1 end
  end
  if n > 0 then last_value = value end
end

local opfunc = "v:lua.require'earmark'.operatorfunc"

--- Expression mapping for the operator. In Normal mode the count picks the label and is
--- dropped before g@, so it doesn't multiply the motion.
function M.operator_expr(suffix)
  local value = value_for_count(vim.v.count)
  if not value then return '<Ignore>' end
  pending = value
  vim.o.operatorfunc = opfunc
  local mode = api.nvim_get_mode().mode
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

function M.cycle_set(step)
  local name = sets.cycle(step)
  if name then notify('label set: ' .. name) end
end

function M.use_set(name)
  if not sets.by_name[name] then return notify('no label set "' .. tostring(name) .. '"', vim.log.levels.WARN) end
  sets.current = name
  notify('label set: ' .. name)
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
local log = require('earmark.log')

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
  A({ name = 'info', desc = 'annotation info', modes = { n = M.info } })
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
  au('ColorScheme', function()
    sets.apply_highlights()
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
