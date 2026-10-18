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
local diff = require('earmark.compat').diff

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
  return diff(token_doc(a), token_doc(b), { result_type = 'indices', algorithm = 'myers' })
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

--- Split a string into words, runs of whitespace and single other characters. Returns the
--- tokens and their 0-based byte offsets. Bytes >= 0x80 count as word characters.
local function words(s)
  local toks, offs = {}, {}
  local i = 1
  while i <= #s do
    local _, e = s:find('^[%w_\128-\255]+', i)
    if not e then _, e = s:find('^%s+', i) end
    e = e or i
    toks[#toks + 1], offs[#offs + 1] = s:sub(i, e), i - 1
    i = e + 1
  end
  return toks, offs
end

--- Hunks of a word diff (as token_hunks). Histogram prefers rare words as anchors, so a
--- common word like "the" doesn't pull the alignment into an unrelated sentence.
local function word_hunks(a, b)
  if #a == 0 and #b == 0 then return {} end
  local function doc(ts)
    if #ts == 0 then return '' end
    local out = {}
    for i, t in ipairs(ts) do
      out[i] = t:gsub('\n', NL)
    end
    return table.concat(out, '\n') .. '\n'
  end
  return diff(doc(a), doc(b), { result_type = 'indices', algorithm = 'histogram' })
end

--- Index of the last element of the ascending list `offs` that is <= x.
local function last_le(offs, x)
  local lo, hi = 1, #offs
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if offs[mid] <= x then lo = mid else hi = mid - 1 end
  end
  return lo
end

--- 0-based start of the last (possibly multibyte) character in s[from, to).
local function last_char_start(s, from, to)
  local i = to - 1
  while i > from and s:byte(i + 1) >= 0x80 and s:byte(i + 1) < 0xC0 do
    i = i - 1
  end
  return i
end

--- Map byte `rel` of `a` to `b` through a character diff. Returns a 0-based offset of a
--- character in b, -1 (before it) or #b (after it). `side` as in map_index.
local function char_map(a, b, rel, side)
  local a_chars, a_offs = chars(a)
  local b_chars, b_offs = chars(b)
  local j = map_index(token_hunks(a_chars, b_chars), last_le(a_offs, rel), side)
  if j < 1 then return -1 end
  if j > #b_offs then return #b end
  return b_offs[j]
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

---------------------------------------------------------------------------
-- Fuzzy search and scored candidates
---------------------------------------------------------------------------

--- Collapse whitespace runs to one space. Returns the collapsed string and a map from each
--- of its byte positions (1-based) to the byte position in `s`.
local function collapse(s, base)
  local out, map = {}, {}
  local n, i, len = 0, 1, #s
  while i <= len do
    local ws = s:match('^%s+', i)
    if ws then
      n = n + 1
      out[n], map[n] = ' ', base + i
      i = i + #ws
    else
      n = n + 1
      out[n], map[n] = s:sub(i, i), base + i
      i = i + 1
    end
  end
  map[n + 1] = base + len + 1
  return table.concat(out), map
end

--- Approximate occurrences of `pat` in `str` (Sellers' algorithm with Ukkonen's cut-off):
--- ends of substrings within `k` edits, each as { s, e, dist } (1-based, inclusive),
--- keeping the best end of each run of neighbouring matches.
local function approx(str, pat, k)
  local m = #pat
  if m == 0 then return {} end
  local pb = { pat:byte(1, m) }
  local col, start = {}, {}
  for i = 0, m do
    col[i], start[i] = i, 1
  end
  local lact = math.min(k, m) -- deepest row whose value may be <= k
  local hits = {}
  for j = 1, #str do
    local c = str:byte(j)
    start[0] = j + 1 -- D[0][j] = 0: nothing matched yet, a match starts after j
    local diag, diag_s = 0, j -- D[0][j-1]
    for i = 1, lact do
      local up, up_s = col[i], start[i]
      local v, vs = diag + (pb[i] == c and 0 or 1), diag_s
      if col[i - 1] + 1 < v then v, vs = col[i - 1] + 1, start[i - 1] end
      if up + 1 < v then v, vs = up + 1, up_s end
      diag, diag_s = up, up_s
      col[i], start[i] = v, vs
    end
    if lact < m then
      -- one more row can come within k through the diagonal (its previous value was above k)
      local i = lact + 1
      local v, vs = diag + (pb[i] == c and 0 or 1), diag_s
      if col[i - 1] + 1 < v then v, vs = col[i - 1] + 1, start[i - 1] end
      col[i], start[i] = v, vs
      lact = i
    end
    while lact > 0 and col[lact] > k do
      lact = lact - 1
    end
    if lact == m then
      local prev = hits[#hits]
      if prev and prev.last == j - 1 then
        -- same run of neighbouring ends: keep the closest
        if col[m] < prev.dist then prev.s, prev.e, prev.dist = start[m], j, col[m] end
        prev.last = j
      else
        hits[#hits + 1] = { s = start[m], e = j, dist = col[m], first = j, last = j }
      end
    end
  end
  return hits
end
M._approx = approx

M.FUZZY_MIN = 0.75 -- similarity a fuzzy match needs
M.FUZZY_WINDOW = 200 -- lines on each side of the expected place searched first

--- Expand a byte range to whole UTF-8 characters.
local function char_bounds(str, s, e)
  while s > 1 and str:byte(s) and str:byte(s) >= 0x80 and str:byte(s) < 0xC0 do
    s = s - 1
  end
  while e < #str and str:byte(e + 1) and str:byte(e + 1) >= 0x80 and str:byte(e + 1) < 0xC0 do
    e = e + 1
  end
  return s, e
end

--- Fuzzy matches of `item.quote` in text `t`: { { s, e, sim } ... } as 0-based offsets
--- (end-exclusive), best first. Whitespace differences are ignored. Searches the lines
--- around `near` (0-based offset) first, then the whole text when it is small enough.
function M.fuzzy(t, item, near, opts)
  opts = opts or {}
  local quote = item.quote or ''
  local q = collapse(quote, 0):gsub('^ ', ''):gsub(' $', '')
  if #q < 4 then return {} end
  local function search(lo_row, hi_row)
    local so = t.starts[lo_row + 1] or 0
    local eo = hi_row + 2 <= #t.starts and t.starts[hi_row + 2] - 1 or #t.str
    local seg, map = collapse(t.str:sub(so + 1, eo), so)
    local found = {}
    -- similarity from the edit distance: 1 - edits / length
    local function add(s1, e1, dist)
      local bs, be = char_bounds(t.str, map[s1], map[e1 + 1] - 1)
      local sim = 1 - dist / math.max(#q, e1 - s1 + 1)
      if sim >= (opts.min or M.FUZZY_MIN) then found[#found + 1] = { s = bs - 1, e = be, sim = sim } end
    end
    if #q <= 256 then
      local k = math.min(math.floor(#q / 4), 64)
      local hits = approx(seg, q, k)
      -- only the closest few are worth scoring
      table.sort(hits, function(x, y)
        return x.dist < y.dist
      end)
      for i = 1, math.min(#hits, 20) do
        add(hits[i].s, hits[i].e, hits[i].dist)
      end
    else
      -- long quotes: match the head and the tail and pair them up
      local head, tail = q:sub(1, 96), q:sub(-96)
      local heads, tails = approx(seg, head, 24), approx(seg, tail, 24)
      for _, hh in ipairs(heads) do
        for _, tt in ipairs(tails) do
          local len = tt.e - hh.s + 1
          if len >= #q * 0.75 and len <= #q * 1.25 and #found < 20 then
            local bs, be = char_bounds(t.str, map[hh.s], map[tt.e + 1] - 1)
            local sim = M.similarity(collapse(t.str:sub(bs, be), 0), q)
            if sim >= (opts.min or M.FUZZY_MIN) then found[#found + 1] = { s = bs - 1, e = be, sim = sim } end
          end
        end
      end
    end
    return found
  end
  local rows = #t.starts
  local found = {}
  if near then
    local r = M.off_to_pos(t, near)
    found = search(math.max(0, r - M.FUZZY_WINDOW), math.min(rows - 1, r + M.FUZZY_WINDOW))
  end
  if #found == 0 and #t.str <= (opts.max_bytes or 2 * 1024 * 1024) then found = search(0, rows - 1) end
  table.sort(found, function(x, y)
    return x.sim > y.sim
  end)
  return found
end

--- Up to `n` places where `item` could be now, best first:
--- { { s, e, score, sim, context, how = 'exact'|'fuzzy' } ... } (0-based offsets).
--- score = 0.5 * similarity + 0.3 * context + 0.2 * proximity to `near`.
function M.candidates(t, item, near, n, opts)
  opts = opts or {}
  n = n or 3
  local out = {}
  local quote = item.quote or ''
  local function proximity(s)
    if not near then return 0.5 end
    return 1 / (1 + math.abs(s - near) / 2000)
  end
  local function push(s, e, sim, how)
    local ctx = context_score(t.str, s, e, item.prefix or '', item.suffix or '')
    out[#out + 1] = {
      s = s, e = e, sim = sim, context = ctx, how = how,
      score = 0.5 * sim + 0.3 * ctx + 0.2 * proximity(s),
    }
  end
  if quote ~= '' then
    for _, s in ipairs(occurrences(t.str, quote, 200)) do
      push(s, s + #quote, 1, 'exact')
    end
  end
  if opts.fuzzy ~= false and #out == 0 then
    for _, f in ipairs(M.fuzzy(t, item, near, opts)) do
      push(f.s, f.e, f.sim, 'fuzzy')
    end
  end
  table.sort(out, function(x, y)
    return x.score > y.score
  end)
  while #out > n do
    table.remove(out)
  end
  return out
end

M.AMBIGUOUS_MARGIN = 0.1

--- Whether the best two candidates are too close to tell apart.
local function ambiguous(cands)
  return #cands >= 2 and cands[1].score - cands[2].score < M.AMBIGUOUS_MARGIN
end
M.is_ambiguous = ambiguous

M.MIN_CONTEXT = 0.5 -- context score needed to trust a relocated quote
M.MIN_UNIQUE_QUOTE = 12 -- bytes; a unique quote this long is trusted without context

M.FUZZY_MIN_QUOTE = 12 -- bytes; shorter quotes are only ever matched exactly

--- Whether a fuzzy candidate is good enough to place an annotation on its own.
local function fuzzy_ok(item, c)
  return #(item.quote or '') >= M.FUZZY_MIN_QUOTE and (c.context >= 0.3 or c.sim >= 0.9)
end

--- Locate an item in a text purely by quote/context (no diff), e.g. when restoring from
--- trash, re-attaching a detached annotation or loading without a snapshot. `near` is an
--- optional 0-based offset hint; opts.fuzzy allows near matches of an edited quote.
--- Returns s, e offsets and { how, score, ambiguous }, or nil.
function M.locate(t, item, near, opts)
  opts = opts or {}
  if not item.quote or item.quote == '' then return nil end
  local cands = M.candidates(t, item, near, 3, { fuzzy = opts.fuzzy == true })
  local best = cands[1]
  if not best then return nil end
  local info = { how = 'relocated', score = best.score }
  if best.how == 'exact' then
    if best.context >= M.MIN_CONTEXT then
      info.ambiguous = ambiguous(cands) and cands[2].context >= M.MIN_CONTEXT
      return best.s, best.e, info
    end
    if #item.quote >= M.MIN_UNIQUE_QUOTE and #cands == 1 then return best.s, best.e, info end
    return nil
  end
  if fuzzy_ok(item, best) then
    info.how, info.ambiguous = 'fuzzy', ambiguous(cands)
    return best.s, best.e, info
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
  local line_hunks = diff(norm(old_lines), norm(new_lines), { result_type = 'indices', algorithm = 'histogram' })
  local seg_cache = {}

  -- Map offset `off` (0-based, in old text) inside the old segment [a_base, a_base + #a_str)
  -- to the new segment starting at b_base. The segments are diffed by words first, so a
  -- replaced word maps to its replacement as a whole ("two" -> "four", not "fo"); only
  -- inside a run of changed words is a character diff used.
  local function seg_map(key, a_str, a_base, b_str, b_base, off, side)
    local sc = seg_cache[key]
    if not sc then
      local a_toks, a_offs = words(a_str)
      local b_toks, b_offs = words(b_str)
      sc = { a_offs = a_offs, a_len = #a_str, b_offs = b_offs, b_len = #b_str, hunks = word_hunks(a_toks, b_toks) }
      seg_cache[key] = sc
    end
    local rel = off - a_base
    if rel >= sc.a_len then
      -- the newline right after the segment
      local j = map_index(sc.hunks, #sc.a_offs + 1, side)
      if j > #sc.b_offs then return b_base + sc.b_len end
      return b_base + sc.b_offs[j]
    end
    local ti = last_le(sc.a_offs, rel)
    local j, changed, h = map_index(sc.hunks, ti, side)
    if not changed then return b_base + sc.b_offs[j] + (rel - sc.a_offs[ti]) end
    -- inside a run of changed words: old run [ra, ra_end) maps to new run [rb, rb_end)
    local ra = sc.a_offs[h[1]]
    local ra_end = sc.a_offs[h[1] + h[2]] or sc.a_len
    if h[4] == 0 then
      -- the words were deleted: the next word (start) or the end of the previous one (last)
      local rb = sc.b_offs[h[3] + 1] or sc.b_len
      if side == 'start' then return b_base + rb end
      return b_base + last_char_start(b_str, 0, rb)
    end
    local rb = sc.b_offs[h[3]]
    local rb_end = sc.b_offs[h[3] + h[4]] or sc.b_len
    if side == 'start' and rel == ra then return b_base + rb end
    if side == 'last' and rel == last_char_start(a_str, ra, ra_end) then
      return b_base + last_char_start(b_str, rb, rb_end)
    end
    local r = char_map(a_str:sub(ra + 1, ra_end), b_str:sub(rb + 1, rb_end), rel - ra, side)
    return b_base + rb + r
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
      local cands = (it.quote and it.quote ~= '') and M.candidates(new, it, near, 3, { fuzzy = false }) or {}
      local best = cands[1]
      if best and best.context >= M.MIN_CONTEXT then
        local amb = ambiguous(cands) and cands[2].context >= M.MIN_CONTEXT
        placed = { best.s, best.e, 'relocated', best.score, amb }
      elseif mapped_text and mapped_text ~= '' and not mapped_text:match('^%s*$') then
        placed = { ns, ne, 'edited' }
      elseif best and #it.quote >= M.MIN_UNIQUE_QUOTE and #cands == 1 then
        placed = { best.s, best.e, 'relocated', best.score }
      elseif not best and it.quote and it.quote ~= '' then
        -- the text was moved and edited: look for something close to it
        local f = M.candidates(new, it, near, 3)
        if f[1] and fuzzy_ok(it, f[1]) then placed = { f[1].s, f[1].e, 'fuzzy', f[1].score, ambiguous(f) } end
      end
    end

    if placed then
      local sr, sc = M.off_to_pos(new, placed[1])
      local er, ec = M.off_to_pos(new, placed[2])
      result[it.id] = { s = { sr, sc }, e = { er, ec }, how = placed[3], score = placed[4], ambiguous = placed[5] }
    else
      result[it.id] = false
    end
  end
  return result
end

--- Re-anchor items without a snapshot of the text they were recorded against (the
--- snapshot is missing, e.g. a fresh clone of a repo with a committed `.earmark/`).
--- Positions are only hints: a span is kept where it was if its text still equals the
--- quote, else the quote is searched for with its context.
--- @return table<string, {s: integer[], e: integer[], how: string}|false>
function M.reanchor_by_quote(new_lines, items)
  local t = M.text(new_lines)
  local result = {}
  for _, it in ipairs(items) do
    local placed
    if it.s and it.e and it.s[1] < #new_lines and M.span_text(t, it.s, it.e) == it.quote then
      placed = { s = it.s, e = it.e, how = 'same' }
    else
      local near = it.s and M.pos_to_off(t, it.s[1], it.s[2]) or nil
      local so, eo, info = M.locate(t, it, near, { fuzzy = true })
      if so then
        local sr, sc = M.off_to_pos(t, so)
        local er, ec = M.off_to_pos(t, eo)
        placed = { s = { sr, sc }, e = { er, ec }, how = info.how, score = info.score, ambiguous = info.ambiguous }
      end
    end
    result[it.id] = placed or false
  end
  return result
end

--- Text of a span in a line list (or a prebuilt earmark.Text).
function M.span_text(lines, s, e)
  local t = lines.str and lines or M.text(lines)
  return t.str:sub(M.pos_to_off(t, s[1], s[2]) + 1, M.pos_to_off(t, e[1], e[2]))
end

M.MAX_CONTEXT = 96

--- Context for a new annotation: `n` bytes each side, grown (up to MAX_CONTEXT) until the
--- quote with its context occurs only once, then extended to a word boundary.
function M.unique_context(lines, s, e, n)
  local t = lines.str and lines or M.text(lines)
  local so, eo = M.pos_to_off(t, s[1], s[2]), M.pos_to_off(t, e[1], e[2])
  local quote = t.str:sub(so + 1, eo)
  local size = n
  local pre, suf
  while true do
    pre, suf = t.str:sub(math.max(1, so - size + 1), so), t.str:sub(eo + 1, eo + size)
    if quote == '' or size >= M.MAX_CONTEXT or #occurrences(t.str, pre .. quote .. suf, 2) <= 1 then break end
    size = math.min(M.MAX_CONTEXT, size + 32)
  end
  -- don't cut words in half at the outer edges
  local ps = so - #pre -- 0-based start of the prefix
  local k = 0
  while ps > 0 and k < 16 and not t.str:sub(ps, ps):match('%s') do
    ps, k = ps - 1, k + 1
  end
  local se = eo + #suf
  k = 0
  while se < #t.str and k < 16 and not t.str:sub(se + 1, se + 1):match('%s') do
    se, k = se + 1, k + 1
  end
  return t.str:sub(ps + 1, so), t.str:sub(eo + 1, se)
end

--- Prefix/suffix context around a span, `n` bytes each.
function M.context(lines, s, e, n)
  local t = lines.str and lines or M.text(lines)
  local so, eo = M.pos_to_off(t, s[1], s[2]), M.pos_to_off(t, e[1], e[2])
  return t.str:sub(math.max(1, so - n + 1), so), t.str:sub(eo + 1, eo + n)
end

return M
