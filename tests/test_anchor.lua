local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local anchor = require('earmark.anchor')

-- Build an item for `quote` (its n-th occurrence) in `lines`, like the plugin records it.
local function item(lines, quote, n, id)
  local t = anchor.text(lines)
  local init, s = 1, nil
  for _ = 1, n or 1 do
    s = t.str:find(quote, init, true)
    init = s + 1
  end
  local so, eo = s - 1, s - 1 + #quote
  local sr, sc = anchor.off_to_pos(t, so)
  local er, ec = anchor.off_to_pos(t, eo)
  local pre, suf = anchor.context(lines, { sr, sc }, { er, ec }, 32)
  return { id = id or quote, s = { sr, sc }, e = { er, ec }, quote = quote, prefix = pre, suffix = suf }
end

local function text_at(lines, r)
  if not r then return nil end
  return anchor.span_text(lines, r.s, r.e)
end

local function run(old, new, ...)
  local items = { ... }
  local res = anchor.reanchor(old, new, items)
  local out = {}
  for _, it in ipairs(items) do
    out[it.id] = res[it.id] and { text = text_at(new, res[it.id]), how = res[it.id].how } or false
  end
  return out
end

local base = {
  'The quick brown fox jumps over the lazy dog.',
  'A second line with some words.',
  'Third line: the end.',
}

T['unchanged text keeps positions'] = function()
  local out = run(base, base, item(base, 'brown fox'))
  eq(out['brown fox'], { text = 'brown fox', how = 'same' })
end

T['lines inserted above shift the span'] = function()
  local new = { 'new first line', '', unpack(base) }
  eq(run(base, new, item(base, 'some words'))['some words'].text, 'some words')
end

T['edit on the same line before the span'] = function()
  local new = vim.deepcopy(base)
  new[2] = 'A rewritten second line with some words.'
  eq(run(base, new, item(base, 'some words'))['some words'], { text = 'some words', how = 'mapped' })
end

T['edit inside the span keeps it, as edited'] = function()
  local new = vim.deepcopy(base)
  new[1] = 'The quick red fox jumps over the lazy dog.'
  eq(run(base, new, item(base, 'quick brown fox'))['quick brown fox'], { text = 'quick red fox', how = 'edited' })
end

T['deleting the span detaches it'] = function()
  local new = vim.deepcopy(base)
  new[1] = 'The quick jumps over the lazy dog.'
  eq(run(base, new, item(base, 'brown fox '))['brown fox '], false)
end

T['deleted short common word is not re-attached to another occurrence'] = function()
  local new = vim.deepcopy(base)
  new[1] = 'The quick brown fox jumps over lazy dog.'
  -- "the" (2nd occurrence, lowercase) is deleted; "the" still exists on line 3
  local it = item(base, 'the', 1, 'the1')
  eq(run(base, new, it).the1, false)
end

T['moved block is found by quote and context'] = function()
  local old = { 'alpha', 'beta paragraph with a highlighted phrase inside it', 'gamma', 'delta', 'epsilon' }
  local new = { 'alpha', 'gamma', 'delta', 'epsilon', 'beta paragraph with a highlighted phrase inside it' }
  eq(run(old, new, item(old, 'highlighted phrase')), { ['highlighted phrase'] = { text = 'highlighted phrase', how = 'relocated' } })
end

T['whole-buffer reformat (indent + trailing space) keeps every span'] = function()
  local old = { 'function foo()  ', 'local x = 1   ', 'return x + 2', 'end' }
  local new = { 'function foo()', '  local x = 1', '  return x + 2', 'end' }
  local out = run(old, new, item(old, 'x = 1'), item(old, 'return x'), item(old, 'foo()'))
  eq(out['x = 1'].text, 'x = 1')
  eq(out['return x'].text, 'return x')
  eq(out['foo()'].text, 'foo()')
end

