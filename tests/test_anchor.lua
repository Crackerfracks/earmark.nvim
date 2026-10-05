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

return T
