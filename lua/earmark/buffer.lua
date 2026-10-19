-- Per-buffer annotation state: extmarks for live tracking, a text snapshot for repairs and
-- persistence, and the trash.
--
-- Invariant: `S.snap.lines` is the buffer text at some recent moment, and `S.snap.pos[id]`
-- is where each live annotation was at that same moment. Anything that breaks an extmark
-- (whole-buffer replace, :e!, external reload, deleting the span) is repaired by diffing
-- the snapshot against the current text.
local anchor = require('earmark.anchor')
local config = require('earmark.config')
local log = require('earmark.log')
local sets = require('earmark.sets')
local store = require('earmark.store')

local api = vim.api
local M = {}

M.ns = api.nvim_create_namespace('earmark')
M.ns_swatch = api.nvim_create_namespace('earmark_swatch')

--- @class earmark.Annotation
--- @field id string
--- @field values {set: string, label: string, choice: string?, text: string?}[]
--- @field quote string            text of the span when last seen
--- @field prefix string
--- @field suffix string
--- @field original_quote string   text when first annotated
--- @field status 'ok'|'stale'|'ambiguous'|'detached'
--- @field note string?            markdown note
--- @field tags string[]?          explicit tags (tags written in the note are parsed, not stored)
--- @field score number?           confidence of the last re-anchoring (absent = exact)
--- @field how string?             how it was last re-anchored
--- @field zk string?              path of a zk note this annotation was promoted to
--- @field created integer
--- @field updated integer
--- @field s integer[]?            last known start (snapshot coordinates)
--- @field e integer[]?            last known end

--- @class earmark.BufState
--- @field doc earmark.Doc
--- @field annos table<string, earmark.Annotation>
--- @field ext table<string, integer>   annotation id -> extmark id
--- @field by_ext table<integer, string> extmark id -> annotation id
--- @field swatch table<string, integer> annotation id -> extmark of its label 3+ swatches
--- @field names table<string, string>  "set/key" -> name of that label in this doc
--- @field colors table<string, string> "set/key" -> colour override in this doc
--- @field snap {lines: string[], pos: table<string, {s: integer[], e: integer[]}>}
--- @field trash table[]
--- @field readonly string?             reason saving is disabled (unreadable record)
--- @field timer uv.uv_timer_t?

M.state = {} --- @type table<integer, earmark.BufState>

local function now()
  return os.time()
end

--- Fire `User EarmarkChanged` and the specific `User Earmark<Action>` event.
local function emit(buf, action, ids)
  if buf == 0 then buf = api.nvim_get_current_buf() end
  local data = { buf = buf, action = action, ids = ids }
  for _, pattern in ipairs({ 'EarmarkChanged', 'Earmark' .. action:sub(1, 1):upper() .. action:sub(2) }) do
    local ok, err = pcall(api.nvim_exec_autocmds, 'User', { pattern = pattern, modeline = false, data = data })
    if not ok then log.error('User %s handler: %s', pattern, err) end
  end
  if M.cache_positions then M.cache_positions(buf) end
end
M.emit = emit

local function bufnr(buf)
  return (buf == nil or buf == 0) and api.nvim_get_current_buf() or buf
end

local function lines_of(buf)
  return api.nvim_buf_get_lines(buf, 0, -1, false)
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------

local function priority(s, e)
  -- Smaller spans draw on top of larger ones they overlap.
  local size = (e[1] - s[1]) * 200 + (e[2] - s[2])
  return 4200 - math.max(0, math.min(4000, size))
end

--- Place (or move) the extmark for an annotation.
local function render(buf, S, a, s, e)
  local opts = {
    end_row = e[1],
    end_col = e[2],
    hl_group = sets.group(a.values[1], S.colors, a.status),
    priority = priority(s, e),
    invalidate = true,
    undo_restore = true,
    strict = false,
  }
  -- while text replacing an edge of the span is typed (see `M.track`), that edge takes it in
  local g = S.grow and S.grow[a.id]
  if g then
    opts.right_gravity = not g.start
    opts.end_right_gravity = g.finish or false
  end
  local old = S.ext[a.id]
  if old then
    -- an invalidated extmark can't be moved back to life; replace it
    local m = api.nvim_buf_get_extmark_by_id(buf, M.ns, old, { details = true })
    if m[3] and m[3].invalid then
      api.nvim_buf_del_extmark(buf, M.ns, old)
      S.by_ext[old] = nil
    else
      opts.id = old
    end
  end
  local ext = api.nvim_buf_set_extmark(buf, M.ns, s[1], s[2], opts)
  S.ext[a.id], S.by_ext[ext] = ext, a.id
  M.render_swatch(buf, S, a, e)
end

