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
  local d = config.options.default_label
  if type(d) == 'string' then
    local set, key = d:match('^(.-)/(.+)$')
    if set == sets.current and sets.label({ set = set, label = key }) then return key end
  end
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
    if asked[buf][key] or not sets.is_numbered(value.set) or names().known_here(buf, value) then return false end
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

local function key_name(action)
  local k = config.options.keys and config.options.keys[action]
  return k or (':Earmark ' .. action)
end

local function apply(buf, spans, value)
  local n, onto = 0, 0
  for _, r in ipairs(spans) do
    local a, how = buffer.add(buf, r.s, r.e, value)
    if a then n = n + 1 end
    if how == 'added' then onto = onto + 1 end
  end
  if n > 0 then last_value = value end
  if onto > 0 then
    notify(('added %s to the annotation already there (%s changes its label instead)'):format(
      buffer.display_name(buf, value), key_name('relabel')))
  end
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
    existing = opts.existing,
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
  local spans = vim.tbl_filter(function(r)
    return r.s[1] ~= r.e[1] or r.s[2] ~= r.e[2]
  end, region(motion))
  if replay then
    local want = replay
    replay = nil
    apply(0, same_spans(spans, want) and spans or want, pending)
    return
  end
  if #spans == 0 then
    want_prompt, op = false, nil
    return notify('nothing to annotate there (no text)')
  end
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
    if not mode:match('^[vV\22]') and config.options.prompt.count_hint then
      -- the keys returned below haven't run yet: wait for the operator to start waiting
      api.nvim_create_autocmd('ModeChanged', {
        pattern = '*:no*',
        once = true,
        callback = function()
          -- (scheduled callbacks only run once the operator is done, so open it right here)
          if vim.v.operator == 'g@' then require('earmark.ui.count_hint').show(value) end
        end,
      })
    end
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

local function erased(n)
  if n == 0 then return notify('nothing to erase') end
  notify(('erased %d (restore with %s)'):format(n, key_name('restore')))
end

--- Erase the annotation under the cursor (the smallest one, if several overlap).
function M.erase_under_cursor()
  local hits = buffer.find(0, cursor_pos())
  if #hits == 0 then return notify('nothing under the cursor') end
  erased(buffer.erase(0, { hits[1].a.id }))
end

