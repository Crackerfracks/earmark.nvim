-- The public API and its events, with hostile inputs: other plugins build on these, so
-- nothing here may throw, corrupt state, or fire events that don't match what changed.
local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child, [[{ prompt = { ask_name = 'never' }, sets = { 'vivid', review = { labels = {
  { key = 'acc', name = 'Accuracy', color = '#e06c75', desc = 'is it right?', tags = { 'check' },
    choices = { { key = 'a', name = 'Correct' }, { key = 'b', name = 'Minor issue', color = '#e5c07b' } } } } } } }]])

local V3 = { set = 'vivid', label = '3' }

-- every User Earmark* event since the last call: { name, buf, action, ids }
local function record()
  child.lua([[
    _G.events = {}
    vim.api.nvim_create_autocmd('User', { pattern = 'Earmark*', callback = function(ev)
      local d = ev.data or {}
      table.insert(_G.events, { name = ev.match, buf = d.buf, action = d.action, ids = d.ids })
    end })
  ]])
end

local function events()
  local out = child.lua_get('_G.events')
  child.lua('_G.events = {}')
  return out
end

local function errors()
  return child.lua_get([[vim.tbl_filter(function(l) return l:find(' ERROR ', 1, true) ~= nil end,
    require('earmark.log').entries)]])
end

local function mark(s, e, value, buf)
  return child.lua_get('(require("earmark").annotate(...) or {}).id', { buf or 0, s, e, value or V3 })
end

local function bufnr()
  return child.api.nvim_get_current_buf()
end

---------------------------------------------------------------------------
-- Buffers
---------------------------------------------------------------------------

T['buffers'] = MiniTest.new_set()

T['buffers']['buf 0, nil and the explicit number mean the same buffer'] = function()
  h.open()
  local b = bufnr()
  local id = mark({ 0, 4 }, { 0, 9 }, V3, b)
  eq(child.lua_get('#require("earmark").list(0)'), 1)
  eq(child.lua_get('#require("earmark").list()'), 1)
  eq(child.lua_get('require("earmark").get(nil, ...).id', { id }), id)
  eq(child.lua_get('require("earmark").get(...).id', { b, id }), id)
  eq(child.lua_get('require("earmark").set_note(nil, ...)', { id, 'x' }), true)
  eq(child.lua_get('require("earmark").get(0, ...).note', { id }), 'x')
end

T['buffers']['works on a buffer that is not the current one'] = function()
  local a = h.open(nil, 'a.md')
  local b = child.api.nvim_get_current_buf()
  h.open({ 'other' }, 'b.md')
  record()
  local id = mark({ 0, 4 }, { 0, 9 }, V3, b)
  eq(child.lua_get('#require("earmark").list(0)'), 0)
  eq(child.lua_get('#require("earmark").list(...)', { b }), 1)
  eq(child.lua_get('#vim.api.nvim_buf_get_extmarks(..., require("earmark.buffer").ns, 0, -1, {})', { b }), 1)
  eq(child.lua_get('require("earmark").at(..., { 0, 5 })[1].annotation.id', { b }), id)
  eq(child.lua_get('require("earmark").set_note(...)', { b, id, 'n' }), true)
  for _, e in ipairs(events()) do
    eq(e.buf, b)
  end
  eq(a ~= nil, true)
end

T['buffers']['invalid buffer numbers: nothing throws, nothing is created'] = function()
  h.open()
  record()
  local r = child.lua_get([[(function()
    local em = require('earmark')
    local out = {}
    for _, b in ipairs({ 9999, -1 }) do
      out[#out + 1] = {
        annotate = em.annotate(b, { 0, 0 }, { 0, 3 }, { set = 'vivid', label = '3' }) == nil,
        list = #em.list(b), at = #em.at(b, { 0, 0 }), get = em.get(b, 'x') == nil,
        note = em.set_note(b, 'x', 'n'), tags = em.set_tags(b, 'x', { 't' }),
        values = em.set_values(b, 'x', { { set = 'vivid', label = '3' } }),
        erase = em.erase(b, { 'x' }), restore = em.restore(b),
        rename = em.rename_label(b, { set = 'vivid', label = '3' }, 'N'),
        names = vim.tbl_count(em.names(b)), export = #em.export(b),
        display = em.display_name(b, { set = 'vivid', label = '3' }),
        state = require('earmark.buffer').state[b] == nil,
      }
    end
    return out
  end)()]])
  local want = {
    annotate = true, list = 0, at = 0, get = true, note = false, tags = false, values = false, erase = 0,
    restore = 0, rename = false, names = 0, export = 0, display = '3', state = true,
  }
  eq(r, { want, want })
  eq(events(), {})
  eq(errors(), {})
end

T['buffers']['a wiped buffer: state is dropped and the API treats it as gone'] = function()
  h.open()
  local b = bufnr()
  local id = mark({ 0, 4 }, { 0, 9 })
  child.cmd('enew')
  child.cmd('bwipeout! ' .. b)
  record()
  eq(child.lua_get('require("earmark.buffer").state[...] == nil', { b }), true)
  eq(child.lua_get('#require("earmark").list(...)', { b }), 0)
  eq(child.lua_get('require("earmark").get(...) == nil', { b, id }), true)
  eq(child.lua_get('require("earmark").set_note(...)', { b, id, 'n' }), false)
  eq(child.lua_get('require("earmark").erase(...)', { b, { id } }), 0)
  eq(child.lua_get('require("earmark").annotate(..., { 0, 0 }, { 0, 2 }, { set = "vivid", label = "3" }) == nil', { b }), true)
  eq(child.lua_get('require("earmark").rename_label(..., { set = "vivid", label = "3" }, "N")', { b }), false)
  eq(child.lua_get('#require("earmark").export(...)', { b }), 0)
  eq(events(), {})
  eq(errors(), {})
end

