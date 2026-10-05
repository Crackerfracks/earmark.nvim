-- Re-anchoring: given the text an annotation was recorded against ("old") and the text
-- now in the buffer ("new"), find where each annotation's span lives in the new text.
--
-- Pure functions over line lists; no buffer access. Positions are 0-based {row, col} with
-- byte columns; spans are end-exclusive.
--
-- Strategy per span:
--   1. Map both ends through a line-level diff; inside changed hunks, refine with a
--      character-level diff of just that hunk. Exact for untouched text, sensible for edits.
--   2. If the mapped text equals the recorded quote, done.
--   3. Otherwise look for exact occurrences of the quote whose surrounding text matches the
--      recorded prefix/suffix (handles moved blocks and whole-buffer rewrites).
--   4. Otherwise keep the mapped span if non-empty (the text was edited in place).
--   5. Otherwise, a long-enough unique quote is accepted anywhere; else the span is lost.
local M = {}

---------------------------------------------------------------------------
-- Text helpers
---------------------------------------------------------------------------

--- @class earmark.Text
--- @field str string   lines joined with "\n"
--- @field starts integer[]  0-based byte offset of each line start (1-based index = row + 1)

--- @return earmark.Text
function M.text(lines)
  local starts, off = {}, 0
  for i, l in ipairs(lines) do
    starts[i] = off
    off = off + #l + 1
  end
  return { str = table.concat(lines, '\n'), starts = starts, lines = lines }
end

