-- Derived visuals, drawn by one decoration provider for the visible rows only:
--   * where annotations overlap, a composite: the OKLab mean of their colours, underlined in
--     the outermost one's colour (same colour throughout: a deeper shade per level, like
--     highlighter strokes laid over each other);
--   * an annotation's second label as an undercurl in that label's colour; with more labels
--     the undercurl is cut into one equal run per extra label (`overlap.extra = 'split'`);
--   * end-of-line indicators: a pencil per note, #tags and [identifiers] of the annotations
--     ending on that line, in their colours (never a second background). A line too long
--     for them gets them on a virtual line below instead (kept in `ns_lines`, since virtual
--     lines can't be ephemeral).
-- The persistent extmarks in `buffer.ns` stay the anchors and draw each span's own colour;
-- with `overlap.extra = 'squares'`, swatches for labels 3+ are persistent too (inline
-- virtual text can't be ephemeral).
local buffer = require('earmark.buffer')
local color = require('earmark.color')
local config = require('earmark.config')
local log = require('earmark.log')
local sets = require('earmark.sets')
local tags = require('earmark.tags')

local api = vim.api
local M = {}

M.ns = api.nvim_create_namespace('earmark_render')
M.ns_lines = api.nvim_create_namespace('earmark_indicator_lines')

local PRIORITY_CURL = 4300 -- above every span (max 4200)
local PRIORITY_MIX = 4500

local disabled = {} -- buf -> true after an error
local mix_groups = {} -- cache key -> group name
local mix_specs = {} -- group name -> highlight definition
local n_mix = 0

local function before(p, q)
  return p[1] < q[1] or (p[1] == q[1] and p[2] < q[2])
end

local function same(p, q)
  return p[1] == q[1] and p[2] == q[2]
end

--- Highlight group for a definition, created once and kept for ColorScheme.
local function group(key, hl)
  local name = mix_groups[key]
  if name then return name end
  if n_mix >= 2000 then
    -- runaway cache (thousands of distinct colour combinations): start over
    mix_groups, mix_specs, n_mix = {}, {}, 0
  end
  n_mix = n_mix + 1
  name = 'EarmarkMix' .. n_mix
  mix_groups[key], mix_specs[name] = name, hl
  api.nvim_set_hl(0, name, hl)
  return name
end

--- Re-define the composite groups (after `:colorscheme` cleared them). With a new
--- background the colours themselves change, so the groups are made again as they're drawn.
function M.apply_highlights(background_changed)
  if background_changed then
    mix_groups, mix_specs, n_mix = {}, {}, 0
    return
  end
  for name, hl in pairs(mix_specs) do
    api.nvim_set_hl(0, name, hl)
  end
end

--- Look of an overlap segment whose members are listed outermost first.
--- Returns a group name.
function M.overlap_group(hexes)
  hexes = vim.tbl_map(color.adapt, hexes)
  local uniq, seen = {}, {}
  for _, h in ipairs(hexes) do
    if not seen[h] then
      seen[h] = true
      uniq[#uniq + 1] = h
    end
  end
  if #uniq == 1 then
    -- nested spans of one colour: like highlighter strokes laid over each other, each level
    -- is a deeper shade of the same colour (darker and a little richer)
    local depth = math.min(#hexes - 1, 4)
    local bg = color.shift(uniq[1], 1 + 0.18 * depth, -0.07 * depth)
    return group(('same|%s|%d'):format(uniq[1], depth), { bg = bg, fg = color.contrast_fg(bg) })
  end
  local sorted = vim.list_slice(uniq)
  table.sort(sorted)
  local bg = color.mix(sorted)
  local sp = hexes[1]
  return group(('mix|%s|%s'):format(table.concat(sorted, ','), sp), {
    bg = bg, fg = color.contrast_fg(bg), sp = sp, underline = true,
  })
end

function M.curl_group(hex)
  hex = color.adapt(hex)
  return group('curl|' .. hex, { sp = hex, undercurl = true })
end

--- Live annotations overlapping rows [top, bot] (0-based, inclusive), with their colours.
local function visible(buf, S, top, bot)
  local marks = api.nvim_buf_get_extmarks(buf, buffer.ns, { top, 0 }, { bot, -1 }, { details = true, overlap = true })
  local out = {}
  for _, m in ipairs(marks) do
    local d = m[4]
    local id = S.by_ext[m[1]]
    local a = id and S.annos[id]
    if a and not d.invalid and d.end_row then
      local s, e = { m[2], m[3] }, { d.end_row, d.end_col }
      if before(s, e) then
        out[#out + 1] = {
          id = id,
          a = a,
          s = s,
          e = e,
          hex = sets.color(a.values[1], S.colors),
          size = (e[1] - s[1]) * 200 + (e[2] - s[2]),
        }
      end
    end
  end
  return out
end

--- [s, e) cut into `k` runs of (nearly) equal numbers of characters: { {s=, e=} ... }.
--- Fewer runs when the span has fewer than `k` characters.
local function split_span(buf, s, e, k)
  local lines = api.nvim_buf_get_text(buf, s[1], s[2], e[1], e[2], {})
  local pos = {}
  for i, l in ipairs(lines) do
    local row, base = s[1] + i - 1, i == 1 and s[2] or 0
    for _, b in ipairs(vim.str_utf_pos(l)) do
      pos[#pos + 1] = { row, base + b - 1 }
    end
  end
  local n = #pos
  k = math.min(k, n)
  pos[n + 1] = e
  local out = {}
  for i = 0, k - 1 do
    out[#out + 1] = { s = pos[math.floor(i * n / k) + 1], e = pos[math.floor((i + 1) * n / k) + 1] }
  end
  return out
end

--- Decorations for rows [top, bot] of `buf`, as plain data (the provider draws exactly these):
---   { overlaps = { {s, e, ids, hexes} ... }, curls = { {s, e, id, hex} ... } }
--- `ids`/`hexes` list the overlapping annotations outermost first.
function M.segments(buf, top, bot)
  if buf == 0 then buf = api.nvim_get_current_buf() end
  local S = buffer.state[buf]
  local res = { overlaps = {}, curls = {} }
  if not S then return res end
  local items = visible(buf, S, top, bot)
  local split = config.options.overlap.extra ~= 'squares'
  for _, it in ipairs(items) do
    local extra = {}
    for i = 2, (split and #it.a.values or 2) do
      local hex = it.a.values[i] and sets.color(it.a.values[i], S.colors)
      if hex then extra[#extra + 1] = hex end
    end
    if #extra == 1 then
      res.curls[#res.curls + 1] = { s = it.s, e = it.e, id = it.id, hex = extra[1] }
    elseif #extra > 1 then
      for i, part in ipairs(split_span(buf, it.s, it.e, #extra)) do
        res.curls[#res.curls + 1] = { s = part.s, e = part.e, id = it.id, hex = extra[i] }
      end
    end
  end
  items = vim.tbl_filter(function(it)
    return it.hex ~= nil -- labels that no longer exist keep the plain look
  end, items)
  if #items < 2 or config.options.overlap.style == 'top' then return res end

  -- Sweep the span boundaries; each elementary interval covered by 2+ spans is an overlap,
  -- and neighbouring intervals with the same members merge into one segment.
  local points = {}
  for _, it in ipairs(items) do
    points[#points + 1] = it.s
    points[#points + 1] = it.e
  end
  table.sort(points, before)
  local uniq = {}
  for _, p in ipairs(points) do
    if #uniq == 0 or not same(uniq[#uniq], p) then uniq[#uniq + 1] = p end
  end
  table.sort(items, function(x, y)
    if x.size ~= y.size then return x.size > y.size end
    return before(x.s, y.s)
  end)
  local last
  for i = 1, #uniq - 1 do
    local p, q = uniq[i], uniq[i + 1]
    local members = {}
    for _, it in ipairs(items) do
      if not before(p, it.s) and not before(it.e, q) then members[#members + 1] = it end
    end
    if #members >= 2 then
      local ids, hexes = {}, {}
      for k, it in ipairs(members) do
        ids[k], hexes[k] = it.id, it.hex
      end
      local key = table.concat(ids, ',')
      if last and last.key == key and same(last.e, p) then
        last.e = q
      else
        last = { s = p, e = q, ids = ids, hexes = hexes, key = key }
        res.overlaps[#res.overlaps + 1] = last
      end
    else
      last = nil
    end
  end
  for _, o in ipairs(res.overlaps) do
    o.key = nil
  end
  return res
end

---------------------------------------------------------------------------
-- End-of-line indicators
---------------------------------------------------------------------------

local function ind_opts()
  return config.options.indicators
end

local function last_row(it)
  -- a span ending at column 0 ends on the line before
  if it.e[2] == 0 and it.e[1] > it.s[1] then return it.e[1] - 1 end
  return it.e[1]
end

--- Indicator chunks for annotations ending on `row`, or nil when there are none.
--- Returns { chunks = { {text, group} ... }, col = start column of the first one }.
local function eol_from(S, items, row)
  local o = ind_opts()
  local ending = {}
  for _, it in ipairs(items) do
    if last_row(it) == row then ending[#ending + 1] = it end
  end
  if #ending == 0 then return nil end
  table.sort(ending, function(x, y)
    return before(x.s, y.s)
  end)
  local nerd = vim.g.have_nerd_font ~= false
  local pencil, empty = nerd and '✎' or '*', nerd and '·' or '.'
  local chunks, pencils = {}, 0
  local seen_tag, seen_id = {}, {}
  local tag_chunks, id_chunks = {}, {}
  for _, it in ipairs(ending) do
    local hex = it.hex
    local fg = hex and sets.fg_group(hex) or 'EarmarkIndicator'
    if it.a.note then
      pencils = pencils + 1
      if pencils <= o.max_pencils then chunks[#chunks + 1] = { pencil, fg } end
    elseif o.show_empty then
      chunks[#chunks + 1] = { empty, fg }
    end
    local list, idents = tags.of(it.a)
    if not o.tags then list, idents = {}, {} end
    for _, t in ipairs(list) do
      if not seen_tag[t] then
        seen_tag[t] = true
        tag_chunks[#tag_chunks + 1] = { '#' .. t, fg }
      end
    end
    if o.identifiers then
      for _, t in ipairs(idents) do
        if not seen_id[t] then
          seen_id[t] = true
          id_chunks[#id_chunks + 1] = { '[' .. t .. ']', hex and sets.fg_group(hex, true) or 'EarmarkIndicator' }
        end
      end
    end
  end
  if pencils > o.max_pencils then chunks[#chunks + 1] = { '+' .. (pencils - o.max_pencils), 'Comment' } end
  for _, c in ipairs(tag_chunks) do
    chunks[#chunks + 1] = c
  end
  vim.list_extend(chunks, id_chunks)
  if #chunks == 0 then return nil end
  -- one space between items, except between pencils and inside [A][B]
  local out = {}
  for i, c in ipairs(chunks) do
    local prev = chunks[i - 1]
    if prev and not (prev[1] == pencil and c[1] == pencil) and not (prev[1]:sub(1, 1) == '[' and c[1]:sub(1, 1) == '[') then
      out[#out + 1] = { ' ', 'Normal' }
    end
    out[#out + 1] = c
  end
  return { chunks = out, col = ending[1].s[1] == row and ending[1].s[2] or 0 }
end

--- Indicator chunks for one row of `buf` (see eol_from), or nil.
function M.eol_items(buf, row)
  if buf == 0 then buf = api.nvim_get_current_buf() end
  local S = buffer.state[buf]
  if not S then return nil end
  return eol_from(S, visible(buf, S, row, row), row)
end

local function chunks_width(chunks)
  local w = 0
  for _, c in ipairs(chunks) do
    w = w + vim.fn.strdisplaywidth(c[1])
  end
  return w
end

local virt = {} -- buf -> { [row] = signature } of the virtual lines placed

--- Place/remove the virtual indicator lines of rows [top, bot] to match `want`.
local function sync_lines(buf, top, bot, want)
  if not api.nvim_buf_is_valid(buf) then return end
  local have = virt[buf] or {}
  virt[buf] = have
  local marks = api.nvim_buf_get_extmarks(buf, M.ns_lines, { top, 0 }, { bot, -1 }, { details = true })
  local placed = {}
  for _, m in ipairs(marks) do
    local row = m[2]
    if not want[row] or placed[row] or have[row] ~= want[row].sig then
      api.nvim_buf_del_extmark(buf, M.ns_lines, m[1])
      have[row] = nil
    else
      placed[row] = true
    end
  end
  for row, w in pairs(want) do
    if not placed[row] then
      api.nvim_buf_set_extmark(buf, M.ns_lines, row, 0, { virt_lines = { w.line }, strict = false })
      have[row] = w.sig
    end
  end
end

--- Remove every virtual indicator line (indicators off, or the buffer forgotten).
function M.clear_lines(buf)
  if api.nvim_buf_is_valid(buf) then api.nvim_buf_clear_namespace(buf, M.ns_lines, 0, -1) end
  virt[buf] = nil
end

local function draw_indicators(win, buf, S, top, bot)
  if ind_opts().mode ~= 'eol' then return end
  local items = visible(buf, S, top, bot)
  local by_row = {}
  for _, it in ipairs(items) do
    local r = last_row(it)
    if r >= top and r <= bot then by_row[r] = true end
  end
  -- every window of this tab showing the buffer decides alike (the virtual lines are the
  -- buffer's): else each one would remove the lines another one places, again and again
  local rooms, avail = {}, math.huge
  for _, w in ipairs(vim.fn.win_findbuf(buf)) do
    if api.nvim_win_get_tabpage(w) == api.nvim_win_get_tabpage(win) then
      local info = vim.fn.getwininfo(w)[1]
      local room = { avail = api.nvim_win_get_width(w) - (info and info.textoff or 0), wrap = vim.wo[w].wrap }
      rooms[#rooms + 1] = room
      avail = math.min(avail, room.avail)
    end
  end
  local want, dirty = {}, false
  for row in pairs(by_row) do
    local ind = eol_from(S, items, row)
    if ind then
      local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ''
      local lw = vim.fn.strdisplaywidth(line)
      local w = chunks_width(ind.chunks)
      local fits = true
      for _, r in ipairs(rooms) do
        local used = r.wrap and r.avail > 0 and (lw % r.avail) or lw
        if r.wrap and lw > 0 and used == 0 then used = r.avail end
        if used + 1 + w > r.avail then fits = false end
      end
      if fits then
        api.nvim_buf_set_extmark(buf, M.ns, row, 0, {
          virt_text = ind.chunks, virt_text_pos = 'eol', ephemeral = true, priority = 100,
        })
      else
        local indent = vim.fn.strdisplaywidth(line:sub(1, ind.col))
        indent = math.min(indent, math.max(0, avail - w))
        local vline = { { string.rep(' ', indent), 'Normal' } }
        vim.list_extend(vline, ind.chunks)
        local sig = vim.inspect(vline)
        want[row] = { line = vline, sig = sig }
      end
    end
  end
  local have = virt[buf] or {}
  for row = top, bot do
    if (want[row] and want[row].sig) ~= have[row] then dirty = true end
  end
  if dirty then
    vim.schedule(function()
      log.guard('indicator lines', sync_lines, buf, top, bot, want)
    end)
  end
end

local function draw(win, buf, top, bot)
  local segs = M.segments(buf, top, bot)
  for _, c in ipairs(segs.curls) do
    api.nvim_buf_set_extmark(buf, M.ns, c.s[1], c.s[2], {
      end_row = c.e[1], end_col = c.e[2], hl_group = M.curl_group(c.hex),
      priority = PRIORITY_CURL, ephemeral = true, strict = false,
    })
  end
  for _, o in ipairs(segs.overlaps) do
    api.nvim_buf_set_extmark(buf, M.ns, o.s[1], o.s[2], {
      end_row = o.e[1], end_col = o.e[2], hl_group = M.overlap_group(o.hexes),
      priority = PRIORITY_MIX, ephemeral = true, strict = false,
    })
  end
  draw_indicators(win, buf, buffer.state[buf], top, bot)
end

local function on_win(_, win, buf, top, bot)
  if disabled[buf] or not buffer.state[buf] then return false end
  local ok, err = pcall(draw, win, buf, top, bot)
  if not ok then
    disabled[buf] = true
    log.error('render (buffer %d): %s', buf, err)
    vim.schedule(function()
      vim.notify('earmark: overlap drawing failed and is off for this buffer, see :Earmark log', vim.log.levels.WARN)
    end)
  end
  return false
end

function M.setup()
  api.nvim_set_decoration_provider(M.ns, { on_win = on_win })
end

--- `<leader>mv`: show or hide #tags and [identifiers] at the ends of lines (pencils stay).
--- Only changes how things look; nothing is re-read or re-saved.
function M.toggle_indicators()
  local o = ind_opts()
  o.tags = not o.tags
  for buf in pairs(virt) do
    M.clear_lines(buf)
  end
  vim.cmd('redraw!')
  vim.notify('earmark: tags ' .. (o.tags and 'shown' or 'hidden'))
end

--- Turn drawing back on for a buffer (after an error).
function M.enable(buf)
  disabled[buf] = nil
end

return M