T['formatter rewrapping a paragraph keeps the span'] = function()
  local old = { 'This is a long paragraph that a formatter will rewrap so the', 'highlighted words move to a different line entirely.' }
  local new = { 'This is a long paragraph that a formatter will', 'rewrap so the highlighted words move to a', 'different line entirely.' }
  local out = run(old, new, item(old, 'highlighted words'), item(old, 'formatter'))
  eq(out['highlighted words'].text, 'highlighted words')
  eq(out['formatter'].text, 'formatter')
end

T['multi-line span survives edits around it'] = function()
  local q = 'brown fox jumps over the lazy dog.\nA second'
  local new = { 'Intro.', 'The quick brown fox jumps over the lazy dog.', 'A second line, edited.', 'Third line: the end.' }
  eq(run(base, new, item(base, q))[q].text, q)
end

T['multibyte text maps by character'] = function()
  local old = { 'café ünïcödé — naïve façade' }
  local new = { 'le café ünïcödé — très naïve façade' }
  local out = run(old, new, item(old, 'naïve'), item(old, 'ünïcödé'))
  eq(out['naïve'].text, 'naïve')
  eq(out['ünïcödé'].text, 'ünïcödé')
end

T['empty new buffer detaches everything'] = function()
  eq(run(base, { '' }, item(base, 'brown fox'))['brown fox'], false)
end

T['similarity'] = function()
  eq(anchor.similarity('abc', 'abc'), 1)
  eq(anchor.similarity('abc', ''), 0)
  eq(anchor.similarity('quick brown', 'brown'), 2 * 5 / 16)
end

T['locate finds by context and refuses ambiguous short quotes'] = function()
  local t = anchor.text(base)
  local it = item(base, 'the', 1)
  local s = anchor.locate(t, it)
  eq(s, 31) -- the lowercase "the" on line 1 (context matches)
  local bare = { quote = 'the', prefix = '', suffix = '' }
  eq(anchor.locate(t, bare), nil)
end