T['buffers']['an unloaded buffer is left alone, and loads its annotations when opened'] = function()
  local path = h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  child.cmd('enew')
  child.cmd('bwipeout! ' .. child.lua_get('vim.fn.bufnr(...)', { path }))
  local b = child.lua_get('vim.fn.bufadd(...)', { path })
  eq(child.lua_get('vim.api.nvim_buf_is_loaded(...)', { b }), false)
  record()
  local r = child.lua_get([[(function(b)
    local em = require('earmark')
    return {
      annotate = em.annotate(b, { 1, 0 }, { 1, 3 }, { set = 'vivid', label = '4' }) == nil,
      rename = em.rename_label(b, { set = 'vivid', label = '3' }, 'N'),
      list = #em.list(b), names = vim.tbl_count(em.names(b)),
      state = require('earmark.buffer').state[b] == nil,
    }
  end)(...)]], { b })
  eq(r, { annotate = true, rename = false, list = 0, names = 0, state = true })
  eq(events(), {})
  child.cmd('buffer ' .. b)
  eq(h.ids(), { id })
  eq(vim.tbl_map(function(e) return e.name end, events()), { 'EarmarkChanged', 'EarmarkLoad' })
  eq(errors(), {})
end

T['buffers']['an unnamed buffer is annotated as a scratch document'] = function()
  child.cmd('enew')
  child.api.nvim_buf_set_lines(0, 0, -1, false, { 'scratch text here' })
  local id = mark({ 0, 0 }, { 0, 7 })
  eq(h.ids(), { id })
  eq(child.lua_get('require("earmark.buffer").state[vim.api.nvim_get_current_buf()].doc.kind'), 'scratch')
  eq(child.lua_get('require("earmark").export(0)[1]'):match('^# %[scratch%]') ~= nil, true)
  eq(child.lua_get('require("earmark").export(0)[3]'), '## 3 (vivid·3)')
end

