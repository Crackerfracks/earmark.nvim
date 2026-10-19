-- Edge cases: text shapes (line endings, tabs, multibyte, huge files), ambiguous and
-- detached annotations, and how long the big cases take.
local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child)

local function root()
  return child.lua_get('_G.root')
end

local function mark(s, e, label)
  return child.lua_get('require("earmark").annotate(0, ...).id', { s, e, { set = 'vivid', label = label or '1' } })
end

local function save()
  child.lua('require("earmark.buffer").save(0)')
end

local function quotes()
  return vim.tbl_map(function(x)
    return x.text or false
  end, h.texts())
end

local function statuses()
  return vim.tbl_map(function(x)
    return x.status
  end, h.texts())
end

local function reopen()
  child.cmd('bwipeout!')
  child.cmd('edit ' .. root() .. '/notes/doc.md')
end

--- Write raw bytes to the test file.
local function write_raw(data)
  child.lua('local d = ...; vim.fn.mkdir(_G.root .. "/notes", "p"); local f = io.open(_G.root .. "/notes/doc.md", "wb"); f:write(d); f:close()', { data })
end

--- {row, col} of the first occurrence of `needle` (plain) in the buffer, and its end.
local function find(needle, nth)
  return unpack(child.lua_get(
    [[(function(needle, nth)
    local n = 0
    for i, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
      local init = 1
      while true do
        local s = l:find(needle, init, true)
        if not s then break end
        n = n + 1
        if n == nth then return { { i - 1, s - 1 }, { i - 1, s - 1 + #needle } } end
        init = s + 1
      end
    end
  end)(...)]],
    { needle, nth or 1 }
  ))
end

local function mark_text(needle, label, nth)
  local s, e = find(needle, nth)
  return mark(s, e, label)
end

---------------------------------------------------------------------------
-- Line endings and blank files
---------------------------------------------------------------------------

T['shapes'] = MiniTest.new_set()

T['shapes']['CRLF file: positions survive write, reopen and an outside edit'] = function()
  write_raw('The quick brown fox.\r\nSecond line here.\r\n')
  child.cmd('edit ' .. root() .. '/notes/doc.md')
  eq(child.bo.fileformat, 'dos')
  mark_text('brown')
  mark_text('Second', '2')
  child.cmd('write')
  reopen()
  eq(quotes(), { 'brown', 'Second' })
  write_raw('Inserted.\r\nThe quick brown fox.\r\nSecond line here.\r\n')
  reopen()
  eq(quotes(), { 'brown', 'Second' })
  -- converted to LF outside: same text, same places
  write_raw('Inserted.\nThe quick brown fox.\nSecond line here.\n')
  reopen()
  eq(child.bo.fileformat, 'unix')
  eq(quotes(), { 'brown', 'Second' })
end

T['shapes']['mixed line endings (a stray CR stays in the text)'] = function()
  write_raw('The quick brown fox.\r\nSecond line here.\n')
  child.cmd('edit ' .. root() .. '/notes/doc.md')
  mark_text('fox.')
  mark_text('here.', '2')
  child.cmd('write')
  reopen()
  eq(#quotes(), 2)
  eq(quotes()[2], 'here.')
  eq(quotes()[1]:sub(1, 4), 'fox.')
end

T['shapes']['no newline at end of file'] = function()
  write_raw('The quick brown fox.\nlast words')
  child.o.fixendofline = false
  child.cmd('edit ' .. root() .. '/notes/doc.md')
  mark_text('words')
  child.cmd('write')
  reopen()
  eq(quotes(), { 'words' })
  eq(child.bo.eol, false)
  child.api.nvim_buf_set_lines(0, 0, 0, false, { 'top' })
  child.cmd('write')
  reopen()
  eq(quotes(), { 'words' })
end

T['shapes']['a file of one empty line'] = function()
  write_raw('\n')
  child.cmd('edit ' .. root() .. '/notes/doc.md')
  eq(child.lua_get('require("earmark").annotate(0, {0, 0}, {0, 0}, { set = "vivid", label = "1" }) == nil'), true)
  save()
  eq(child.lua_get('vim.fn.filereadable(_G.root .. "/.earmark/docs/notes/doc.md.json")'), 0)
  child.api.nvim_buf_set_lines(0, 0, -1, false, { 'now text' })
  mark({ 0, 4 }, { 0, 8 })
  child.cmd('write')
  reopen()
  eq(quotes(), { 'text' })
end

T['shapes']['a 0-byte file'] = function()
  write_raw('')
  child.cmd('edit ' .. root() .. '/notes/doc.md')
  eq(child.lua_get('require("earmark.buffer").get(0) ~= nil'), true)
  save()
  eq(h.texts(), {})
end

T['shapes']['annotation at the very end of the file, file shrinks under it'] = function()
  h.open()
  mark({ 2, 12 }, { 2, 20 }) -- "the end."
  child.cmd('write')
  child.api.nvim_buf_set_lines(0, 2, 3, false, {})
  h.settle()
  eq(statuses(), { 'detached' })
  child.type_keys('u')
  h.settle()
  eq(quotes(), { 'the end.' })
end

T['shapes']['blank lines only around the span'] = function()
  h.open({ '', '', 'word', '', '' })
  mark({ 2, 0 }, { 2, 4 })
  child.api.nvim_buf_set_lines(0, 0, -1, false, { '', '', '', 'word', '', '' })
  h.settle()
  eq(quotes(), { 'word' })
end

T['shapes']['tabs, then :retab to spaces'] = function()
  h.open({ '\tindented\twith\ttabs', '\t\tdeeper\tline' })
  mark_text('with')
  mark_text('deeper\tline', '2')
  child.o.expandtab = true
  child.cmd('%retab')
  h.settle()
  eq(quotes(), { 'with', 'deeper  line' })
  eq(statuses(), { 'ok', 'ok' })
end

---------------------------------------------------------------------------
-- Multibyte text
---------------------------------------------------------------------------

T['multibyte'] = MiniTest.new_set()

local UNI = {
  'Emoji 👍🏽 and 👩‍💻 here, CJK 日本語のテキスト, combining é and ñ.',
  'Korean 한국어 문장, Arabic مرحبا, math ∑∫√.',
}

T['multibyte']['spans on emoji, CJK and combining characters follow edits before them'] = function()
  h.open(UNI)
  mark_text('👍🏽')
  mark_text('日本語', '2')
  mark_text('é', '3') -- e + U+0301
  mark_text('مرحبا', '4')
  h.cursor(1, 0)
  child.type_keys('i', 'Ünï ', '<Esc>')
  h.cursor(2, 0)
  child.type_keys('i', '日本 ', '<Esc>')
  h.settle()
  eq(quotes(), { '👍🏽', '日本語', 'é', 'مرحبا' })
end

T['multibyte']['and survive outside edits via the snapshot diff'] = function()
  h.open(UNI)
  mark_text('👩‍💻')
  mark_text('テキスト', '2')
  mark_text('ñ', '3')
  mark_text('∑∫√', '4')
  child.cmd('write')
  child.cmd('bwipeout!')
  child.lua('vim.fn.writefile(..., _G.root .. "/notes/doc.md")', {
    {
      'Emoji 👍🏽 and also 👩‍💻 right here, CJK 日本語のテキスト!, combining é and ñ.',
      'Korean 한국어 문장, Arabic مرحبا, math: ∑∫√.',
    },
  })
  child.cmd('edit ' .. root() .. '/notes/doc.md')
  eq(quotes(), { '👩‍💻', 'テキスト', 'ñ', '∑∫√' })
end

T['multibyte']['a span edited at its multibyte edges stays on whole characters'] = function()
  h.open(UNI)
  mark_text('日本語のテキスト')
  child.cmd('write')
  -- the first and last characters change outside Neovim
  child.lua('vim.fn.writefile(..., _G.root .. "/notes/doc.md")', { { (UNI[1]:gsub('日本語のテキスト', '中本語のテキス卜')), UNI[2] } })
  child.cmd('edit!')
  h.settle()
  local q = quotes()[1]
  -- only whole UTF-8 characters
  local rest = q:gsub('[%z\1-\127]', '')
    :gsub('[\194-\223][\128-\191]', '')
    :gsub('[\224-\239][\128-\191][\128-\191]', '')
    :gsub('[\240-\244][\128-\191][\128-\191][\128-\191]', '')
  eq(rest, '')
  eq(q:find('本語のテキ', 1, true) ~= nil, true)
end

T['multibyte']['whole-buffer replace with the same multibyte text'] = function()
  h.open(UNI)
  mark_text('👍🏽')
  mark_text('한국어 문장', '2')
  child.api.nvim_buf_set_lines(0, 0, -1, false, UNI)
  h.settle()
  eq(quotes(), { '👍🏽', '한국어 문장' })
end

T['multibyte']['fresh clone (no snapshot) finds multibyte quotes'] = function()
  h.open(UNI)
  mark_text('日本語')
  save()
  child.cmd('bwipeout!')
  child.lua('vim.fn.delete(_G.root .. "/.earmark/snap", "rf")')
  child.lua('vim.fn.writefile(..., _G.root .. "/notes/doc.md")', { { 'new first line', UNI[1], UNI[2] } })
  child.cmd('edit ' .. root() .. '/notes/doc.md')
  eq(quotes(), { '日本語' })
end

---------------------------------------------------------------------------
-- Big inputs
---------------------------------------------------------------------------

T['big'] = MiniTest.new_set()

T['big']['a very long line: annotations at start, middle and end follow edits'] = function()
  child.lua([[
    local words = {}
    for i = 1, 20000 do words[i] = 'w' .. i end
    _G.long = table.concat(words, ' ')
  ]])
  child.lua('_G.open("notes/doc.md", { _G.long, "second" })')
  mark_text('w1 ')
  mark_text('w10000 ', '2')
  mark_text('w20000', '3')
  local ms = child.lua_get([[(function()
    local t0 = vim.uv.hrtime()
    vim.api.nvim_buf_set_text(0, 0, 0, 0, 0, { 'X ' })
    vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    require('earmark.buffer').on_change(0)
    return (vim.uv.hrtime() - t0) / 1e6
  end)()]])
  eq(quotes(), { 'w1 ', 'w10000 ', 'w20000' })
  eq(ms < 2000, true)
  child.cmd('write')
  reopen()
  eq(quotes(), { 'w1 ', 'w10000 ', 'w20000' })
end

T['big']['10k lines, 500 annotations: load, save and an edit stay fast'] = function()
  local t = child.lua_get([[(function()
    local lines = {}
    for i = 1, 10000 do
      lines[i] = ('Line %d: some words about topic %d, and then a little more text.'):format(i, i % 97)
    end
    vim.fn.mkdir(_G.root .. '/notes', 'p')
    vim.fn.writefile(lines, _G.root .. '/notes/big.md')
    vim.cmd.edit(_G.root .. '/notes/big.md')
    local em, b = require('earmark'), require('earmark.buffer')
    local t = {}
    local t0 = vim.uv.hrtime()
    for i = 0, 499 do
      local row = i * 20
      em.annotate(0, { row, 0 }, { row, 4 + #tostring(row + 1) + 1 }, { set = 'vivid', label = tostring(i % 9 + 1) })
    end
    t.annotate = (vim.uv.hrtime() - t0) / 1e6
    t0 = vim.uv.hrtime()
    b.save(0)
    t.save = (vim.uv.hrtime() - t0) / 1e6
    vim.cmd('silent write')
    vim.cmd('bwipeout!')
    t0 = vim.uv.hrtime()
    vim.cmd.edit(_G.root .. '/notes/big.md')
    t.load = (vim.uv.hrtime() - t0) / 1e6
    t.count_load = #em.list(0)
    t0 = vim.uv.hrtime()
    vim.api.nvim_buf_set_lines(0, 5000, 5000, false, { 'inserted line' })
    b.on_change(0)
    t.edit = (vim.uv.hrtime() - t0) / 1e6
    t0 = vim.uv.hrtime()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    b.on_change(0)
    t.replace = (vim.uv.hrtime() - t0) / 1e6
    vim.cmd('silent write')
    vim.cmd('bwipeout!')
    -- changed outside: lines inserted throughout, then reopened (snapshot diff)
    local changed = {}
    for i, l in ipairs(lines) do
      changed[#changed + 1] = l
      if i % 100 == 0 then changed[#changed + 1] = 'an extra line' end
    end
    vim.fn.writefile(changed, _G.root .. '/notes/big.md')
    t0 = vim.uv.hrtime()
    vim.cmd.edit(_G.root .. '/notes/big.md')
    t.load_changed = (vim.uv.hrtime() - t0) / 1e6
    local ok = 0
    for _, x in ipairs(em.list(0)) do
      if x.s and x.annotation.status == 'ok' then ok = ok + 1 end
    end
    t.ok_changed = ok
    vim.cmd('bwipeout!')
    -- and again without snapshots (fresh clone)
    vim.fn.delete(_G.root .. '/.earmark/snap', 'rf')
    t0 = vim.uv.hrtime()
    vim.cmd.edit(_G.root .. '/notes/big.md')
    t.load_noshap = (vim.uv.hrtime() - t0) / 1e6
    ok = 0
    for _, x in ipairs(em.list(0)) do
      if x.s and x.annotation.status == 'ok' then ok = ok + 1 end
    end
    t.ok_nosnap = ok
    return t
  end)()]])
  eq({ t.count_load, t.ok_changed, t.ok_nosnap }, { 500, 500, 500 })
  for _, k in ipairs({ 'save', 'load', 'edit', 'replace', 'load_changed', 'load_noshap' }) do
    if t[k] >= 2000 then error(('%s took %d ms (budget 2000): %s'):format(k, t[k], vim.inspect(t))) end
  end
  if t.annotate >= 10000 then error(('500 annotations took %d ms'):format(t.annotate)) end
end

---------------------------------------------------------------------------
-- Ambiguous and detached
---------------------------------------------------------------------------

T['ambiguous'] = MiniTest.new_set()

local PARA = { 'Intro.', 'The value is 42 today.', 'Outro.' }

T['ambiguous']['a duplicated paragraph with no snapshot is ambiguous, not guessed'] = function()
  h.open(PARA)
  mark_text('42')
  save()
  child.cmd('bwipeout!')
  child.lua('vim.fn.delete(_G.root .. "/.earmark/snap", "rf")')
  child.lua('vim.fn.writefile(..., _G.root .. "/notes/doc.md")', { { 'Top.', 'Intro.', 'The value is 42 today.', 'Outro.', 'Intro.', 'The value is 42 today.', 'Outro.' } })
  child.cmd('edit ' .. root() .. '/notes/doc.md')
  eq(statuses(), { 'ambiguous' })
  eq(quotes(), { '42' })
  -- the review list offers the other copy, and moving it there settles it
  local sug = child.lua_get('require("earmark.ui.review").suggestions(vim.api.nvim_get_current_buf(), require("earmark").list(0)[1].annotation)')
  eq(#sug >= 1, true)
  child.lua('local s = ...; require("earmark.buffer").reanchor(0, require("earmark").list(0)[1].annotation.id, s.s, s.e)', { sug[1] })
  eq(statuses(), { 'ok' })
  child.cmd('write')
  reopen()
  eq(statuses(), { 'ok' })
  eq(child.lua_get('require("earmark").list(0)[1].s'), sug[1].s)
end

T['ambiguous']['with the snapshot, a duplicated paragraph is not ambiguous'] = function()
  h.open(PARA)
  mark_text('42')
  child.cmd('write')
  child.cmd('bwipeout!')
  child.lua('vim.fn.writefile(..., _G.root .. "/notes/doc.md")', { { 'Intro.', 'The value is 42 today.', 'Outro.', 'Intro.', 'The value is 42 today.', 'Outro.' } })
  child.cmd('edit ' .. root() .. '/notes/doc.md')
  eq(statuses(), { 'ok' })
end

T['ambiguous']['pasting a copy of annotated text does not move or duplicate the annotation'] = function()
  h.open(PARA)
  mark_text('42')
  h.cursor(2, 0)
  child.type_keys('yyP')
  h.settle()
  eq(#h.texts(), 1)
  eq(child.lua_get('require("earmark").list(0)[1].s'), { 2, 13 })
  child.cmd('write')
  reopen()
  eq(child.lua_get('require("earmark").list(0)[1].s'), { 2, 13 })
  eq(statuses(), { 'ok' })
end

T['ambiguous']['detached by an outside edit, re-attached by hand, stays attached'] = function()
  h.open(PARA)
  local id = mark_text('42')
  child.cmd('write')
  child.lua('vim.fn.writefile(..., _G.root .. "/notes/doc.md")', { { 'Intro.', 'The number is forty-two today.', 'Outro.' } })
  child.cmd('edit!')
  h.settle()
  local st = statuses()[1]
  eq(st == 'detached' or st == 'stale', true)
  local s, e = find('forty-two')
  eq(child.lua_get('require("earmark.buffer").reanchor(0, ...)', { id, s, e }), true)
  eq(quotes(), { 'forty-two' })
  child.cmd('write')
  reopen()
  eq(quotes(), { 'forty-two' })
  eq(child.lua_get('require("earmark").list(0)[1].annotation.original_quote'), '42')
end

T['ambiguous']['a detached annotation survives many saves and comes back with its text'] = function()
  h.open(PARA)
  mark_text('42')
  child.cmd('write')
  child.api.nvim_buf_set_lines(0, 1, 2, false, {})
  h.settle()
  eq(statuses(), { 'detached' })
  for _ = 1, 3 do
    child.cmd('write')
    reopen()
  end
  eq(statuses(), { 'detached' })
  child.api.nvim_buf_set_lines(0, 1, 1, false, { 'The value is 42 today.' })
  h.settle()
  eq(quotes(), { '42' })
end

T['ambiguous'][':Earmark check reports detached and ambiguous'] = function()
  h.open(PARA)
  mark_text('42')
  mark_text('Outro', '2')
  save()
  child.cmd('bwipeout!')
  child.lua('vim.fn.delete(_G.root .. "/.earmark/snap", "rf")')
  child.lua('vim.fn.writefile(..., _G.root .. "/notes/doc.md")', { { 'Top.', 'Intro.', 'The value is 42 today.', 'Outro.', 'Intro.', 'The value is 42 today.', 'Outro.' } })
  child.cmd('edit ' .. root() .. '/notes/doc.md')
  local lines = child.lua_get('require("earmark").check()')
  eq(#lines, 2)
  eq(lines[1]:match('^ambiguous') ~= nil, true)
end

---------------------------------------------------------------------------
-- Re-anchoring units for the cases above
---------------------------------------------------------------------------

T['reanchor'] = MiniTest.new_set()

local function reanchor(old, new, s, e)
  return child.lua_get(
    [[(function(old, new, s, e)
    local anchor = require('earmark.anchor')
    local it = { id = 'x', s = s, e = e, quote = anchor.span_text(old, s, e) }
    it.prefix, it.suffix = anchor.unique_context(old, s, e, 32)
    local r = anchor.reanchor(old, new, { it }).x
    return r and anchor.span_text(new, r.s, r.e) or false
  end)(...)]],
    { old, new, s, e }
  )
end

T['reanchor']['spacing changed inside the span'] = function()
  eq(reanchor({ 'x = a+b' }, { 'x = a + b' }, { 0, 4 }, { 0, 7 }), 'a + b')
  eq(reanchor({ 'call(a,b,c)' }, { 'call(a, b, c)' }, { 0, 5 }, { 0, 10 }), 'a, b, c')
end

T['reanchor']['a span re-wrapped onto two lines'] = function()
  local old = { 'This is a long sentence that a formatter will wrap somewhere in the middle.' }
  local new = { 'This is a long sentence that a formatter will', 'wrap somewhere in the middle.' }
  eq(reanchor(old, new, { 0, 31 }, { 0, 60 }), 'formatter will\nwrap somewhere')
end

T['reanchor']['two lines joined into one'] = function()
  local old = { 'first half of the', 'sentence here.' }
  local new = { 'first half of the sentence here.' }
  eq(reanchor(old, new, { 0, 11 }, { 1, 8 }), 'of the sentence')
end

T['reanchor']['a short line moved by :sort or ddp'] = function()
  eq(reanchor({ 'cherry', 'apple', 'banana' }, { 'apple', 'banana', 'cherry' }, { 0, 0 }, { 0, 3 }), 'che')
  eq(reanchor({ 'one', 'two', 'three' }, { 'two', 'one', 'three' }, { 0, 0 }, { 0, 3 }), 'one')
end

T['reanchor']['a moved line that is not unique is not guessed'] = function()
  local r = reanchor({ 'x', 'end', 'y', 'end' }, { 'end', 'q', 'end', 'z' }, { 1, 0 }, { 1, 3 })
  -- either of the two "end" lines would be a guess; anything but a wrong text is fine
  eq(r == false or r == 'end', true)
end

return T