function M.pos_to_off(t, row, col)
  local s = t.starts[row + 1]
  if not s then return #t.str end
  return s + math.min(col, #t.lines[row + 1])
end

function M.off_to_pos(t, off)
  off = math.max(0, math.min(off, #t.str))
  -- binary search for the last line start <= off
  local lo, hi = 1, #t.starts
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if t.starts[mid] <= off then lo = mid else hi = mid - 1 end
  end
  return lo - 1, off - t.starts[lo]
end

--- Split a string into UTF-8 characters. Returns chars and their 0-based byte offsets.
local function chars(s)
  local cs, offs = {}, {}
  for pos, ch in s:gmatch('()([%z\1-\127\194-\244][\128-\191]*)') do
    cs[#cs + 1], offs[#offs + 1] = ch, pos - 1
  end
  return cs, offs
end
M.chars = chars

local NL = '\1nl\1'
local function token_doc(cs)
  if #cs == 0 then return '' end
  local out = {}
  for i, c in ipairs(cs) do
    out[i] = c == '\n' and NL or c
  end
  return table.concat(out, '\n') .. '\n'
end

--- Hunks of a diff between two token lists: {a_start, a_count, b_start, b_count}, 1-based.
local function token_hunks(a, b)
  if #a == 0 and #b == 0 then return {} end
  return vim.diff(token_doc(a), token_doc(b), { result_type = 'indices', algorithm = 'myers' })
end

--- Similarity in [0, 1] between two strings (2 * matched chars / total chars).
function M.similarity(a, b)
  if a == b then return 1 end
  if a == '' or b == '' then return 0 end
  local ca, cb = chars(a), chars(b)
  if #ca + #cb > 40000 then
    -- Too long for a char diff; compare by lines instead.
    ca, cb = vim.split(a, '\n'), vim.split(b, '\n')
  end
  local deleted = 0
  for _, h in ipairs(token_hunks(ca, cb)) do
    deleted = deleted + h[2]
  end
  return 2 * (#ca - deleted) / (#ca + #cb)
end

---------------------------------------------------------------------------
-- Index mapping through a diff
---------------------------------------------------------------------------

--- Map a 1-based index `i` of sequence A to sequence B, given diff hunks.
--- side = 'start': an index inside a changed region maps to the first element of the
---   corresponding new region (or the element right after it, if that region is empty).
--- side = 'last': maps to the last element of the new region (or the one right before).
--- Returns the mapped index and whether it fell inside a changed region.
local function map_index(hunks, i, side)
  local delta = 0
  for _, h in ipairs(hunks) do
    local as, ac, bs, bc = h[1], h[2], h[3], h[4]
    if ac == 0 then
      -- pure insertion after A[as]; elements <= as are before it
      if i <= as then return i + delta, false end
    else
      if i < as then return i + delta, false end
      if i <= as + ac - 1 then
        local first = bc == 0 and bs + 1 or bs
        if side == 'start' then return first, true, h end
        return first + bc - 1, true, h
      end
    end
    delta = delta + bc - ac
  end
  return i + delta, false
end

---------------------------------------------------------------------------
-- Searching
---------------------------------------------------------------------------

local function common_suffix_len(a, b)
  local n = 0
  while n < #a and n < #b and a:byte(#a - n) == b:byte(#b - n) do
    n = n + 1
  end
  return n
end

local function common_prefix_len(a, b)
  local n = 0
  while n < #a and n < #b and a:byte(n + 1) == b:byte(n + 1) do
    n = n + 1
  end
  return n
end

--- Context score in [0, 1] for an occurrence at [s, e) of `str`.
local function context_score(str, s, e, prefix, suffix)
  local total = #prefix + #suffix
  if total == 0 then return 0 end
  local pre = str:sub(math.max(1, s - #prefix + 1), s)
  local suf = str:sub(e + 1, e + #suffix)
  return (common_suffix_len(pre, prefix) + common_prefix_len(suf, suffix)) / total
end

--- All exact occurrences of `quote` in `str` (0-based start offsets).
local function occurrences(str, quote, limit)
  local res, init = {}, 1
  while #res < (limit or 1000) do
    local s = str:find(quote, init, true)
    if not s then break end
    res[#res + 1] = s - 1
    init = s + 1
  end
  return res
end

--- Best occurrence of the quote by context, then by distance from `near` (0-based offset).
--- Returns start offset and its context score, or nil.
local function best_occurrence(str, item, near)
  local best, best_score, best_dist
  for _, s in ipairs(occurrences(str, item.quote)) do
    local score = context_score(str, s, s + #item.quote, item.prefix or '', item.suffix or '')
    local dist = near and math.abs(s - near) or 0
    if not best or score > best_score + 1e-9 or (math.abs(score - best_score) <= 1e-9 and dist < best_dist) then
      best, best_score, best_dist = s, score, dist
    end
  end
  return best, best_score
end

M.MIN_CONTEXT = 0.5 -- context score needed to trust a relocated quote
M.MIN_UNIQUE_QUOTE = 12 -- bytes; a unique quote this long is trusted without context

--- Locate an item in a text purely by quote/context (no diff), e.g. when restoring from
--- trash or re-attaching a detached annotation. `near` is an optional 0-based offset hint.
--- Returns s, e offsets or nil.
function M.locate(t, item, near)
  if not item.quote or item.quote == '' then return nil end
  local s, score = best_occurrence(t.str, item, near)
  if not s then return nil end
  if score >= M.MIN_CONTEXT then return s, s + #item.quote end
  if #item.quote >= M.MIN_UNIQUE_QUOTE and #occurrences(t.str, item.quote, 2) == 1 then
    return s, s + #item.quote
  end
  return nil
end

---------------------------------------------------------------------------
-- Main entry point
---------------------------------------------------------------------------

--- @class earmark.AnchorItem
--- @field id string
--- @field s integer[] {row, col} start in old text
--- @field e integer[] {row, col} end (exclusive) in old text
--- @field quote string text of the span in the old text
--- @field prefix string? text right before the span
--- @field suffix string? text right after the span

--- Re-anchor items recorded against `old_lines` into `new_lines`.
--- @param old_lines string[]
--- @param new_lines string[]
--- @param items earmark.AnchorItem[]
--- @return table<string, {s: integer[], e: integer[], how: string}|false>
function M.reanchor(old_lines, new_lines, items)
  local old, new = M.text(old_lines), M.text(new_lines)
  local result = {}
  if old.str == new.str then
    for _, it in ipairs(items) do
      result[it.id] = { s = it.s, e = it.e, how = 'same' }
    end
    return result
  end

  -- Lines are aligned by a diff that ignores whitespace, so formatter-style changes
  -- (indentation, trailing space, spacing) keep lines paired; such pairs are then mapped
  -- column-by-column with a small per-line character diff.
  local function norm(lines)
    local out = {}
    for i, l in ipairs(lines) do
      out[i] = l:gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', '')
    end
    return table.concat(out, '\n') .. '\n'
  end
  local line_hunks = vim.diff(norm(old_lines), norm(new_lines), { result_type = 'indices', algorithm = 'histogram' })
  local seg_cache = {}

  -- Map offset `off` (0-based, in old text) inside the old segment [a_base, a_base + #a_str)
  -- to the new segment starting at b_base, through a character diff of the two segments.
  local function seg_map(key, a_str, a_base, b_str, b_base, off, side)
    local sc = seg_cache[key]
    if not sc then
      local a_chars, a_offs = chars(a_str)
      local b_chars, b_offs = chars(b_str)
      sc = { a_offs = a_offs, a_len = #a_str, b_offs = b_offs, b_len = #b_str, hunks = token_hunks(a_chars, b_chars) }
      seg_cache[key] = sc
    end
    local rel = off - a_base
    local offs, idx = sc.a_offs, #sc.a_offs + 1 -- default: the newline right after the segment
    if rel < sc.a_len then
      -- the char containing byte `rel`: last char start <= rel
      local lo, hi = 1, #offs
      while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if offs[mid] <= rel then lo = mid else hi = mid - 1 end
      end
      idx = lo
    end
    local j = map_index(sc.hunks, idx, side)
    if j < 1 then return b_base - 1 end
    if j > #sc.b_offs then return b_base + sc.b_len end
    return b_base + sc.b_offs[j]
  end

  -- Map a 0-based byte offset of a character in old text to the new text.
  -- `side` as in map_index. Returns a 0-based offset of a character in new text
  -- (may equal #new.str when mapping past the end).
  local function map_char(off, side)
    local orow, ocol = M.off_to_pos(old, off)
    local nline, changed, h = map_index(line_hunks, orow + 1, side)
    if not changed then
      local s = new.starts[nline]
      if not s then return #new.str end
      local a, b = old_lines[orow + 1], new_lines[nline]
      if a == b then return s + ocol end
      return seg_map('l' .. orow, a, old.starts[orow + 1], b, s, off, side)
    end
    -- Inside a changed hunk: character diff of the whole hunk (lines joined).
    local a_str = table.concat(old_lines, '\n', h[1], h[1] + h[2] - 1)
    local b_str = h[4] > 0 and table.concat(new_lines, '\n', h[3], h[3] + h[4] - 1) or ''
    local b_base = h[4] > 0 and new.starts[h[3]] or (new.starts[h[3] + 1] or #new.str)
    return seg_map(h, a_str, old.starts[h[1]], b_str, b_base, off, side)
  end

  for _, it in ipairs(items) do
    local so, eo = M.pos_to_off(old, it.s[1], it.s[2]), M.pos_to_off(old, it.e[1], it.e[2])
    local ns, ne
    if eo > so then
      ns = map_char(so, 'start')
      local lo = eo - 1 -- start byte of the last included (possibly multibyte) char
      while lo > so and old.str:byte(lo + 1) >= 0x80 and old.str:byte(lo + 1) < 0xC0 do
        lo = lo - 1
      end
      local last = map_char(lo, 'last')
      -- end-exclusive: step past the (possibly multibyte) char at `last`
      if last >= ns and last < #new.str then
        local ch = new.str:match('^[%z\1-\127\194-\244][\128-\191]*', last + 1)
        ne = last + #(ch or ' ')
      elseif last >= ns then
        ne = #new.str
      end
    end

    local mapped_text = ns and ne and new.str:sub(ns + 1, ne) or nil
    local placed
    if mapped_text and mapped_text == it.quote then
      placed = { ns, ne, 'mapped' }
    else
      local near = ns or (so and map_char(so, 'start'))
      local s, score = nil, 0
      if it.quote and it.quote ~= '' then
        s, score = best_occurrence(new.str, it, near)
      end
      if s and score >= M.MIN_CONTEXT then
        placed = { s, s + #it.quote, 'relocated' }
      elseif mapped_text and mapped_text ~= '' and not mapped_text:match('^%s*$') then
        placed = { ns, ne, 'edited' }
      elseif s and #it.quote >= M.MIN_UNIQUE_QUOTE and #occurrences(new.str, it.quote, 2) == 1 then
        placed = { s, s + #it.quote, 'relocated' }
      end
    end

    if placed then
      local sr, sc = M.off_to_pos(new, placed[1])
      local er, ec = M.off_to_pos(new, placed[2])
      result[it.id] = { s = { sr, sc }, e = { er, ec }, how = placed[3] }
    else
      result[it.id] = false
    end
  end
  return result
end

--- Text of a span in a line list (or a prebuilt earmark.Text).
function M.span_text(lines, s, e)
  local t = lines.str and lines or M.text(lines)
  return t.str:sub(M.pos_to_off(t, s[1], s[2]) + 1, M.pos_to_off(t, e[1], e[2]))
end

--- Prefix/suffix context around a span, `n` bytes each.
function M.context(lines, s, e, n)
  local t = lines.str and lines or M.text(lines)
  local so, eo = M.pos_to_off(t, s[1], s[2]), M.pos_to_off(t, e[1], e[2])
  return t.str:sub(math.max(1, so - n + 1), so), t.str:sub(eo + 1, eo + n)
end

return M