--- Erase every annotation overlapping the visual selection (whole lines in linewise
--- Visual, the column range on each line in blockwise Visual).
function M.erase_visual()
  local mode = vim.fn.mode()
  local s, e = vim.fn.getpos('v'), vim.fn.getpos('.')
  if s[2] > e[2] or (s[2] == e[2] and s[3] > e[3]) then s, e = e, s end
  api.nvim_feedkeys(vim.keycode('<Esc>'), 'nx', false)
  local hits
  if mode == 'V' then
    local last = api.nvim_buf_get_lines(0, e[2] - 1, e[2], false)[1] or ''
    hits = buffer.find(0, { s[2] - 1, 0 }, { e[2] - 1, math.max(#last, 1) })
  elseif mode == '\22' then
    local c1, c2 = math.min(s[3], e[3]), math.max(s[3], e[3])
    local seen = {}
    hits = {}
    for row = s[2] - 1, e[2] - 1 do
      for _, h in ipairs(buffer.find(0, { row, c1 - 1 }, { row, c2 })) do
        if not seen[h.a.id] then
          seen[h.a.id] = true
          hits[#hits + 1] = h
        end
      end
    end
  else
    hits = buffer.find(0, { s[2] - 1, s[3] - 1 }, { e[2] - 1, e[3] })
  end
  erased(buffer.erase(0, vim.tbl_map(function(h)
    return h.a.id
  end, hits)))
end

function M.clear()
  erased(buffer.erase(0, vim.tbl_map(function(x)
    return x.annotation.id
  end, buffer.list(0))))
end

function M.restore_last()
  local n, missing = buffer.restore(0)
  if n == 0 then return notify('nothing to restore') end
  notify(('restored %d%s'):format(n, missing > 0 and (' (%d detached: text not found)'):format(missing) or ''))
end

function M.next()
  require('earmark.nav').next()
end

function M.prev()
  require('earmark.nav').prev()
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
  end, { set = v1.set, first = v1.label, existing = vim.list_slice(h.a.values, 2) })
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
  end, { existing = h.a.values })
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
  if name then require('earmark.ui.set_popup').show(name) end
end

--- `<leader>mS`: choose the label set from a list.
function M.pick_set()
  vim.ui.select(sets.order, {
    prompt = 'Label set',
    format_item = function(name)
      local set = sets.by_name[name]
      local src = set.source and (' · ' .. vim.fn.fnamemodify(set.source, ':~:.')) or ''
      return ('%s%s  (%d labels%s)'):format(name, name == sets.current and ' ✓' or '', #set.labels, src)
    end,
  }, function(name)
    if name then M.use_set(name) end
  end)
end

--- Load the label sets of the project `buf` belongs to (and pick up edited set files).
local function sync_sets(buf)
  local root
  if vim.bo[buf].buftype == '' and api.nvim_buf_get_name(buf) ~= '' then
    local doc = require('earmark.store').doc(buf)
    root = doc and doc.root
  end
  local switch = root and root ~= sets.root
  if switch or sets.files_changed(config.options) then
    sets.load(config.options, switch and root or nil)
    for b in pairs(buffer.state) do
      buffer.rerender(b)
    end
    return true
  end
end
M._sync_sets = sync_sets

function M.use_set(name)
  if not sets.by_name[name] then return notify('no label set "' .. tostring(name) .. '"', vim.log.levels.WARN) end
  sets.current = name
  notify('label set: ' .. name)
end

--- `<leader>mm`: open (or close) the note of the annotation under the cursor; a count
--- picks the n-th overlapping one, innermost first.
function M.note()
  local note = require('earmark.ui.note')
  local h
  if note.active then
    local hits = buffer.find(0, cursor_pos())
    h = hits[math.min(math.max(1, vim.v.count), math.max(#hits, 1))]
  else
    h = hit_under_cursor()
  end
  -- the same key closes the open note, unless the cursor is on another annotation (a
  -- split note stays open while you work in the text): then that one's note opens
  if note.active and (not h or h.a.id == note.active.id) then return note.close() end
  if h then note.open(0, h.a.id) end
end

---------------------------------------------------------------------------
-- Pickers, review, quickfix, scratch
---------------------------------------------------------------------------

local function picker()
  return require('earmark.ui.picker')
end

--- `:Earmark pick [query]` / `<leader>mp`: annotations in this buffer.
local function pick_file(args)
  local p = picker()
  local q = type(args) == 'table' and table.concat(args, ' ') or nil
  p.pick(p.filter(p.doc_items(0), q), { prompt = 'Annotations', on_choice = p.jump_to })
end
M.pick_file = pick_file

--- `:Earmark pick_all [query]` / `<leader>mP`: annotations in the whole project.
function M.pick_all(args)
  local p = picker()
  local q = type(args) == 'table' and table.concat(args, ' ') or nil
  p.pick(p.filter(p.project_items(0), q), { prompt = 'Annotations in project', on_choice = p.jump_to })
end

function M.review()
  require('earmark.ui.review').open(0)
end

function M.diff()
  local h = hit_under_cursor()
  if h then require('earmark.ui.review').diff(0, h.a.id) end
end

--- `:'<,'>Earmark reanchor`: attach an annotation (from the review list, else the one under
--- the cursor) to the selected text.
function M.reanchor(_, range)
  if not range then return notify('select the new text first (:\'<,\'>Earmark reanchor)') end
  local s, e = vim.fn.getpos("'<"), vim.fn.getpos("'>")
  local line = api.nvim_buf_get_lines(0, e[2] - 1, e[2], false)[1] or ''
  local ec = math.min(e[3], #line)
  -- include the whole last character
  while ec < #line and line:byte(ec + 1) >= 0x80 and line:byte(ec + 1) < 0xC0 do
    ec = ec + 1
  end
  if vim.fn.visualmode() == 'V' then s[3], ec = 1, #line end
  require('earmark.ui.review').reanchor_to_selection(0, { s[2] - 1, s[3] - 1 }, { e[2] - 1, ec })
end

--- `{Visual}<leader>mR`: the same as `:'<,'>Earmark reanchor`.
function M.reanchor_visual()
  api.nvim_feedkeys(vim.keycode('<Esc>'), 'nx', false)
  M.reanchor(nil, { vim.fn.line("'<"), vim.fn.line("'>") })
end

--- `:Earmark check`: one line per annotation (status, placement score, how it was placed,
--- text). Headless (scripts, CI), it exits with status 1 when any annotation is detached.
function M.check()
  local buf = api.nvim_get_current_buf()
  local S = buffer.get(buf)
  if not S then return notify('this buffer cannot be annotated') end
  local lines, detached = {}, 0
  for _, x in ipairs(buffer.list(buf)) do
    local a = x.annotation
    if a.status == 'detached' then detached = detached + 1 end
    local q = (a.quote or ''):gsub('\n', '⏎')
    if vim.fn.strchars(q) > 50 then q = vim.fn.strcharpart(q, 0, 49) .. '…' end
    lines[#lines + 1] = ('%-9s %4s  %-9s %s  "%s"'):format(
      a.status, a.score and (math.floor(a.score * 100 + 0.5) .. '%') or '100%', a.how or 'exact',
      x.s and ('%d:%d'):format(x.s[1] + 1, x.s[2] + 1) or '-', q)
  end
  if #lines == 0 then lines[1] = 'no annotations' end
  if #api.nvim_list_uis() == 0 then
    io.stdout:write(table.concat(lines, '\n') .. '\n')
    if detached > 0 then vim.cmd('cquit 1') end
  else
    api.nvim_echo({ { table.concat(lines, '\n') } }, true, {})
  end
  return lines
end

--- `:Earmark qf [all] [query]`: annotations into the quickfix list.
function M.qf(args)
  args = args or {}
  local all = args[1] == 'all'
  if all then table.remove(args, 1) end
  local p = picker()
  local items = p.filter(all and p.project_items(0) or p.doc_items(0), table.concat(args, ' '))
  local qf = {}
  for _, it in ipairs(items) do
    if it.pos then
      qf[#qf + 1] = {
        bufnr = it.buf,
        filename = not it.buf and it.file or nil,
        lnum = it.pos[1] + 1,
        col = it.pos[2] + 1,
        end_lnum = it.end_pos and it.end_pos[1] + 1 or nil,
        end_col = it.end_pos and it.end_pos[2] + 1 or nil,
        text = it.text:gsub('^[^\n]-%d+:%d+  ', ''),
        user_data = { earmark = it.annotation.id },
      }
    end
  end
  if #qf == 0 then return notify('no annotations') end
  vim.fn.setqflist({}, ' ', { title = 'earmark', items = qf })
  vim.cmd('copen')
end

--- `:Earmark scratch`: reopen an annotated scratch buffer from its saved text.
function M.scratch()
  local store = require('earmark.store')
  local dir = config.options.storage_dir .. '/scratch'
  local entries = {}
  for _, path in ipairs(vim.fn.globpath(dir, '*.json', false, true)) do
    local rec = store.read(path)
    if rec and rec.doc then
      local snap = store.snap_path(path)
      local lines = store.read_snapshot(snap, rec)
      if lines then
        local first = ''
        for _, l in ipairs(lines) do
          if l:match('%S') then
            first = vim.trim(l)
            break
          end
        end
        entries[#entries + 1] = {
          id = rec.doc.key,
          lines = lines,
          filetype = rec.doc.filetype,
          n = #(rec.annotations or {}),
          when = vim.fn.getftime(path),
          text = first,
        }
      end
    end
  end
  if #entries == 0 then return notify('no saved scratch buffers') end
  table.sort(entries, function(x, y) return x.when > y.when end)
  vim.ui.select(entries, {
    prompt = 'Reopen scratch buffer',
    format_item = function(x)
      return ('%s  %d annotation%s  %s'):format(os.date('%Y-%m-%d %H:%M', x.when), x.n, x.n == 1 and '' or 's', x.text:sub(1, 50))
    end,
  }, function(x)
    if not x then return end
    for b, S in pairs(buffer.state) do
      if S.doc.kind == 'scratch' and S.doc.key == x.id and api.nvim_buf_is_valid(b) then
        return api.nvim_set_current_buf(b)
      end
    end
    local buf = api.nvim_create_buf(true, true)
    vim.b[buf].earmark_doc = x.id
    api.nvim_buf_set_lines(buf, 0, -1, false, x.lines)
    if x.filetype and x.filetype ~= '' then vim.bo[buf].filetype = x.filetype end
    api.nvim_set_current_buf(buf)
    buffer.get(buf)
  end)
end

---------------------------------------------------------------------------
-- Export, occurrences, regrow, colour
---------------------------------------------------------------------------

--- `<leader>mo`: give every other occurrence of the annotated text the same labels.
function M.occurrences()
  local h = hit_under_cursor()
  if not h then return end
  local buf = api.nvim_get_current_buf()
  local anchor = require('earmark.anchor')
  local t = anchor.text(api.nvim_buf_get_lines(buf, 0, -1, false))
  local quote = h.a.quote
  if not quote or quote == '' then return end
  local n, init = 0, 1
  while true do
    local f = t.str:find(quote, init, true)
    if not f then break end
    init = f + #quote
    local sr, sc = anchor.off_to_pos(t, f - 1)
    local er, ec = anchor.off_to_pos(t, f - 1 + #quote)
    local s, e = { sr, sc }, { er, ec }
    if not (sr == h.s[1] and sc == h.s[2]) then
      local existing
      for _, x in ipairs(buffer.find(buf, s, e)) do
        if x.s[1] == sr and x.s[2] == sc and x.e[1] == er and x.e[2] == ec then existing = x end
      end
      if not existing then
        local a = buffer.add(buf, s, e, vim.deepcopy(h.a.values[1]))
        if a and #h.a.values > 1 then buffer.set_values(buf, a.id, vim.deepcopy(h.a.values)) end
        n = n + 1
      end
    end
  end
  notify(('annotated %d more occurrence%s'):format(n, n == 1 and '' or 's'))
end

local regrow_target
--- `<leader>mg{motion}` / `{Visual}<leader>mg`: the annotation under the cursor now covers
--- the motion or selection (its note, labels and tags stay).
function M.regrow_expr()
  local mode = api.nvim_get_mode().mode
  local hits
  if mode:match('^[vV\22]') then
    local a, b = vim.fn.getpos('v'), vim.fn.getpos('.')
    if a[2] > b[2] or (a[2] == b[2] and a[3] > b[3]) then a, b = b, a end
    hits = buffer.find(0, { a[2] - 1, a[3] - 1 }, { b[2] - 1, b[3] })
  else
    hits = buffer.find(0, cursor_pos())
  end
  if #hits == 0 then
    vim.schedule(function()
      notify('nothing under the cursor')
    end)
    return '<Ignore>'
  end
  regrow_target = hits[1].a.id
  vim.o.operatorfunc = "v:lua.require'earmark'.regrow_opfunc"
  return 'g@'
end

function M.regrow_opfunc(motion)
  local id = regrow_target
  regrow_target = nil
  if not id then return end
  local spans = region(motion)
  if #spans == 0 then return end
  local s, e = spans[1].s, spans[#spans].e
  if buffer.reanchor(0, id, s, e, { accept = true }) then
    pcall(api.nvim_win_set_cursor, 0, { s[1] + 1, s[2] })
  end
end

--- `:Earmark color #rrggbb` colours the label under the cursor differently in this file;
--- `:Earmark color reset` undoes it.
function M.color(args)
  local h = hit_under_cursor()
  if not h then return end
  local arg = args and args[1]
  if not arg then
    local cur = sets.color(h.a.values[1], buffer.get(0) and buffer.get(0).colors)
    return notify(('%s is %s; :Earmark color #rrggbb or reset'):format(buffer.display_name(0, h.a.values[1]), cur or '?'))
  end
  if arg == 'reset' then
    buffer.set_color(0, h.a.values[1], nil)
    return
  end
  if not arg:match('^#%x%x%x%x%x%x$') then return notify('colour must look like #e06c75', vim.log.levels.WARN) end
  buffer.set_color(0, h.a.values[1], arg:lower())
end

function M.zk()
  local h = hit_under_cursor()
  if h then require('earmark.zk').promote(0, h.a.id) end
end

function M.tags()
  local h = hit_under_cursor()
  if h then require('earmark.ui.tags_picker').open(0, h.a.id) end
end

function M.toggle_indicators()
  require('earmark.render').toggle_indicators()
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
      local name = sets.label(v) and buffer.display_name(0, v) or (v.label .. '?')
      return ('%s (%s·%s)'):format(name, v.set, v.label)
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

--- Annotations at a position (default: cursor), innermost first: { annotation, s, e }.
function M.at(buf, pos)
  return vim.tbl_map(function(h)
    return { annotation = h.a, a = h.a, s = h.s, e = h.e }
  end, buffer.find(buf or 0, pos or cursor_pos()))
end

--- An annotation by id in a buffer (nil if it isn't there).
function M.get(buf, id)
  return buffer.annotation(buf or 0, id)
end

--- Set (or clear with nil/'') the note of an annotation.
function M.set_note(buf, id, text)
  return buffer.set_note(buf or 0, id, text)
end

--- Replace the explicit tags of an annotation (tags written in its note stay).
function M.set_tags(buf, id, list)
  return buffer.set_tags(buf or 0, id, list)
end

--- Replace the labels of an annotation: { { set =, label =, choice =?, text =? }, ... }.
function M.set_values(buf, id, values)
  return buffer.set_values(buf or 0, id, values)
end

--- Move annotations to the trash (restorable). Returns how many.
function M.erase(buf, ids)
  return buffer.erase(buf or 0, ids)
end

--- Restore the most recently erased batch.
function M.restore(buf)
  return buffer.restore(buf or 0)
end

--- The value a plain `gh` offers first (and the statusline shows).
function M.next_value()
  local key = first_key()
  return key and { set = sets.current, label = key } or nil
end

--- Make `value` the one `gh` offers first, switching to its set.
function M.use_value(value)
  if not sets.label(value) then return end
  sets.current = value.set
  last_value = { set = value.set, label = value.label }
  pcall(vim.cmd, 'redrawstatus!')
  notify(('next label: %s·%s %s'):format(value.set, value.label,
    sets.color_name(value, (buffer.state[api.nvim_get_current_buf()] or {}).colors) or ''))
end

--- Name a label for one document (nil clears it).
function M.rename_label(buf, value, name)
  return buffer.rename_label(buf or 0, value, name)
end

--- Names given to labels in a document: { ["set/key"] = name }.
function M.names(buf)
  return buffer.names(buf or 0)
end

--- Markdown export lines (see README, Export).
function M.export(buf, opts)
  return require('earmark.export').markdown(buf or 0, opts)
end

--- Open the annotation picker: opts.scope = 'file' (default) | 'project', opts.query.
function M.pick(opts)
  opts = opts or {}
  local q = opts.query and vim.split(opts.query, '%s+') or nil
  if opts.scope == 'project' then return M.pick_all(q) end
  return pick_file(q)
end

--- Show / hide the hover for what's under the cursor.
M.hover = {
  show = function()
    local hits = buffer.find(0, cursor_pos())
    if #hits > 0 then require('earmark.ui.hover').show(api.nvim_get_current_win(), hits, false) end
  end,
  hide = function()
    require('earmark.ui.hover').hide()
  end,
}

--- Run `fn(data)` on an earmark event: 'Changed', 'Add', 'Update', 'Erase', 'Restore',
--- 'Repair', 'Note', 'Load' (or the full 'EarmarkNote'). data = { buf, action, ids }.
--- Returns the autocmd id.
function M.on(event, fn)
  local pattern = event:match('^Earmark') and event or ('Earmark' .. event:sub(1, 1):upper() .. event:sub(2))
  return api.nvim_create_autocmd('User', {
    pattern = pattern,
    callback = function(ev)
      fn(ev.data)
    end,
  })
end

--- Statusline component: `%#..#` string for the current buffer (see README).
--- opts.hl: highlight group of the section it goes in (its background is kept).
function M.statusline(opts)
  return require('earmark.ui.statusline').render(last_value, opts)
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
  A({ name = 'erase', desc = 'erase annotation(s)', modes = { n = M.erase_under_cursor, x = M.erase_visual } })
  A({ name = 'clear', desc = 'erase all annotations in this buffer', modes = { n = M.clear } })
  A({ name = 'restore', desc = 'restore last erased', modes = { n = M.restore_last } })
  A({ name = 'next', desc = 'next annotation', modes = { n = M.next } })
  A({ name = 'prev', desc = 'previous annotation', modes = { n = M.prev } })
  A({ name = 'next_same', desc = 'next with the same label', modes = { n = function() require('earmark.nav').next_same() end } })
  A({ name = 'prev_same', desc = 'previous with the same label', modes = { n = function() require('earmark.nav').prev_same() end } })
  A({ name = 'jump', desc = 'jump to an annotation (flash)', modes = { n = function() require('earmark.nav').jump() end } })
  A({ name = 'pick', desc = 'pick an annotation in this file', modes = { n = pick_file }, cmd = pick_file })
  A({ name = 'pick_all', desc = 'pick an annotation in the project', modes = { n = M.pick_all }, cmd = M.pick_all })
  A({ name = 'review', desc = 'review stale/detached annotations', modes = { n = M.review } })
  A({ name = 'diff', desc = 'original vs current text', modes = { n = M.diff } })
  A({ name = 'reanchor', desc = 'attach an annotation to the selection', modes = { x = M.reanchor_visual }, cmd = M.reanchor })
  A({ name = 'qf', desc = 'annotations to quickfix', modes = { n = function() M.qf({}) end }, cmd = M.qf, complete = function() return { 'all' } end })
  A({ name = 'scratch', desc = 'reopen a scratch buffer', cmd = M.scratch })
  A({ name = 'check', desc = 'list annotations with their placement', cmd = M.check })
  A({ name = 'export', desc = 'export annotations to Markdown', modes = { n = function() require('earmark.export').run(0) end } })
  A({ name = 'zk', desc = 'promote to a zk note', modes = { n = M.zk } })
  A({ name = 'occurrences', desc = 'annotate other occurrences of this text', modes = { n = M.occurrences } })
  A({ name = 'regrow', desc = 'move the annotation onto a motion', modes = { n = M.regrow_expr, x = M.regrow_expr }, expr = true, cmd = false })
  A({ name = 'palette', desc = 'the set\'s colours as labelled patches', modes = { n = function() require('earmark.ui.palette').open() end },
    cmd = function(args) require('earmark.ui.palette').open(args[1]) end,
    complete = function() return sets.order end })
  A({ name = 'color', desc = 'colour this label differently in this file', cmd = M.color,
    complete = function() return { 'reset' } end })
  A({ name = 'cycle_set', desc = 'next label set', modes = { n = M.cycle_set } })
  A({ name = 'pick_set', desc = 'choose the label set', modes = { n = M.pick_set } })
  A({ name = 'peek', desc = 'show annotation details', modes = { n = M.peek } })
  A({ name = 'note', desc = 'open/close note', modes = { n = M.note } })
  A({ name = 'toggle_hover', desc = 'automatic hover on/off', modes = { n = M.toggle_hover } })
  A({ name = 'tags', desc = 'add/remove tags', modes = { n = M.tags } })
  A({ name = 'toggle_indicators', desc = 'show/hide tags at line ends', modes = { n = M.toggle_indicators } })
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
      sets.load(config.options, nil)
      for b in pairs(buffer.state) do
        buffer.rerender(b)
      end
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
    sync_sets(ev.buf)
    if buffer.state[ev.buf] then
      buffer.reloaded(ev.buf) -- external reload: place again from the in-memory snapshot
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
      -- counts and statuses changed after the edit was drawn: show them in statuslines now
      pcall(vim.cmd, 'redrawstatus!')
    end))
  end)
  au('InsertEnter', function(ev)
    buffer.insert_entered(ev.buf)
  end)
  au('InsertLeave', function(ev)
    buffer.insert_left(ev.buf)
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
  au({ 'BufEnter', 'FocusGained' }, function(ev)
    sync_sets(ev.buf)
  end)
  au('BufWritePost', function()
    sync_sets(api.nvim_get_current_buf())
  end, { pattern = { '*/earmark/sets/*.lua', '*/earmark/sets/*.json', '*/.earmark/sets/*.lua', '*/.earmark/sets/*.json' } })
  -- a label named elsewhere in the project gets that name here too
  au('User', function(ev)
    local d = ev.data
    if d and d.ids and buffer.state[d.buf] then names().adopt(d.buf, d.ids) end
  end, { pattern = { 'EarmarkAdd', 'EarmarkUpdate' } })
  require('earmark.ui.hover').setup(au)
  au('ColorScheme', function()
    sets.apply_highlights()
    require('earmark.render').apply_highlights()
    require('earmark.ui.statusline').apply_highlights()
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
  -- which-key: name the <leader>m group so the prefix doesn't show as "+prefix"
  local uses_prefix = false
  for _, lhs in pairs(config.options.keys or {}) do
    if type(lhs) == 'string' and vim.startswith(lhs, '<leader>m') then uses_prefix = true end
  end
  if uses_prefix then
    vim.schedule(function()
      local ok, wk = pcall(require, 'which-key')
      if ok and type(wk.add) == 'function' then
        pcall(wk.add, { { '<leader>m', group = 'earmark', icon = { icon = '󰃉', color = 'yellow' } } })
      end
    end)
  end
  -- Buffers loaded before setup (e.g. the file Neovim was started with).
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == '' and api.nvim_buf_get_name(buf) ~= '' then
      buffer.get(buf)
    end
  end
end

return M
