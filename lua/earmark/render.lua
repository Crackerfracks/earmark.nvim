-- Derived visuals, drawn by one decoration provider for the visible rows only:
--   * where annotations overlap, a composite: the OKLab mean of their colours, underlined in
--     the outermost one's colour (same colour throughout: underlined in the text colour, so
--     a word marked inside a phrase of the same label is still visible);
--   * an annotation's second label as an undercurl in that label's colour.
-- The persistent extmarks in `buffer.ns` stay the anchors and draw each span's own colour;
-- swatches for labels 3+ are persistent too (inline virtual text can't be ephemeral).
local buffer = require('earmark.buffer')
local color = require('earmark.color')
local config = require('earmark.config')
local log = require('earmark.log')
local sets = require('earmark.sets')

local api = vim.api
local M = {}

M.ns = api.nvim_create_namespace('earmark_render')

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

--- Re-define the composite groups (after `:colorscheme` cleared them).
function M.apply_highlights()
  for name, hl in pairs(mix_specs) do
    api.nvim_set_hl(0, name, hl)
  end
end

--- Look of an overlap segment whose members are listed outermost first.
--- Returns a group name.
function M.overlap_group(hexes)
  local uniq, seen = {}, {}
  for _, h in ipairs(hexes) do
    if not seen[h] then
      seen[h] = true
      uniq[#uniq + 1] = h
    end
  end
  if #uniq == 1 then
    -- nested spans of one colour: keep the colour, underline in the text colour (double
    -- underline from three levels deep)
    local bg = uniq[1]
    local fg = color.contrast_fg(bg)
    local deep = #hexes >= 3
    return group(('same|%s|%s'):format(bg, deep and 2 or 1), {
      bg = bg, fg = fg, sp = fg, underline = not deep or nil, underdouble = deep or nil,
    })
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

--- Decorations for rows [top, bot] of `buf`, as plain data (the provider draws exactly these):
---   { overlaps = { {s, e, ids, hexes} ... }, curls = { {s, e, id, hex} ... } }
--- `ids`/`hexes` list the overlapping annotations outermost first.
function M.segments(buf, top, bot)
  if buf == 0 then buf = api.nvim_get_current_buf() end
  local S = buffer.state[buf]
  local res = { overlaps = {}, curls = {} }
  if not S then return res end
  local items = visible(buf, S, top, bot)
  for _, it in ipairs(items) do
    local v2 = it.a.values[2]
    local hex = v2 and sets.color(v2, S.colors)
    if hex then res.curls[#res.curls + 1] = { s = it.s, e = it.e, id = it.id, hex = hex } end
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

local function draw(buf, top, bot)
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
end

local function on_win(_, _, buf, top, bot)
  if disabled[buf] or not buffer.state[buf] then return false end
  local ok, err = pcall(draw, buf, top, bot)
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

--- Turn drawing back on for a buffer (after an error).
function M.enable(buf)
  disabled[buf] = nil
end

return M