--- With `overlap.extra = 'squares'`, labels 3 and up: one small square per label right after
--- the span, in its colour. (Otherwise they share the undercurl, drawn by `render.lua`.)
function M.render_swatch(buf, S, a, e)
  local old = S.swatch[a.id]
  if #a.values < 3 or not e or config.options.overlap.extra ~= 'squares' then
    if old then
      pcall(api.nvim_buf_del_extmark, buf, M.ns_swatch, old)
      S.swatch[a.id] = nil
    end
    return
  end
  local glyph = vim.g.have_nerd_font == false and '#' or '■'
  local chunks = {}
  for i = 3, #a.values do
    local hex = sets.color(a.values[i], S.colors)
    chunks[#chunks + 1] = { glyph, hex and sets.fg_group(hex) or 'EarmarkUnknown' }
  end
  S.swatch[a.id] = api.nvim_buf_set_extmark(buf, M.ns_swatch, e[1], e[2], {
    id = old,
    virt_text = chunks,
    virt_text_pos = 'inline',
    right_gravity = false, -- text typed right after the span goes after the squares
    undo_restore = true,
    strict = false,
  })
end

--- Current {s, e} of an annotation from its extmark, or nil if it is broken
--- (missing, invalidated, or collapsed to nothing while it had text).
local function live_pos(buf, S, id)
  local ext = S.ext[id]
  if not ext then return nil end
  local m = api.nvim_buf_get_extmark_by_id(buf, M.ns, ext, { details = true })
  if not m[1] or (m[3] and m[3].invalid) then return nil end
  local s, e = { m[1], m[2] }, { m[3].end_row or m[1], m[3].end_col or m[2] }
  -- a whole-buffer replace can leave a multi-line mark inverted (start after its end)
  if s[1] > e[1] or (s[1] == e[1] and s[2] > e[2]) then return nil end
  local growing = S.grow and S.grow[id]
  if s[1] == e[1] and s[2] == e[2] and S.annos[id].quote ~= '' and not growing then return nil end
  return s, e
end

local function drop_ext(buf, S, id)
  local ext = S.ext[id]
  if ext then
    pcall(api.nvim_buf_del_extmark, buf, M.ns, ext)
    S.ext[id], S.by_ext[ext] = nil, nil
  end
  local sw = S.swatch[id]
  if sw then
    pcall(api.nvim_buf_del_extmark, buf, M.ns_swatch, sw)
    S.swatch[id] = nil
  end
end

local function detach(buf, S, a)
  drop_ext(buf, S, a.id)
  a.status = 'detached'
end

local function status_for(a, text)
  return anchor.similarity(text, a.original_quote) >= config.options.stale_threshold and 'ok' or 'stale'
end

--- Record how a re-anchoring placed an annotation (score/how are omitted when exact).
local function set_placement(a, r)
  a.how = (r.how and r.how ~= 'same' and r.how ~= 'mapped') and r.how or nil
  a.score = (r.score and r.score < 1) and r.score or nil
  if r.ambiguous then
    a.status = 'ambiguous'
  elseif a.status == 'ambiguous' then
    a.status = 'ok'
  end
end

---------------------------------------------------------------------------
-- Snapshot and repair
---------------------------------------------------------------------------

--- Record the current text and every live annotation's position in it. Also refreshes each
--- annotation's quote/context/status from the live text. Returns true if a status changed.
function M.refresh_snapshot(buf, S)
  -- extmarks broken since the last snapshot (e.g. a save or an annotation right after a
  -- whole-buffer replace, before the debounced repair) are repaired while it can place them
  for id, a in pairs(S.annos) do
    if a.status ~= 'detached' and S.snap.pos[id] and not live_pos(buf, S, id) then
      M.repair(buf, S)
      break
    end
  end
  local lines = lines_of(buf)
  local t = anchor.text(lines)
  local pos = {}
  local ctx = config.options.context
  local restatus = false
  for id, a in pairs(S.annos) do
    if a.status ~= 'detached' then
      local s, e = live_pos(buf, S, id)
      if s then
        pos[id] = { s = s, e = e }
        local text = anchor.span_text(t, s, e)
        if text ~= a.quote then
          local was = a.status
          a.quote = text
          a.status = status_for(a, text)
          a.updated = now()
          -- ok <-> stale changes the highlight group (stale is drawn underdashed)
          if a.status ~= was then
            render(buf, S, a, s, e)
            restatus = true
          end
        end
        -- keep the context as long as it was made (longer where the quote isn't unique)
        local n = math.min(anchor.MAX_CONTEXT + 16, math.max(ctx, #(a.prefix or ''), #(a.suffix or '')))
        a.prefix, a.suffix = anchor.context(t, s, e, n)
        a.s, a.e = s, e
      end
    end
  end
  S.snap = { lines = lines, pos = pos }
  return restatus
end

--- Repair annotations whose extmarks broke, and try to re-attach detached ones.
--- Returns true if anything changed.
function M.repair(buf, S)
  local broken, changed = {}, false
  for id, a in pairs(S.annos) do
    if a.status ~= 'detached' and not live_pos(buf, S, id) then
      local p = S.snap.pos[id]
      if p then
        broken[#broken + 1] = { id = id, s = p.s, e = p.e, quote = a.quote, prefix = a.prefix, suffix = a.suffix }
      else
        detach(buf, S, a)
        changed = true
      end
    end
  end
  local lines = lines_of(buf)
  if #broken > 0 then
    local res = anchor.reanchor(S.snap.lines, lines, broken)
    for _, it in ipairs(broken) do
      local a, r = S.annos[it.id], res[it.id]
      if r then
        set_placement(a, r)
        render(buf, S, a, r.s, r.e)
      else
        detach(buf, S, a)
      end
    end
    changed = true
  end
  -- Detached annotations come back when their text reappears (undo, paste).
  local t
  for _, a in pairs(S.annos) do
    if a.status == 'detached' then
      t = t or anchor.text(lines)
      local near = a.s and anchor.pos_to_off(t, a.s[1], a.s[2]) or nil
      local so, eo = anchor.locate(t, a, near)
      if so then
        local sr, sc = anchor.off_to_pos(t, so)
        local er, ec = anchor.off_to_pos(t, eo)
        a.status = status_for(a, t.str:sub(so + 1, eo))
        render(buf, S, a, { sr, sc }, { er, ec })
        changed = true
      end
    end
  end
  return changed
end

--- Called (debounced) after text changes.
function M.on_change(buf)
  buf = bufnr(buf)
  local S = M.state[buf]
  if not S or not api.nvim_buf_is_valid(buf) then return end
  local repaired = M.repair(buf, S)
  -- also keeps quotes and stale status current while text inside spans is edited
  local restatus = M.refresh_snapshot(buf, S)
  if repaired or restatus then
    M.schedule_save(buf)
    emit(buf, 'repair', nil)
  end
end

---------------------------------------------------------------------------
-- Persistence
---------------------------------------------------------------------------

local function serialize(a)
  return {
    id = a.id,
    values = a.values,
    s = a.s,
    e = a.e,
    quote = a.quote,
    prefix = a.prefix,
    suffix = a.suffix,
    original_quote = a.original_quote,
    status = a.status,
    note = (a.note and a.note ~= '') and a.note or nil,
    tags = (a.tags and #a.tags > 0) and a.tags or nil,
    score = a.score,
    how = a.how,
    zk = a.zk,
    created = a.created,
    updated = a.updated,
  }
end

local function by_position(x, y)
  local xs, ys = x.s or { math.huge, 0 }, y.s or { math.huge, 0 }
  if x.status == 'detached' ~= (y.status == 'detached') then return y.status == 'detached' end
  if xs[1] ~= ys[1] then return xs[1] < ys[1] end
  if xs[2] ~= ys[2] then return xs[2] < ys[2] end
  return x.id < y.id
end

function M.save(buf)
  buf = bufnr(buf)
  local S = M.state[buf]
  if not S then return end
  if S.timer then S.timer:stop() end
  if S.readonly or not api.nvim_buf_is_valid(buf) then return end
  if api.nvim_buf_is_loaded(buf) then M.refresh_snapshot(buf, S) end
  local list = {}
  for _, a in pairs(S.annos) do
    list[#list + 1] = serialize(a)
  end
  if #list == 0 and #S.trash == 0 and next(S.names) == nil and next(S.colors) == nil then
    if vim.uv.fs_stat(S.doc.record) then
      store.write(S.doc.record, nil)
      store.write_snapshot(S.doc.snap, nil)
    end
    return
  end
  table.sort(list, by_position)
  local ok, err = store.write(S.doc.record, {
    version = store.VERSION,
    doc = { kind = S.doc.kind, key = S.doc.key, name = api.nvim_buf_get_name(buf), filetype = vim.bo[buf].filetype },
    fingerprint = store.fingerprint(S.snap.lines),
    annotations = list,
    trash = S.trash,
    names = next(S.names) and S.names or nil,
    colors = next(S.colors) and S.colors or nil,
  })
  if ok then ok, err = store.write_snapshot(S.doc.snap, S.snap.lines) end
  if not ok then
    log.error('could not save %s: %s', S.doc.record, tostring(err))
    vim.notify('earmark: could not save ' .. S.doc.record .. ': ' .. tostring(err), vim.log.levels.ERROR)
  end
end

function M.schedule_save(buf)
  buf = bufnr(buf)
  local S = M.state[buf]
  if not S then return end
  S.timer = S.timer or vim.uv.new_timer()
  S.timer:stop()
  S.timer:start(
    500,
    0,
    vim.schedule_wrap(function()
      M.save(buf)
    end)
  )
end

--- Load annotations for a buffer from its record, re-anchoring against the current text.
local function load(buf, S)
  local rec, err = store.read(S.doc.record)
  if err then
    S.readonly = err
    log.warn('%s (annotations for this buffer will not be saved)', err)
    vim.notify('earmark: ' .. err .. ' (annotations for this buffer will not be saved)', vim.log.levels.WARN)
    return
  end
  local snap_path = S.doc.snap
  local lines = lines_of(buf)
  if not rec and S.doc.kind == 'file' then
    local rerooted = store.find_rerooted(S.doc)
    local moved = rerooted or (not (#lines == 1 and lines[1] == '') and store.find_renamed(S.doc, lines))
    if moved then
      rec = store.read(moved)
      if rec then
        S.moved_from = moved
        snap_path = store.snap_path(moved)
        if not rerooted then
          vim.notify('earmark: annotations followed a renamed file (' .. vim.fs.basename(moved) .. ')')
        end
      end
    end
  end
  if not rec then return end
  S.trash = rec.trash or {}
  S.names = type(rec.names) == 'table' and rec.names or {}
  S.colors = type(rec.colors) == 'table' and rec.colors or {}
  local snapshot = store.read_snapshot(snap_path, rec)
  local items = {}
  for _, a in ipairs(rec.annotations or {}) do
    S.annos[a.id] = a
    if a.status ~= 'detached' and a.s and a.e then
      items[#items + 1] = { id = a.id, s = a.s, e = a.e, quote = a.quote, prefix = a.prefix, suffix = a.suffix }
    else
      a.status = 'detached'
    end
  end
  local res
  if snapshot then
    res = anchor.reanchor(snapshot, lines, items)
  else
    res = anchor.reanchor_by_quote(lines, items)
  end
  for _, it in ipairs(items) do
    local a, r = S.annos[it.id], res[it.id]
    if r then
      set_placement(a, r)
      render(buf, S, a, r.s, r.e)
    else
      a.status = 'detached'
    end
  end
  S.snap = { lines = snapshot or {}, pos = {} }
  M.repair(buf, S) -- re-attach anything detached whose text is present
  M.refresh_snapshot(buf, S)
  if S.moved_from then
    -- a buffer still open on the old path (renamed outside Neovim) must not write it back
    for _, other in pairs(M.state) do
      if other ~= S and other.doc.record == S.moved_from then
        other.readonly = 'its record moved to ' .. S.doc.record
      end
    end
    M.save(buf)
    store.write(S.moved_from, nil)
    store.write_snapshot(store.snap_path(S.moved_from), nil)
    S.moved_from = nil
  elseif (rec.version or 1) < store.VERSION then
    M.save(buf) -- migrate the record to the current schema
  end
  emit(buf, 'load', nil)
end

--- State for a buffer, created (and loaded from disk) on first use. Nil if the buffer
--- can't be annotated, or isn't loaded (it gets its state when it is: BufReadPost).
--- @return earmark.BufState?
function M.get(buf, opts)
  buf = bufnr(buf)
  local S = M.state[buf]
  if S then return S end
  if opts and opts.no_create then return nil end
  -- not before its text is read: an empty state would stay empty and save over the record
  if not api.nvim_buf_is_loaded(buf) then return nil end
  local doc = store.doc(buf)
  if not doc then return nil end
  S = { doc = doc, annos = {}, ext = {}, by_ext = {}, swatch = {}, names = {}, colors = {}, snap = { lines = {}, pos = {} }, trash = {} }
  M.state[buf] = S
  load(buf, S)
  if not S.snap.lines[1] then M.refresh_snapshot(buf, S) end
  M.track(buf, S)
  return S
end

--- The buffer's text was read again without unloading it (`:checktime`, 'autoread', `:e!`
--- on a buffer that stays loaded). Its extmarks stay where they were, now over unrelated
--- text, so drop them all and place every annotation again from the snapshot.
function M.reloaded(buf)
  buf = bufnr(buf)
  local S = M.state[buf]
  if not S then return end
  api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  api.nvim_buf_clear_namespace(buf, M.ns_swatch, 0, -1)
  S.ext, S.by_ext, S.swatch = {}, {}, {}
  S.grow, S.pending = nil, nil
  M.on_change(buf)
  M.cache_positions(buf)
end

--- Re-read a buffer's record from disk (e.g. after :e! or an external change).
function M.reload(buf)
  buf = bufnr(buf)
  local S = M.state[buf]
  if S then
    if S.timer then S.timer:close() end
    if S.change_timer then S.change_timer:close() end
    api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
    api.nvim_buf_clear_namespace(buf, M.ns_swatch, 0, -1)
    M.state[buf] = nil
  end
  return M.get(buf)
end

function M.forget(buf)
  buf = bufnr(buf)
  local S = M.state[buf]
  if not S then return end
  if S.timer and not S.timer:is_closing() then S.timer:close() end
  if S.change_timer and not S.change_timer:is_closing() then S.change_timer:close() end
  M.state[buf] = nil
  -- an unloaded buffer keeps its extmarks: without this, `:e` after an outside edit draws
  -- the old marks at their old places next to the ones loaded again
  if api.nvim_buf_is_valid(buf) then
    api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
    api.nvim_buf_clear_namespace(buf, M.ns_swatch, 0, -1)
  end
end

--- The buffer's document identity changed (:saveas, :file, scratch written to a file).
function M.rename(buf)
  buf = bufnr(buf)
  local S = M.state[buf]
  if not S then return end
  local doc = store.doc(buf)
  if not doc or doc.record == S.doc.record then return end
  local old = S.doc
  M.refresh_snapshot(buf, S)
  S.doc = doc
  M.save(buf)
  store.write(old.record, nil)
  store.write_snapshot(old.snap, nil)
end

---------------------------------------------------------------------------
-- Editing operations
---------------------------------------------------------------------------

--- Annotate [s, e) with `value`. If an annotation with exactly this span exists, `value`
--- is added to it as another label instead (so the two show as an overlap). Returns the
--- annotation, plus 'added' when it went onto an existing annotation or 'same' when that
--- annotation had the label already.
function M.add(buf, s, e, value, opts)
  local S = M.get(buf)
  if not S then return nil end
  if s[1] == e[1] and s[2] == e[2] then return nil end
  -- on exactly the span of an annotation, the label joins it, unless `separate` (then it is
  -- an annotation of its own, with its own note and tags)
  for id, a in pairs((opts and opts.separate) and {} or S.annos) do
    local ls, le = live_pos(buf, S, id)
    if ls and ls[1] == s[1] and ls[2] == s[2] and le[1] == e[1] and le[2] == e[2] then
      for _, v in ipairs(a.values) do
        if v.set == value.set and v.label == value.label and v.choice == value.choice then return a, 'same' end
      end
      a.values[#a.values + 1] = value
      a.updated = now()
      render(buf, S, a, s, e)
      M.refresh_snapshot(buf, S)
      M.schedule_save(buf)
      emit(buf, 'update', { id })
      return a, 'added'
    end
  end
  local t = anchor.text(lines_of(buf))
  local text = anchor.span_text(t, s, e)
  local pre, suf = anchor.unique_context(t, s, e, config.options.context)
  local t = now()
  local a = {
    id = store.uuid(),
    values = { value },
    quote = text,
    prefix = pre,
    suffix = suf,
    original_quote = text,
    status = 'ok',
    created = t,
    updated = t,
    s = s,
    e = e,
  }
  S.annos[a.id] = a
  render(buf, S, a, s, e)
  M.refresh_snapshot(buf, S)
  M.schedule_save(buf)
  emit(buf, 'add', { a.id })
  return a
end

--- Annotations overlapping [s, e) (or containing position s when e is nil), smallest first.
function M.find(buf, s, e)
  local S = M.get(buf, { no_create = true })
  if not S then return {} end
  local point = e == nil
  e = e or { s[1], s[2] + 1 }
  local function before(p, q)
    return p[1] < q[1] or (p[1] == q[1] and p[2] < q[2])
  end
  -- A cursor past the last character (empty line, end of line in Insert or with
  -- 'virtualedit') still belongs to a span that ends right there.
  local eol = false
  if point then
    local line = api.nvim_buf_get_lines(buf, s[1], s[1] + 1, false)[1] or ''
    eol = s[2] >= #line
  end
  local hits = {}
  for id, a in pairs(S.annos) do
    local as, ae = live_pos(buf, S, id)
    if as and before(as, e) and (before(s, ae) or (eol and ae[1] == s[1] and ae[2] == s[2] and before(as, s))) then
      hits[#hits + 1] = { a = a, s = as, e = ae, size = priority(as, ae) }
    end
  end
  table.sort(hits, function(x, y)
    if x.size ~= y.size then return x.size > y.size end
    -- the same size (separate annotations on the same text): the older first, so counts
    -- and the hover's numbers stay put
    if (x.a.created or 0) ~= (y.a.created or 0) then return (x.a.created or 0) < (y.a.created or 0) end
    return x.a.id < y.a.id
  end)
  return hits
end

--- Move annotations to the trash. Returns the number erased.
function M.erase(buf, ids)
  local S = M.get(buf, { no_create = true })
  if not S or #ids == 0 then return 0 end
  M.refresh_snapshot(buf, S)
  local batch, t = store.uuid(), now()
  local done = {}
  for _, id in ipairs(ids) do
    local a = S.annos[id]
    if a then
      done[#done + 1] = id
      local entry = serialize(a)
      entry.erased, entry.batch = t, batch
      S.trash[#S.trash + 1] = entry
      drop_ext(buf, S, id)
      S.annos[id], S.snap.pos[id] = nil, nil
    end
  end
  while #S.trash > 500 do
    table.remove(S.trash, 1)
  end
  if #done == 0 then return 0 end
  M.schedule_save(buf)
  emit(buf, 'erase', done)
  return #done
end

--- Set the note of an erased annotation still in the trash (a note being edited when its
--- annotation was erased). Returns true if it was found.
function M.set_trashed_note(buf, id, text)
  local S = M.get(bufnr(buf), { no_create = true })
  if not S then return false end
  for i = #S.trash, 1, -1 do
    local a = S.trash[i]
    if a.id == id then
      a.note = (text and text:match('%S')) and text or nil
      M.schedule_save(bufnr(buf))
      return true
    end
  end
  return false
end

--- Restore the most recently erased batch. Returns restored count and how many of those
--- could not be found in the current text (kept, as detached).
function M.restore(buf)
  local S = M.get(buf, { no_create = true })
  if not S or #S.trash == 0 then return 0, 0 end
  local batch = S.trash[#S.trash].batch
  local lines = lines_of(buf)
  local t = anchor.text(lines)
  local ids, missing = {}, 0
  while #S.trash > 0 and S.trash[#S.trash].batch == batch do
    local a = table.remove(S.trash)
    a.erased, a.batch = nil, nil
    S.annos[a.id] = a
    ids[#ids + 1] = a.id
    local near = a.s and anchor.pos_to_off(t, a.s[1], a.s[2]) or nil
    local so, eo
    if a.s and a.e and anchor.span_text(lines, a.s, a.e) == a.quote then
      so, eo = anchor.pos_to_off(t, a.s[1], a.s[2]), anchor.pos_to_off(t, a.e[1], a.e[2])
    else
      so, eo = anchor.locate(t, a, near)
    end
    if so and a.status ~= 'detached' then
      local sr, sc = anchor.off_to_pos(t, so)
      local er, ec = anchor.off_to_pos(t, eo)
      render(buf, S, a, { sr, sc }, { er, ec })
    else
      a.status = 'detached'
      missing = missing + 1
    end
  end
  M.refresh_snapshot(buf, S)
  M.schedule_save(buf)
  emit(buf, 'restore', ids)
  return #ids, missing
end

---------------------------------------------------------------------------
-- Annotation edits (the single write path for notes, tags, values and names)
---------------------------------------------------------------------------

--- The annotation with this id in a buffer, or nil.
function M.annotation(buf, id)
  local S = M.get(buf, { no_create = true })
  return S and S.annos[id] or nil
end

local function touch(buf, S, a, action)
  a.updated = now()
  M.schedule_save(buf)
  emit(buf, action, { a.id })
end

--- Set (or clear, with nil or '') the note of an annotation.
function M.set_note(buf, id, text)
  buf = bufnr(buf)
  local S = M.get(buf, { no_create = true })
  local a = S and S.annos[id]
  if not a then return false end
  text = (text and text:match('%S')) and text or nil
  if a.note == text then return true end
  local tags = require('earmark.tags')
  local before = tags.parse(a.note).tags
  a.note = text
  pcall(tags.remember, tags.added(before, tags.parse(text).tags))
  touch(buf, S, a, 'note')
  return true
end

--- Replace the explicit tags of an annotation.
function M.set_tags(buf, id, tags)
  buf = bufnr(buf)
  local S = M.get(buf, { no_create = true })
  local a = S and S.annos[id]
  if not a then return false end
  local seen, list = {}, {}
  for _, t in ipairs(tags or {}) do
    if type(t) == 'string' and t ~= '' and not seen[t] then
      seen[t], list[#list + 1] = true, t
    end
  end
  if vim.deep_equal(list, a.tags or {}) then return true end
  local tags = require('earmark.tags')
  pcall(tags.remember, tags.added(a.tags, list))
  a.tags = #list > 0 and list or nil
  touch(buf, S, a, 'update')
  return true
end

--- Replace the values of an annotation (the first one colours it).
function M.set_values(buf, id, values)
  buf = bufnr(buf)
  local S = M.get(buf, { no_create = true })
  local a = S and S.annos[id]
  if not a or not values or #values == 0 then return false end
  if vim.deep_equal(a.values, values) then return true end
  a.values = values
  local s, e = live_pos(buf, S, id)
  if s then render(buf, S, a, s, e) end
  touch(buf, S, a, 'update')
  return true
end

local function label_key(value)
  return value.set .. '/' .. value.label
end
M.label_key = label_key

--- Name a label for this document (nil or '' clears the name).
function M.rename_label(buf, value, name)
  buf = bufnr(buf)
  local S = M.get(buf)
  if not S then return false end
  name = (name and name:match('%S')) and vim.trim(name) or nil
  if S.names[label_key(value)] == name then return true end
  S.names[label_key(value)] = name
  M.schedule_save(buf)
  emit(buf, 'update', nil)
  return true
end

--- Names given to labels in this document: { ["set/key"] = name }.
function M.names(buf)
  local S = M.get(buf, { no_create = true })
  return S and S.names or {}
end

--- Display name of a value in a buffer: the doc's name for it, else the label's name,
--- followed by its choice ("Accuracy · b Minor issue").
function M.display_name(buf, value)
  local S = M.get(buf, { no_create = true })
  local n = S and S.names[label_key(value)]
  if not n then
    local l = sets.label(value)
    n = l and l.name or value.label
  end
  local c = sets.choice(value)
  if c then n = n .. ' · ' .. c.key .. ' ' .. c.name end
  return n
end

--- Move an annotation to [s, e) (re-attaching a detached one). Its original text is kept,
--- so it reads as stale if the new text differs a lot.
--- opts.accept: the new text becomes what it annotates (regrowing a span on purpose).
function M.reanchor(buf, id, s, e, opts)
  buf = bufnr(buf)
  local S = M.get(buf, { no_create = true })
  local a = S and S.annos[id]
  if not a or not s or (s[1] == e[1] and s[2] == e[2]) then return false end
  local t = anchor.text(lines_of(buf))
  local text = anchor.span_text(t, s, e)
  if opts and opts.accept then a.original_quote = text end
  a.status = status_for(a, text)
  a.score, a.how = nil, nil
  render(buf, S, a, s, e)
  M.refresh_snapshot(buf, S)
  touch(buf, S, a, 'repair')
  return true
end

--- Accept an annotation's current text as what it annotates (clears stale/ambiguous).
function M.accept(buf, id)
  buf = bufnr(buf)
  local S = M.get(buf, { no_create = true })
  local a = S and S.annos[id]
  if not a then return false end
  local s, e = live_pos(buf, S, id)
  if not s then return false end
  a.original_quote = a.quote
  a.status, a.score, a.how = 'ok', nil, nil
  render(buf, S, a, s, e)
  touch(buf, S, a, 'update')
  return true
end

--- Colour a label differently in this document only (nil resets it).
function M.set_color(buf, value, hex)
  buf = bufnr(buf)
  local S = M.get(buf)
  if not S then return false end
  S.colors[label_key(value)] = hex
  M.rerender(buf)
  M.schedule_save(buf)
  emit(buf, 'update', nil)
  return true
end

--- Tags used in this document (explicit and from notes): { tag = count }.
function M.all_tags(buf)
  local S = M.get(buf, { no_create = true })
  local out = {}
  for _, a in pairs(S and S.annos or {}) do
    for _, t in ipairs((require('earmark.tags').of(a))) do
      out[t] = (out[t] or 0) + 1
    end
  end
  return out
end

--- Live annotations with positions, sorted by position (detached ones last, no position).
function M.list(buf)
  local S = M.get(buf, { no_create = true })
  if not S then return {} end
  local out = {}
  for id, a in pairs(S.annos) do
    local s, e = live_pos(buf, S, id)
    out[#out + 1] = { annotation = a, s = s, e = e }
  end
  table.sort(out, function(x, y)
    return by_position({ s = x.s, status = x.s and 'ok' or 'detached', id = x.annotation.id }, {
      s = y.s,
      status = y.s and 'ok' or 'detached',
      id = y.annotation.id,
    })
  end)
  return out
end

--- Re-render every annotation (after highlight groups or sets change).
function M.rerender(buf)
  buf = bufnr(buf)
  local S = M.state[buf]
  if not S then return end
  for id, a in pairs(S.annos) do
    local s, e = live_pos(buf, S, id)
    if s then render(buf, S, a, s, e) end
  end
end

M.live_pos = live_pos

---------------------------------------------------------------------------
-- Changing annotated text (c, s, C, Visual c)
---------------------------------------------------------------------------

-- An extmark only knows where text is deleted and inserted, so `cw` on the last word of
-- an annotation used to leave the new word outside it (the end stays before text typed
-- at it), `cw` on its first word did the same at the start, and changing all of it
-- detached it. When a deletion takes an edge (or all) of a span and Insert mode follows,
-- that edge grows with the typed text until Insert mode ends.

local function in_insert()
  local mode = api.nvim_get_mode().mode
  return mode:sub(1, 1) == 'i' or mode:sub(1, 1) == 'R'
end

local function cmp(a, b)
  if a[1] ~= b[1] then return a[1] < b[1] and -1 or 1 end
  if a[2] ~= b[2] then return a[2] < b[2] and -1 or 1 end
  return 0
end

--- Positions of every annotation as of the last change made outside Insert mode.
local function cache_positions(buf, S)
  local c = {}
  for _, m in ipairs(api.nvim_buf_get_extmarks(buf, M.ns, 0, -1, { details = true })) do
    local id = S.by_ext[m[1]]
    if id and not m[4].invalid then c[id] = { s = { m[2], m[3] }, e = { m[4].end_row or m[2], m[4].end_col or m[3] } } end
  end
  S.pos_cache = c
end

--- Refresh the positions `M.track` compares deletions with (after annotations change).
function M.cache_positions(buf)
  local S = M.state[buf]
  if S and S.tracking and api.nvim_buf_is_loaded(buf) and not in_insert() then cache_positions(buf, S) end
end

--- Insert mode ended: edges go back to normal gravity, and quotes/status catch up.
function M.insert_left(buf)
  local S = M.state[buf]
  if not S then return end
  if not S.grow then return cache_positions(buf, S) end
  local grow = S.grow
  S.grow = nil
  for id in pairs(grow) do
    local a = S.annos[id]
    local s, e = live_pos(buf, S, id)
    if a and s then
      if cmp(s, e) == 0 then
        detach(buf, S, a) -- nothing was typed
      else
        render(buf, S, a, s, e)
      end
    end
  end
  M.on_change(buf)
  cache_positions(buf, S)
  M.schedule_save(buf)
end

--- A deletion from `p` to `q` (old text) just happened outside Insert mode: note which
--- annotations lost an edge. If Insert mode starts right after it (`c`, `s`, `C`), those
--- edges take what is typed (`M.insert_entered`).
local function on_delete(buf, S, tick, p, q)
  local hits = {}
  for id, pos in pairs(S.pos_cache or {}) do
    local s, e = pos.s, pos.e
    local whole = cmp(s, p) == 0 and cmp(e, q) == 0
    local finish = cmp(s, p) < 0 and cmp(e, p) > 0 and cmp(e, q) == 0
    local start = cmp(s, p) == 0 and cmp(s, q) < 0 and cmp(e, q) > 0
    if whole or finish or start then hits[id] = { start = whole or start, finish = whole or finish } end
  end
  S.pending = next(hits) and { tick = tick, hits = hits, p = p } or nil
end

--- Insert mode started: if the change just before it took an edge of annotations, grow them.
function M.insert_entered(buf)
  local S = M.state[buf]
  local pending = S and S.pending
  if not pending then return end
  S.pending = nil
  -- (b:changedtick moves on once more after on_bytes reports the deletion)
  if api.nvim_buf_get_changedtick(buf) - pending.tick > 1 then return end
  local cur = api.nvim_win_get_cursor(0)
  if buf ~= api.nvim_get_current_buf() or cur[1] - 1 ~= pending.p[1] or cur[2] ~= pending.p[2] then return end
  S.grow = S.grow or {}
  for id, g in pairs(pending.hits) do
    local a = S.annos[id]
    if a and (a.status ~= 'detached' or (g.start and g.finish)) then
      S.grow[id] = g
      local s, e = live_pos(buf, S, id)
      if not s then s, e = pending.p, pending.p end -- the whole span went: start over where it was
      if a.status == 'detached' then a.status = 'ok' end
      render(buf, S, a, s, e)
    end
  end
end

--- Watch a buffer's changes (once per load).
function M.track(buf, S)
  if S.tracking then return end
  S.tracking = api.nvim_buf_attach(buf, false, {
    on_bytes = function(_, b, tick, sr, sc, _, oer, oec, old_len, _, _, new_len)
      if M.state[b] ~= S then return true end
      if in_insert() then return end
      S.pending = nil
      if old_len > 0 and new_len == 0 then
        local q = { sr + oer, oer == 0 and sc + oec or oec }
        on_delete(b, S, tick, { sr, sc }, q)
      end
      vim.schedule(function()
        if api.nvim_buf_is_valid(b) and M.state[b] == S and not in_insert() then cache_positions(b, S) end
      end)
      -- TextChanged only fires in the current buffer: repair others (floats, hidden) from here
      if b ~= api.nvim_get_current_buf() then
        S.change_timer = S.change_timer or vim.uv.new_timer()
        S.change_timer:stop()
        S.change_timer:start(config.options.debounce_ms, 0, vim.schedule_wrap(function()
          if M.state[b] == S and api.nvim_buf_is_loaded(b) then log.guard('on_change', M.on_change, b) end
        end))
      end
    end,
    on_detach = function()
      S.tracking = false
    end,
  })
  cache_positions(buf, S)
end

return M