T['fuzzy matcher agrees with a brute-force edit distance'] = function()
  local function brute(str, pat, k)
    local m, set = #pat, {}
    local col = {}
    for i = 0, m do col[i] = i end
    for j = 1, #str do
      local prev = col[0]
      col[0] = 0
      for i = 1, m do
        local cur = col[i]
        col[i] = math.min(prev + (pat:byte(i) == str:byte(j) and 0 or 1), col[i - 1] + 1, cur + 1)
        prev = cur
      end
      if col[m] <= k then set[j] = col[m] end
    end
    return set
  end
  math.randomseed(11)
  local alpha = 'ab c'
  local function rnd(len)
    local t = {}
    for i = 1, len do
      local r = math.random(#alpha)
      t[i] = alpha:sub(r, r)
    end
    return table.concat(t)
  end
  for _ = 1, 500 do
    local str, pat, k = rnd(math.random(0, 30)), rnd(math.random(1, 8)), math.random(0, 3)
    local set = brute(str, pat, k)
    local seen = {}
    for _, h in ipairs(anchor._approx(str, pat, k)) do
      eq(set[h.e], h.dist) -- every reported end is a real match with the right distance
      for j = h.first, h.last do seen[j] = true end
    end
    for j in pairs(set) do
      eq({ j, seen[j] or false }, { j, true }) -- and every real match end is in a reported run
    end
  end
end

T['a typo in the quote is found by fuzzy matching when there is no snapshot'] = function()
  local lines = { 'Intro line.', 'The committee approved the annual budget yesterday.', 'Outro.' }
  local it = item(lines, 'approved the annual budget')
  local new = vim.deepcopy(lines)
  new[2] = 'The committee aproved the anual budget yesterday.'
  table.insert(new, 1, 'A new first line')
  local r = anchor.reanchor_by_quote(new, { it })[it.id]
  eq(text_at(new, r), 'aproved the anual budget')
  eq(r.how, 'fuzzy')
  eq(r.score < 1, true)
end

T['two equal occurrences with equal context are ambiguous'] = function()
  local lines = { 'call compute(a);', 'other', 'call compute(a);' }
  local it = { id = 'x', quote = 'compute(a)', prefix = 'call ', suffix = ';' } -- no position hint
  local r = anchor.reanchor_by_quote(lines, { it })[it.id]
  eq(r.ambiguous, true)
end

T['a repeated quote with distinct context relocates to the right one'] = function()
  local lines = { 'alpha: the value here', 'beta: the value here', 'gamma' }
  local it = item(lines, 'the value', 2)
  local new = { 'gamma', 'zeta', 'alpha: the value here', 'beta: the value here' }
  local r = anchor.reanchor_by_quote(new, { it })[it.id]
  eq(r.s[1], 3)
  eq(r.score >= 0.9, true)
  eq(r.ambiguous or false, false)
end

T['a moved and edited sentence is found again with a snapshot'] = function()
  local old = { 'First paragraph stays.', '', 'The quick brown fox jumps over the lazy dog today.', '', 'End.' }
  local it = item(old, 'quick brown fox jumps over the lazy dog')
  local new = { 'The quick brown fox jumped over the lazy dog today.', '', 'First paragraph stays.', '', 'End.' }
  local r = anchor.reanchor(old, new, { it })[it.id]
  eq(r ~= false, true)
  eq(r.s[1], 0)
  eq(r.how == 'fuzzy' or r.how == 'edited', true)
end

T['context grows until the quote is unique'] = function()
  local lines = { 'one two three. one two three. one two three.' }
  local pre, suf = anchor.unique_context(lines, { 0, 19 }, { 0, 22 }, 4) -- the middle "two"
  local t = anchor.text(lines)
  local count = 0
  local needle = pre .. 'two' .. suf
  local init = 1
  while true do
    local f = t.str:find(needle, init, true)
    if not f then break end
    count, init = count + 1, f + 1
  end
  eq(count, 1)
  -- a unique quote keeps the requested size (plus word padding)
  local p2 = anchor.unique_context({ 'aaaa bbbb unique cccc dddd' }, { 0, 10 }, { 0, 16 }, 3)
  eq(p2, 'bbbb ')
end

T['re-anchoring a reindented 20k-line buffer stays fast'] = function()
  local old, items = {}, {}
  for i = 1, 20000 do
    old[i] = ('line %d has some words: alpha beta gamma %d'):format(i, i * 7)
  end
  for i = 1, 200 do
    local row = i * 97
    items[i] = { id = 'a' .. i, s = { row, 5 }, e = { row, 20 }, quote = old[row + 1]:sub(6, 20) }
  end
  local new = {}
  for i, l in ipairs(old) do
    new[i] = '    ' .. l
  end
  local t0 = vim.uv.hrtime()
  local res = anchor.reanchor(old, new, items)
  local ms = (vim.uv.hrtime() - t0) / 1e6
  for _, it in ipairs(items) do
    eq(anchor.span_text(new, res[it.id].s, res[it.id].e), it.quote)
  end
  eq({ 'ms', ms < 1500 }, { 'ms', true })
end

T['a replaced word maps to its replacement, also when a paragraph above was deleted'] = function()
  local old = {
    '# Council minutes', '',
    'Several members argued that the roads were in worse shape than anyone admitted.',
    'The motion passed by seven votes to two after midnight.', '',
    'Revenue grew by 40% last year.',
  }
  local new = {
    '# Council minutes', '',
    'The motion passed by nine votes to four after midnight.', '',
    'Revenue grew by 40% last year.',
  }
  local out = run(old, new, item(old, 'seven votes to two'), item(old, '40%'))
  eq(out['seven votes to two'], { text = 'nine votes to four', how = 'edited' })
  eq(out['40%'].text, '40%')
  -- the same edit within one line
  out = run({ old[4] }, { new[3] }, item({ old[4] }, 'seven votes to two'))
  eq(out['seven votes to two'].text, 'nine votes to four')
end

return T