T['buffers']['nofile and help buffers are scratch documents too'] = function()
  child.cmd('enew')
  child.bo.buftype = 'nofile'
  child.api.nvim_buf_set_lines(0, 0, -1, false, { 'nofile text' })
  eq(mark({ 0, 0 }, { 0, 6 }) ~= nil, true)
  child.cmd('help help')
  eq(child.bo.buftype, 'help')
  eq(mark({ 0, 0 }, { 0, 4 }) ~= nil, true)
  eq(#h.ids(), 1)
  eq(errors(), {})
end

T['buffers']['ignored buftypes: terminal, prompt and quickfix are never annotated'] = function()
  h.open()
  record()
  local r = child.lua_get([[(function()
    local em = require('earmark')
    local out = {}
    local function try(kind)
      local b = vim.api.nvim_get_current_buf()
      out[kind] = {
        bt = vim.bo[b].buftype,
        annotate = em.annotate(b, { 0, 0 }, { 0, 1 }, { set = 'vivid', label = '3' }) == nil,
        rename = em.rename_label(b, { set = 'vivid', label = '3' }, 'N'),
        list = #em.list(b), at = #em.at(b, { 0, 0 }), names = vim.tbl_count(em.names(b)),
        state = require('earmark.buffer').state[b] == nil,
        export = type(em.export(b)), stl = em.statusline(),
      }
    end
    vim.cmd('enew | setlocal buftype=prompt')
    try('prompt')
    vim.fn.setqflist({ { filename = 'x', lnum = 1, text = 'x' } })
    vim.cmd('copen')
    try('quickfix')
    vim.cmd('cclose | enew')
    vim.fn.jobstart({ 'sh', '-c', 'sleep 5' }, { term = true })
    try('terminal')
    return out
  end)()]])
  for kind, x in pairs(r) do
    eq({ kind, x }, { kind, { bt = kind, annotate = true, rename = false, list = 0, at = 0, names = 0, state = true,
      export = 'table', stl = '' } })
  end
  eq(events(), {})
  eq(errors(), {})
end

---------------------------------------------------------------------------
-- annotate: positions and values
---------------------------------------------------------------------------

T['annotate'] = MiniTest.new_set()

local function quote_of(id)
  return child.lua_get('require("earmark").get(0, ...).quote', { id })
end

T['annotate']['rejects empty, reversed and out-of-range spans'] = function()
  h.open()
  record()
  local r = child.lua_get([[(function()
    local em = require('earmark')
    local v = { set = 'vivid', label = '3' }
    local function nil_for(s, e) return em.annotate(0, s, e, v) == nil end
    return {
      zero = nil_for({ 0, 4 }, { 0, 4 }),
      reversed_col = nil_for({ 0, 9 }, { 0, 4 }),
      reversed_row = nil_for({ 1, 0 }, { 0, 4 }),
      row_past_end = nil_for({ 99, 0 }, { 99, 4 }),
      start_past_end = nil_for({ 3, 0 }, { 3, 1 }),
      negative_row = nil_for({ -1, 0 }, { 0, 4 }),
      nan_row = nil_for({ 0 / 0, 0 }, { 0, 4 }),
      huge_row = nil_for({ 0, 0 }, { math.huge, 4 }),
      no_start = nil_for(nil, { 0, 4 }),
      no_end = nil_for({ 0, 4 }, nil),
      bad_pos = nil_for({ 'a', 0 }, { 0, 4 }),
      short_pos = nil_for({ 0 }, { 0, 4 }),
      past_eol = nil_for({ 0, 50 }, { 0, 60 }),
      list = #em.list(0),
    }
  end)()]])
  eq(r, {
    zero = true, reversed_col = true, reversed_row = true, row_past_end = true, start_past_end = true,
    negative_row = true, nan_row = true, huge_row = true, no_start = true, no_end = true, bad_pos = true,
    short_pos = true, past_eol = true,
    list = 0,
  })
  eq(events(), {})
  eq(errors(), {})
end

T['annotate']['an end past the line clamps to the end of the line'] = function()
  h.open()
  local id = mark({ 0, 40 }, { 0, 999 })
  eq(quote_of(id), 'dog.')
  eq(child.lua_get('require("earmark").list(0)[1].e'), { 0, 44 })
  -- to the start of the line after the last one: the rest of the buffer
  local id2 = mark({ 2, 12 }, { 3, 0 })
  eq(quote_of(id2), 'the end.')
end

T['annotate']['spans across lines and onto empty lines'] = function()
  h.open({ 'one', '', 'three' })
  local id = mark({ 0, 1 }, { 2, 2 })
  eq(quote_of(id), 'ne\n\nth')
  local id2 = mark({ 1, 0 }, { 2, 0 })
  eq(quote_of(id2), '\n')
  eq(child.lua_get('#require("earmark").at(0, { 1, 0 })'), 2)
end

T['annotate']['multibyte text: columns inside a character snap outwards'] = function()
  h.open({ 'a😀b 中文字 é' .. 'e\204\129' .. 'x' })
  -- whole characters, by byte columns
  eq(quote_of(mark({ 0, 1 }, { 0, 5 })), '😀')
  eq(quote_of(mark({ 0, 7 }, { 0, 13 })), '中文')
  -- a column in the middle of a character takes the whole character
  local id = mark({ 0, 2 }, { 0, 3 }, { set = 'vivid', label = '4' })
  eq(quote_of(id), '😀')
  eq(child.lua_get('require("earmark").get(0, ...).values[1].label', { id }), '3') -- same span: stacked
  local id2 = mark({ 0, 8 }, { 0, 14 }, { set = 'vivid', label = '5' })
  eq(quote_of(id2), '中文字')
  -- combining marks: valid UTF-8 even when the mark is left out
  local line = child.api.nvim_buf_get_lines(0, 0, 1, false)[1]
  local e = line:find('e\204\129', 1, true) - 1
  eq(quote_of(mark({ 0, e }, { 0, e + 3 }, { set = 'vivid', label = '6' })), 'e\204\129')
  eq(quote_of(mark({ 0, e + 1 }, { 0, e + 2 }, { set = 'vivid', label = '7' })), '\204\129')
  eq(errors(), {})
end

T['annotate']['tab columns are bytes'] = function()
  h.open({ '\tindented\tword' })
  eq(quote_of(mark({ 0, 0 }, { 0, 1 })), '\t')
  eq(quote_of(mark({ 0, 1 }, { 0, 9 })), 'indented')
  eq(quote_of(mark({ 0, 10 }, { 0, 14 })), 'word')
end

T['annotate']['values: unknown sets and labels are kept, malformed values are refused'] = function()
  h.open()
  local r = child.lua_get([[(function()
    local em = require('earmark')
    local unknown = em.annotate(0, { 0, 4 }, { 0, 9 }, { set = 'nope', label = 'zz' })
    return {
      unknown = unknown and unknown.values[1],
      numeric = (em.annotate(0, { 1, 0 }, { 1, 1 }, { set = 'vivid', label = 4 }) or {}).values,
      no_value = em.annotate(0, { 1, 2 }, { 1, 4 }, nil) == nil,
      no_set = em.annotate(0, { 1, 2 }, { 1, 4 }, { label = '3' }) == nil,
      no_label = em.annotate(0, { 1, 2 }, { 1, 4 }, { set = 'vivid' }) == nil,
      string_value = em.annotate(0, { 1, 2 }, { 1, 4 }, 'vivid/3') == nil,
      list = #em.list(0),
      display = em.display_name(0, { set = 'nope', label = 'zz' }),
    }
  end)()]])
  eq(r, {
    unknown = { set = 'nope', label = 'zz' }, numeric = { { set = 'vivid', label = '4' } }, no_value = true,
    no_set = true, no_label = true, string_value = true, list = 2, display = 'zz',
  })
  eq(errors(), {})
end

T['annotate']['choice and text fields are kept'] = function()
  h.open()
  local v = child.lua_get([[(function()
    local em = require('earmark')
    local a = em.annotate(0, { 0, 4 }, { 0, 9 }, { set = 'review', label = 'acc', choice = 'b', text = 'why?' })
    em.annotate(0, { 0, 4 }, { 0, 9 }, { set = 'review', label = 'acc', choice = 'a' }) -- another choice stacks
    return em.get(0, a.id).values
  end)()]])
  eq(v, { { set = 'review', label = 'acc', choice = 'b', text = 'why?' }, { set = 'review', label = 'acc', choice = 'a' } })
end

T['annotate']['the same span: another label stacks, the same label is a no-op'] = function()
  h.open()
  record()
  local id = mark({ 0, 4 }, { 0, 9 })
  eq(#events(), 2)
  local r = child.lua_get([[{ select(2, require('earmark').annotate(0, { 0, 4 }, { 0, 9 }, { set = 'vivid', label = '3' })) }]])
  eq(r, { 'same' })
  eq(events(), {})
  r = child.lua_get([[{ select(2, require('earmark').annotate(0, { 0, 4 }, { 0, 9 }, { set = 'vivid', label = '5' })) }]])
  eq(r, { 'added' })
  eq(events(), {
    { name = 'EarmarkChanged', buf = bufnr(), action = 'update', ids = { id } },
    { name = 'EarmarkUpdate', buf = bufnr(), action = 'update', ids = { id } },
  })
end

T['annotate']['the caller\'s value table is not kept'] = function()
  h.open()
  local r = child.lua_get([[(function()
    local em = require('earmark')
    local v = { set = 'vivid', label = '3' }
    local a = em.annotate(0, { 0, 4 }, { 0, 9 }, v)
    v.label = '9'
    local vs = { { set = 'vivid', label = '5' } }
    em.set_values(0, a.id, vs)
    vs[1].label = '9'
    vs[2] = { set = 'vivid', label = '8' }
    return em.get(0, a.id).values
  end)()]])
  eq(r, { { set = 'vivid', label = '5' } })
end

---------------------------------------------------------------------------
-- Reading: list, at, get, names
---------------------------------------------------------------------------

T['read'] = MiniTest.new_set()

T['read']['list() is in position order, detached last with no s/e'] = function()
  h.open()
  local c = mark({ 2, 0 }, { 2, 5 })
  local b = mark({ 1, 2 }, { 1, 8 })
  local a2 = mark({ 0, 10 }, { 0, 15 })
  local a1 = mark({ 0, 4 }, { 0, 9 })
  child.api.nvim_buf_set_lines(0, 1, 2, false, {}) -- b's line goes
  child.lua('require("earmark.buffer").on_change(0)')
  local r = child.lua_get([[vim.tbl_map(function(x)
    return { id = x.annotation.id, s = x.s or false, e = x.e or false, status = x.annotation.status }
  end, require('earmark').list(0))]])
  eq(r, {
    { id = a1, s = { 0, 4 }, e = { 0, 9 }, status = 'ok' },
    { id = a2, s = { 0, 10 }, e = { 0, 15 }, status = 'ok' },
    { id = c, s = { 1, 0 }, e = { 1, 5 }, status = 'ok' },
    { id = b, s = false, e = false, status = 'detached' },
  })
  -- a detached annotation is still found by get() and listed, but at() never returns it
  eq(child.lua_get('require("earmark").get(0, ...).status', { b }), 'detached')
  eq(child.lua_get('#require("earmark").at(0, { 1, 2 })'), 1)
end

T['read']['list() on a fresh buffer and names() with no names'] = function()
  h.open()
  eq(child.lua_get('require("earmark").list(0)'), {})
  eq(child.lua_get('require("earmark").names(0)'), {})
  eq(child.lua_get('require("earmark").at(0)'), {})
  eq(child.lua_get('require("earmark").at(0, { 99, 99 })'), {})
end

T['read']['at() is innermost first with nested and equal spans'] = function()
  h.open()
  local outer = mark({ 0, 0 }, { 0, 44 })
  local mid = mark({ 0, 4 }, { 0, 19 })
  local inner = mark({ 0, 10 }, { 0, 15 })
  local r = child.lua_get('vim.tbl_map(function(x) return x.annotation.id end, require("earmark").at(0, { 0, 12 }))')
  eq(r, { inner, mid, outer })
  -- equal spans are one annotation with two labels
  mark({ 0, 10 }, { 0, 15 }, { set = 'vivid', label = '5' })
  eq(child.lua_get('#require("earmark").at(0, { 0, 12 })'), 3)
  eq(child.lua_get('#require("earmark").at(0, { 0, 12 })[1].annotation.values'), 2)
  -- the end is exclusive; the start inclusive
  eq(child.lua_get('#require("earmark").at(0, { 0, 15 })'), 2)
  eq(child.lua_get('#require("earmark").at(0, { 0, 10 })'), 3)
  -- the default position is the cursor
  h.cursor(1, 12)
  eq(child.lua_get('require("earmark").at(0)[1].annotation.id'), inner)
  eq(child.lua_get('require("earmark").at()[1].annotation.id'), inner)
end

T['read']['at() at the end of a line belongs to a span ending there'] = function()
  h.open({ 'abc', '' })
  local id = mark({ 0, 1 }, { 0, 3 })
  eq(child.lua_get('require("earmark").at(0, { 0, 3 })[1].annotation.id'), id)
  eq(child.lua_get('#require("earmark").at(0, { 1, 0 })'), 0)
end

T['read']['results are copies: changing them cannot corrupt state'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  child.lua('require("earmark").rename_label(0, { set = "vivid", label = "3" }, "Three")')
  child.lua([[
    local em = require('earmark')
    local id = ...
    local g = em.get(0, id)
    g.values[1].label = '9'; g.values[2] = { set = 'x', label = 'y' }; g.note = 'hacked'; g.status = 'detached'
    g.s[1] = 2
    local l = em.list(0)[1]
    l.annotation.values = nil; l.annotation.id = 'other'; l.s[1] = 2
    local a = em.at(0, { 0, 5 })[1]
    a.annotation.quote = 'hacked'; a.e[2] = 1
    em.names(0)['vivid/3'] = 'Hacked'
    local made = em.annotate(0, { 1, 2 }, { 1, 8 }, { set = 'vivid', label = '4' })
    made.values[1].label = '9'
  ]], { id })
  local r = child.lua_get([[(function(id)
    local em = require('earmark')
    local g = em.get(0, id)
    return { values = g.values, note = g.note or false, status = g.status, quote = g.quote, s = em.list(0)[1].s,
      e = em.list(0)[1].e, names = em.names(0), second = em.list(0)[2].annotation.values[1].label }
  end)(...)]], { id })
  eq(r, {
    values = { V3 }, note = false, status = 'ok', quote = 'quick', s = { 0, 4 }, e = { 0, 9 },
    names = { ['vivid/3'] = 'Three' }, second = '4',
  })
  -- and it saves as it was
  child.lua('require("earmark.buffer").save(0)')
  eq(child.lua_get('require("earmark.buffer").state[vim.api.nvim_get_current_buf()].annos[...].values', { id }), { V3 })
end

T['read']['get() of an unknown id, a nil id, or another buffer\'s id'] = function()
  h.open(nil, 'a.md')
  local id = mark({ 0, 4 }, { 0, 9 })
  h.open({ 'b' }, 'b.md')
  eq(child.lua_get('require("earmark").get(0, ...) == nil', { id }), true)
  eq(child.lua_get('require("earmark").get(0, "nope") == nil'), true)
  eq(child.lua_get('require("earmark").get(0, nil) == nil'), true)
end

---------------------------------------------------------------------------
-- Writing: notes, tags, values, erase/restore, names
---------------------------------------------------------------------------

T['write'] = MiniTest.new_set()

T['write']['set_note: nil, empty and blank clear; multi-line is kept as is'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  local function note(text)
    return child.lua_get([[(function(id, text)
      return { require('earmark').set_note(0, id, text), require('earmark').get(0, id).note or false }
    end)(...)]], { id, text })
  end
  local function note_nil()
    return note(nil)
  end
  eq(note('line 1\n\nline 3 #t\n'), { true, 'line 1\n\nline 3 #t\n' })
  eq(note(''), { true, false })
  eq(note('x'), { true, 'x' })
  eq(note('  \n\t'), { true, false })
  eq(note('x'), { true, 'x' })
  eq(note_nil(), { true, false })
  eq(child.lua_get('require("earmark").set_note(0, "nope", "x")'), false)
end

T['write']['set_note: a non-string note is refused'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  eq(child.lua_get('{ require("earmark").set_note(0, ..., 42) }', { id }), { false })
  eq(child.lua_get('{ require("earmark").set_note(0, ..., { "x" }) }', { id }), { false })
  eq(child.lua_get('require("earmark").get(0, ...).note == nil', { id }), true)
end

T['write']['set_tags: duplicates, empties and non-strings are dropped'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  local function tags(list)
    return child.lua_get([[(function(id, list)
      return { require('earmark').set_tags(0, id, list), require('earmark').get(0, id).tags or false }
    end)(...)]], { id, list })
  end
  eq(tags({ 'a', 'b', 'a', '', 'b' }), { true, { 'a', 'b' } })
  eq(tags({}), { true, false })
  eq(tags({ 1, true, 'c', { 'd' } }), { true, { 'c' } })
  eq(child.lua_get('{ require("earmark").set_tags(0, ..., nil), require("earmark").get(0, ...).tags or false }', { id, id }),
    { true, false })
  eq(child.lua_get('require("earmark").set_tags(0, ..., "todo")', { id }), false)
  eq(child.lua_get('require("earmark").set_tags(0, "nope", { "x" })'), false)
end

T['write']['set_values: empty or malformed lists are refused'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  local function values(list)
    return child.lua_get('(function(id, list) return require("earmark").set_values(0, id, list) end)(...)', { id, list })
  end
  eq(values({}), false)
  eq(values({ { set = 'vivid' } }), false)
  eq(values({ V3, 'vivid/4' }), false)
  eq(child.lua_get('require("earmark").set_values(0, ..., nil)', { id }), false)
  eq(child.lua_get('require("earmark").get(0, ...).values', { id }), { V3 })
  eq(values({ { set = 'nope', label = 'x' }, V3 }), true)
  eq(child.lua_get('require("earmark").get(0, ...).values', { id }), { { set = 'nope', label = 'x' }, V3 })
  eq(errors(), {})
end

T['write']['erase: mixed valid and invalid ids, duplicates, empty and nil'] = function()
  h.open()
  record()
  local a = mark({ 0, 4 }, { 0, 9 })
  local b = mark({ 1, 2 }, { 1, 8 })
  events()
  eq(child.lua_get('require("earmark").erase(0, { "nope", ..., "nope2", ... })', { a, a }), 1)
  eq(events(), {
    { name = 'EarmarkChanged', buf = bufnr(), action = 'erase', ids = { a } },
    { name = 'EarmarkErase', buf = bufnr(), action = 'erase', ids = { a } },
  })
  eq(child.lua_get('require("earmark").erase(0, { "nope" })'), 0)
  eq(child.lua_get('require("earmark").erase(0, {})'), 0)
  eq(child.lua_get('require("earmark").erase(0, nil)'), 0)
  eq(events(), {})
  eq(h.ids(), { b })
  -- the batch with only invalid ids didn't become the one restore brings back
  eq(child.lua_get('require("earmark").restore(0)'), 1)
  eq(#h.ids(), 2)
end

T['write']['restore with an empty trash, and twice in a row'] = function()
  h.open()
  record()
  eq(child.lua_get('{ require("earmark").restore(0) }'), { 0, 0 })
  local a = mark({ 0, 4 }, { 0, 9 })
  local b = mark({ 1, 2 }, { 1, 8 })
  child.lua('require("earmark").erase(0, { ... })', { a })
  child.lua('require("earmark").erase(0, { ... })', { b })
  events()
  eq(child.lua_get('{ require("earmark").restore(0) }'), { 1, 0 })
  eq(events()[2], { name = 'EarmarkRestore', buf = bufnr(), action = 'restore', ids = { b } })
  eq(child.lua_get('{ require("earmark").restore(0) }'), { 1, 0 })
  eq(child.lua_get('{ require("earmark").restore(0) }'), { 0, 0 })
  eq(#h.ids(), 2)
end

T['write']['restore of text that is gone comes back detached'] = function()
  h.open()
  local a = mark({ 2, 0 }, { 2, 5 })
  child.lua('require("earmark").erase(0, { ... })', { a })
  child.api.nvim_buf_set_lines(0, 2, 3, false, { 'nothing like it' })
  eq(child.lua_get('{ require("earmark").restore(0) }'), { 1, 1 })
  eq(child.lua_get('require("earmark").list(0)[1].s == nil'), true)
  eq(child.lua_get('require("earmark").get(0, ...).status', { a }), 'detached')
end

T['write']['rename_label to a name, to \'\' and back'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  local function rename(name)
    child.lua('require("earmark").rename_label(0, { set = "vivid", label = "3" }, ...)', { name })
    if name == nil then child.lua('require("earmark").rename_label(0, { set = "vivid", label = "3" }, nil)') end
    return { child.lua_get('require("earmark").names(0)'), child.lua_get('require("earmark").display_name(0, { set = "vivid", label = "3" })') }
  end
  eq(rename('  Vague  '), { { ['vivid/3'] = 'Vague' }, 'Vague' })
  eq(rename(''), { {}, '3' })
  eq(rename('Back'), { { ['vivid/3'] = 'Back' }, 'Back' })
  eq(rename('Again'), { { ['vivid/3'] = 'Again' }, 'Again' })
  eq(rename(nil), { {}, '3' })
  eq(child.lua_get('require("earmark").rename_label(0, nil, "x")'), false)
  eq(child.lua_get('require("earmark").rename_label(0, { set = "vivid" }, "x")'), false)
end

T['write']['setting what is already there fires nothing'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  child.lua('require("earmark").set_note(0, ..., "n")', { id })
  child.lua('require("earmark").set_tags(0, ..., { "a" })', { id })
  child.lua('require("earmark").rename_label(0, { set = "vivid", label = "3" }, "Three")')
  record()
  child.lua([[
    local em, id = require('earmark'), ...
    em.set_note(0, id, 'n')
    em.set_tags(0, id, { 'a', 'a' })
    em.set_values(0, id, { { set = 'vivid', label = '3' } })
    em.rename_label(0, { set = 'vivid', label = '3' }, 'Three')
    em.rename_label(0, { set = 'vivid', label = '4' }, nil)
  ]], { id })
  eq(events(), {})
end

---------------------------------------------------------------------------
-- export, pick, statusline, hover with no state
---------------------------------------------------------------------------

T['other'] = MiniTest.new_set()

T['other']['export on an empty buffer and with only detached annotations'] = function()
  h.open()
  local out = child.lua_get('require("earmark").export(0)')
  eq(#out, 1)
  eq(out[1]:match('^# doc%.md') ~= nil, true)
  local id = mark({ 2, 0 }, { 2, 5 })
  child.lua('require("earmark").set_note(0, ..., "first\\nsecond")', { id })
  child.api.nvim_buf_set_lines(0, 2, 3, false, {})
  child.lua('require("earmark.buffer").on_change(0)')
  for _, by in ipairs({ 'label', 'position', 'tag', 'time' }) do
    eq(vim.list_slice(child.lua_get('require("earmark").export(0, { group_by = ... })', { by }), 2), {
      '', '## Detached', '- "Third" — 3 — first',
    })
  end
  eq(#child.lua_get('require("earmark").export(0, { include_detached = false })'), 1)
end

T['other']['pick, statusline and hover with no annotations state'] = function()
  child.cmd('enew')
  eq(child.lua_get('require("earmark").statusline()'), '')
  eq(child.lua_get('require("earmark").statusline({ hl = "StatusLine" })'), '')
  child.lua('require("earmark").hover.show(); require("earmark").hover.hide()')
  child.lua('require("earmark").pick()')
  child.lua('require("earmark").pick({ scope = "project", query = "#todo" })')
  child.cmd('enew | setlocal buftype=prompt')
  eq(child.lua_get('require("earmark").statusline()'), '')
  child.lua('require("earmark").pick({ query = "" })')
  eq(errors(), {})
end

T['other']['pick and statusline on a buffer with annotations'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  eq(child.lua_get('require("earmark").statusline()'):find('1', 1, true) ~= nil, true)
  child.lua('require("earmark").pick({ query = "nothing-matches-this" })')
  eq(errors(), {})
end

---------------------------------------------------------------------------
-- display_name and label
---------------------------------------------------------------------------

T['names'] = MiniTest.new_set()

T['names']['display_name: the document\'s name, else the label\'s name, else its key'] = function()
  h.open()
  local r = child.lua_get([[(function()
    local em = require('earmark')
    local out = {}
    out.numbered = em.display_name(0, { set = 'vivid', label = '3' })
    em.rename_label(0, { set = 'vivid', label = '3' }, 'Vague')
    out.named = em.display_name(0, { set = 'vivid', label = '3' })
    out.explicit_buf = em.display_name(vim.api.nvim_get_current_buf(), { set = 'vivid', label = '3' })
    out.nil_buf = em.display_name(nil, { set = 'vivid', label = '3' })
    out.set_name = em.display_name(0, { set = 'review', label = 'acc' })
    out.choice = em.display_name(0, { set = 'review', label = 'acc', choice = 'b' })
    out.unknown_choice = em.display_name(0, { set = 'review', label = 'acc', choice = 'zz' })
    out.unknown = em.display_name(0, { set = 'nope', label = 'zz' })
    out.numeric = em.display_name(0, { set = 'vivid', label = 3 })
    out.bad = { em.display_name(0, nil), em.display_name(0, { set = 'vivid' }), em.display_name(0, 'x') }
    return out
  end)()]])
  eq(r, {
    numbered = '3', named = 'Vague', explicit_buf = 'Vague', nil_buf = 'Vague', set_name = 'Accuracy',
    choice = 'Accuracy · b Minor issue', unknown_choice = 'Accuracy', unknown = 'zz', numeric = 'Vague', bad = {},
  })
end

T['names']['display_name is per buffer'] = function()
  h.open(nil, 'a.md')
  local a = bufnr()
  child.lua('require("earmark").rename_label(0, { set = "vivid", label = "3" }, "InA")')
  h.open({ 'b' }, 'b.md')
  eq(child.lua_get('require("earmark").display_name(0, { set = "vivid", label = "3" })'), '3')
  eq(child.lua_get('require("earmark").display_name(..., { set = "vivid", label = "3" })', { a }), 'InA')
end

T['names']['label() returns a copy of the label, or nil'] = function()
  h.open()
  local r = child.lua_get([[(function()
    local em = require('earmark')
    local l = em.label({ set = 'review', label = 'acc' })
    l.name = 'hacked'; l.tags[1] = 'hacked'
    return {
      vivid = em.label({ set = 'vivid', label = 3 }),
      review = em.label({ set = 'review', label = 'acc', choice = 'b' }),
      unknown = em.label({ set = 'nope', label = '1' }) == nil,
      unknown_key = em.label({ set = 'vivid', label = '999' }) == nil,
      bad = { em.label(nil), em.label('x'), em.label({ set = 'vivid' }) },
      color = require('earmark.sets').color({ set = 'vivid', label = '3' }),
    }
  end)()]])
  eq(r.vivid, { set = 'vivid', key = '3', name = '3', color = r.color })
  eq(r.review, { set = 'review', key = 'acc', name = 'Accuracy', color = '#e06c75', desc = 'is it right?', tags = { 'check' } })
  eq({ r.unknown, r.unknown_key, r.bad }, { true, true, {} })
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

T['events'] = MiniTest.new_set()

T['events']['one Changed and one specific event per API change, with the real buffer'] = function()
  h.open()
  local b = bufnr()
  record()
  local id = mark({ 0, 4 }, { 0, 9 })
  local function ev(action, ids)
    local name = 'Earmark' .. action:sub(1, 1):upper() .. action:sub(2)
    return {
      { name = 'EarmarkChanged', buf = b, action = action, ids = ids },
      { name = name, buf = b, action = action, ids = ids },
    }
  end
  eq(events(), ev('add', { id }))
  child.lua('require("earmark").set_note(0, ..., "n")', { id })
  eq(events(), ev('note', { id }))
  child.lua('require("earmark").set_note(0, ..., nil)', { id })
  eq(events(), ev('note', { id }))
  child.lua('require("earmark").set_tags(0, ..., { "t" })', { id })
  eq(events(), ev('update', { id }))
  child.lua('require("earmark").set_values(0, ..., { { set = "vivid", label = "5" } })', { id })
  eq(events(), ev('update', { id }))
  child.lua('require("earmark").rename_label(0, { set = "vivid", label = "5" }, "Five")')
  eq(events(), ev('update', nil))
  child.lua('require("earmark").erase(0, { ... })', { id })
  eq(events(), ev('erase', { id }))
  child.lua('require("earmark").restore(0)')
  eq(events(), ev('restore', { id }))
  -- reading fires nothing
  child.lua([[local em = require('earmark'); em.list(0); em.at(0); em.get(0, 'x'); em.names(0); em.export(0)
    em.display_name(0, { set = 'vivid', label = '3' }); em.label({ set = 'vivid', label = '3' }); em.statusline()]])
  eq(events(), {})
end

T['events']['user actions: operator, line, erase, clear, restore'] = function()
  h.open()
  local b = bufnr()
  record()
  local function names()
    return vim.tbl_map(function(e)
      eq(e.buf, b)
      return e.name .. ':' .. (e.ids and #e.ids or '-')
    end, events())
  end
  h.cursor(1, 5)
  child.type_keys('3gh', 'iw')
  eq(names(), { 'EarmarkChanged:1', 'EarmarkAdd:1' })
  h.cursor(2, 0)
  child.type_keys('4ghh')
  eq(names(), { 'EarmarkChanged:1', 'EarmarkAdd:1' })
  h.cursor(1, 5)
  child.type_keys(' mx')
  eq(names(), { 'EarmarkChanged:1', 'EarmarkErase:1' })
  child.type_keys(' mu')
  eq(names(), { 'EarmarkChanged:1', 'EarmarkRestore:1' })
  child.type_keys(' mX')
  eq(names(), { 'EarmarkChanged:2', 'EarmarkErase:2' })
end

T['events']['opening a file with annotations fires Load with the real buffer'] = function()
  local path = h.open()
  mark({ 0, 4 }, { 0, 9 })
  child.cmd('write')
  child.cmd('enew')
  child.cmd('bwipeout! ' .. child.lua_get('vim.fn.bufnr(...)', { path }))
  record()
  child.cmd('edit ' .. path)
  eq(events(), {
    { name = 'EarmarkChanged', buf = bufnr(), action = 'load' },
    { name = 'EarmarkLoad', buf = bufnr(), action = 'load' },
  })
  -- a file with no record fires nothing
  h.open({ 'fresh' }, 'fresh.md')
  eq(events(), {})
end

T['events']['an edit that detaches or brings back an annotation fires Repair'] = function()
  h.open()
  local id = mark({ 2, 0 }, { 2, 5 })
  record()
  child.type_keys('G', 'dd')
  h.settle(100)
  eq(events(), {
    { name = 'EarmarkChanged', buf = bufnr(), action = 'repair' },
    { name = 'EarmarkRepair', buf = bufnr(), action = 'repair' },
  })
  eq(child.lua_get('require("earmark").get(0, ...).status', { id }), 'detached')
  child.type_keys('u')
  h.settle(100)
  eq(vim.tbl_map(function(e) return e.name end, events()), { 'EarmarkChanged', 'EarmarkRepair' })
  eq(child.lua_get('require("earmark").get(0, ...).status', { id }), 'ok')
  -- moving it (a line above) fires nothing: positions are read when asked
  child.type_keys('gg', 'O', 'new line', '<Esc>')
  h.settle(100)
  eq(events(), {})
  eq(child.lua_get('require("earmark").list(0)[1].s'), { 3, 0 })
end

T['events']['an edit that makes an annotation stale fires Repair'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  record()
  child.api.nvim_buf_set_text(0, 0, 5, 0, 9, { 'XXXX' })
  h.settle(100)
  eq(child.lua_get('require("earmark").get(0, ...).status', { id }), 'stale')
  eq(vim.tbl_map(function(e) return e.name end, events()), { 'EarmarkChanged', 'EarmarkRepair' })
  -- typing more inside it, still stale: nothing new
  child.api.nvim_buf_set_text(0, 0, 5, 0, 5, { 'Y' })
  h.settle(100)
  eq(events(), {})
end

T['events']['calling the API from inside a handler'] = function()
  h.open()
  record()
  child.lua([[
    local em = require('earmark')
    em.on('Add', function(d) em.set_note(d.buf, d.ids[1], 'from handler') end)
    -- would loop forever if setting the same note fired again
    em.on('Changed', function(d)
      if d.ids and d.action ~= 'erase' then em.set_note(d.buf, d.ids[1], 'from handler') end
    end)
  ]])
  local id = mark({ 0, 4 }, { 0, 9 })
  eq(child.lua_get('require("earmark").get(0, ...).note', { id }), 'from handler')
  local names = vim.tbl_map(function(e) return e.name .. ':' .. e.action end, events())
  eq(names, { 'EarmarkChanged:add', 'EarmarkChanged:note', 'EarmarkNote:note', 'EarmarkAdd:add' })
  eq(errors(), {})
end

T['events']['a handler that changes something on every change cannot hang or corrupt'] = function()
  h.open()
  child.lua([[
    local em = require('earmark')
    _G.n = 0
    em.on('Changed', function(d)
      if d.ids and d.action ~= 'erase' then _G.n = _G.n + 1; em.set_tags(d.buf, d.ids[1], { 't' .. _G.n }) end
    end)
  ]])
  local id = mark({ 0, 4 }, { 0, 9 })
  eq(child.lua_get('#require("earmark").list(0)'), 1)
  eq(child.lua_get('#require("earmark").get(0, ...).tags', { id }), 1)
  -- Neovim's autocmd nesting limit ends it
  eq(child.lua_get('_G.n') < 50, true)
  record()
  child.lua('require("earmark").set_note(0, ..., "still works")', { id })
  eq(#events() > 0, true)
end

T['events']['an erroring handler does not stop other handlers or earmark'] = function()
  h.open()
  child.lua([[
    local em = require('earmark')
    _G.seen = {}
    em.on('Add', function() error('boom') end)
    em.on('Add', function(d) table.insert(_G.seen, 'add2') end)
    vim.api.nvim_create_autocmd('User', { pattern = 'EarmarkChanged', callback = function() error('boom2') end })
    em.on('Changed', function(d) table.insert(_G.seen, 'changed:' .. d.action) end)
  ]])
  local id = mark({ 0, 4 }, { 0, 9 })
  eq(id ~= nil, true)
  eq(child.lua_get('_G.seen'), { 'changed:add', 'add2' })
  eq(h.ids(), { id })
  child.lua('_G.seen = {}')
  child.lua('require("earmark").set_note(0, ..., "n")', { id })
  eq(child.lua_get('_G.seen'), { 'changed:note' })
  eq(child.lua_get('require("earmark").get(0, ...).note', { id }), 'n')
end

T['events']['a handler erasing what was just added, or changing the event data'] = function()
  h.open()
  child.lua([[
    local em = require('earmark')
    _G.seen = {}
    em.on('Add', function(d) em.erase(d.buf, d.ids) end)
    em.on('Changed', function(d) if d.ids then table.insert(_G.seen, #d.ids); d.ids[1] = nil; d.buf = 0 end end)
    em.on('Erase', function(d) table.insert(_G.seen, d.ids[1] ~= nil and d.buf ~= 0) end)
  ]])
  local id = mark({ 0, 4 }, { 0, 9 })
  eq(id ~= nil, true)
  eq(child.lua_get('_G.seen'), { 1, 1, true })
  eq(h.ids(), {})
  eq(child.lua_get('require("earmark").get(0, ...) == nil', { id }), true)
  eq(child.lua_get('{ require("earmark").restore(0) }'), { 1, 0 })
  eq(h.ids(), { id })
end

T['events']['notes, tags and values can be set on a detached annotation'] = function()
  h.open()
  local id = mark({ 2, 0 }, { 2, 5 })
  child.api.nvim_buf_set_lines(0, 2, 3, false, {})
  child.lua('require("earmark.buffer").on_change(0)')
  record()
  child.lua([[local em, id = require('earmark'), ...
    em.set_note(0, id, 'n'); em.set_tags(0, id, { 't' }); em.set_values(0, id, { { set = 'vivid', label = '5' } })]], { id })
  eq(vim.tbl_map(function(e) return e.name end, events()),
    { 'EarmarkChanged', 'EarmarkNote', 'EarmarkChanged', 'EarmarkUpdate', 'EarmarkChanged', 'EarmarkUpdate' })
  local a = child.lua_get('require("earmark").get(0, ...)', { id })
  eq({ a.note, a.tags, a.values[1].label, a.status }, { 'n', { 't' }, '5', 'detached' })
end

T['events']['on() accepts short and full names and returns the autocmd id'] = function()
  h.open()
  child.lua([[
    local em = require('earmark')
    _G.seen = {}
    _G.au = em.on('note', function(d) table.insert(_G.seen, 'short') end)
    em.on('EarmarkNote', function(d) table.insert(_G.seen, 'full') end)
  ]])
  eq(child.lua_get('type(_G.au)'), 'number')
  local id = mark({ 0, 4 }, { 0, 9 })
  child.lua('require("earmark").set_note(0, ..., "n")', { id })
  eq(child.lua_get('_G.seen'), { 'short', 'full' })
  child.lua('vim.api.nvim_del_autocmd(_G.au); _G.seen = {}')
  child.lua('require("earmark").set_note(0, ..., "m")', { id })
  eq(child.lua_get('_G.seen'), { 'full' })
end

T['events']['nothing fires while a buffer unloads, and the API stays safe there'] = function()
  local path = h.open()
  local b = bufnr()
  mark({ 2, 0 }, { 2, 5 })
  child.lua([[
    local em, b = require('earmark'), ...
    _G.during = {}
    for _, ev in ipairs({ 'BufUnload', 'BufWipeout' }) do
      vim.api.nvim_create_autocmd(ev, { buffer = b, callback = function()
        table.insert(_G.during, { ev, #em.list(b), #em.at(b, { 2, 1 }), em.get(b, 'x') == nil })
      end })
    end
  ]], { b })
  record()
  -- an edit that will detach it, then the buffer goes before the debounce runs
  child.api.nvim_buf_set_lines(b, 2, 3, false, {})
  child.cmd('enew')
  child.cmd('bwipeout! ' .. b)
  h.settle(100)
  eq(events(), {})
  eq(child.lua_get('_G.during'), { { 'BufUnload', 0, 0, true }, { 'BufWipeout', 0, 0, true } })
  eq(child.lua_get('require("earmark.buffer").state[...] == nil', { b }), true)
  eq(errors(), {})
  eq(path ~= nil, true)
end

return T
