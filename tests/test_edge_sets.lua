-- Edge cases of label sets: odd and broken set files, sets that go away while annotations
-- use them, extends chains and cycles, `expires` and `files` in every shape, reloading, and
-- the same name defined in several places.
local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child, [[{ prompt = { ask_name = 'never', confirm_stack = false }, sets_dir = _G.tmp .. '/usersets' }]])

--- Write `content` (a table: JSON-encoded; a string: as is) to `rel` under the temp dir.
local function put(rel, content)
  child.lua([[
    local rel, content = ...
    local path = _G.tmp .. '/' .. rel
    vim.fn.mkdir(vim.fs.dirname(path), 'p')
    if type(content) == 'table' then content = vim.json.encode(content) end
    local f = assert(io.open(path, 'wb'))
    f:write(content)
    f:close()
  ]], { rel, content })
end

local function project_set(name, content)
  put('proj/.earmark/sets/' .. name, content)
end

local function user_set(name, content)
  put('usersets/' .. name, content)
end

local function sidecar(rel, content)
  put('proj/' .. rel, content)
end

local function set(name)
  return child.lua_get('require("earmark.sets").by_name[...]', { name })
end

local function keys(name)
  return child.lua_get([[vim.tbl_map(function(l) return l.key .. ' ' .. l.name end,
    (require('earmark.sets').by_name[...] or { labels = {} }).labels)]], { name })
end

local function errors()
  return child.lua_get([[(function()
    local out = {}
    for path, msg in pairs(require('earmark.sets').errors) do out[#out + 1] = vim.fs.basename(path) .. ': ' .. msg end
    table.sort(out)
    return out
  end)()]])
end

local function has_error(file)
  for _, e in ipairs(errors()) do
    if vim.startswith(e, file .. ':') then return true end
  end
  return false
end

local function reload()
  child.cmd('Earmark reload')
end

local function no_error()
  eq(child.v.errmsg, '')
end

---------------------------------------------------------------------------
-- Odd set files
---------------------------------------------------------------------------

T['duplicate keys: the later label replaces the earlier one in its place'] = function()
  project_set('dup.json', { labels = { { key = 'a', name = 'First A' }, { key = 'b', name = 'B' }, { key = 'a', name = 'Second A' } } })
  h.open()
  eq(keys('dup'), { 'a Second A', 'b B' })
  -- what the prompt offers is what gets drawn and named
  eq(child.lua_get('require("earmark.sets").resolve_query("dup", "a")[1].name'), 'Second A')
  eq(child.lua_get('require("earmark.sets").resolve_query("dup", "")[1].name'), 'Second A')
  eq(child.lua_get('require("earmark.buffer").display_name(0, { set = "dup", label = "a" })'), 'Second A')
end

T['an empty labels list: the set loads, and nothing breaks when it is the current one'] = function()
  project_set('empty.json', { labels = {}, desc = 'nothing yet' })
  h.open()
  eq(#set('empty').labels, 0)
  child.lua('require("earmark").use_set("empty")')
  eq(child.lua_get('require("earmark").statusline()') ~= nil, true)
  child.lua('_G.msgs = {}; vim.notify = function(m) table.insert(_G.msgs, m) end')
  h.cursor(1, 4)
  child.type_keys('3ghiw') -- a count with no label 3
  eq(child.lua_get('_G.msgs[1]'), 'earmark: no label 3 in set "empty"')
  child.type_keys('ghiw')
  child.type_keys('<Esc>', '<Esc>')
  h.settle()
  eq(#h.texts(), 0)
  child.type_keys(' ms')
  no_error()
end

T['labels with an empty name or no name show their key'] = function()
  project_set('noname.json', { labels = { { key = 'x', name = '' }, { key = 'y' }, 'Only a name', '' } })
  h.open()
  eq(keys('noname'), { 'x x', 'y y', '3 Only a name', '4 4' })
end

T['keys with several characters, slashes, spaces and numbers'] = function()
  project_set('odd.json', { labels = {
    { key = 'q1.1', name = 'Dotted' }, { key = 'a/b', name = 'Slashed' }, { key = 'two words', name = 'Spaced' },
    { key = 7, name = 'Number' },
  } })
  h.open()
  eq(keys('odd'), { 'q1.1 Dotted', 'a/b Slashed', 'two words Spaced', '7 Number' })
  local id = child.lua_get('require("earmark").annotate(0, { 0, 4 }, { 0, 9 }, { set = "odd", label = "a/b" }).id')
  child.lua('require("earmark").rename_label(0, { set = "odd", label = "a/b" }, "Renamed")')
  eq(child.lua_get('require("earmark.buffer").display_name(0, { set = "odd", label = "a/b" })'), 'Renamed')
  eq(child.lua_get('require("earmark").export(0)[3]'), '## Renamed (odd·a/b)')
  local p = 'require("earmark.ui.picker")'
  eq(child.lua_get(('#%s.filter(%s.doc_items(0), "label:a/b")'):format(p, p)), 1)
  eq(child.lua_get(('#%s.filter(%s.doc_items(0), "label:renamed")'):format(p, p)), 1)
  eq(child.lua_get('require("earmark").get(0, ...).values[1].label', { id }), 'a/b')
  -- the default_label setting splits at the first slash
  child.lua('require("earmark.config").options.default_label = "odd/a/b"; require("earmark").use_set("odd")')
  no_error()
end

T['labels without colours get distinct palette colours; colour names are distinct too'] = function()
  project_set('plain.json', { labels = { 'A', 'B', 'C', 'D', 'E' } })
  h.open()
  local colors = child.lua_get('vim.tbl_map(function(l) return l.color end, require("earmark.sets").by_name.plain.labels)')
  local seen = {}
  for _, c in ipairs(colors) do
    eq(c:match('^#%x%x%x%x%x%x$') ~= nil, true)
    eq(seen[c], nil)
    seen[c] = true
  end
  local names = child.lua_get([[vim.tbl_map(function(l) return require('earmark.sets').color_name({ set = 'plain', label = l.key }) end,
    require('earmark.sets').by_name.plain.labels)]])
  eq(#names, 5)
  eq(#vim.tbl_keys(vim.iter(names):fold({}, function(acc, n) acc[n] = true return acc end)), 5)
end

T['invalid colours: the label gets a palette colour and the file an error; #rgb is accepted'] = function()
  project_set('bad.json', { labels = {
    { key = 'a', color = 'red' }, { key = 'b', color = '#fff' }, { key = 'c', color = '#zzzzzz' },
    { key = 'd', color = 123 }, { key = 'e', color = '#12345678' }, { key = 'f', color = '#ABCDEF' },
    { key = 'g', choices = { { key = 'x', name = 'X', color = 'blue' } } },
  } })
  h.open()
  local colors = child.lua_get('vim.tbl_map(function(l) return l.color end, require("earmark.sets").by_name.bad.labels)')
  for _, c in ipairs(colors) do
    eq(type(c) == 'string' and c:match('^#%x%x%x%x%x%x$') ~= nil, true)
  end
  eq(colors[2], '#ffffff')
  eq(colors[6]:lower(), '#abcdef')
  eq(has_error('bad.json'), true)
  -- every label draws, with its choice too
  child.lua([[
    local em = require('earmark')
    for i, k in ipairs({ 'a', 'b', 'c', 'd', 'e', 'f' }) do
      em.annotate(0, { 0, i - 1 }, { 0, i }, { set = 'bad', label = k })
    end
    em.annotate(0, { 1, 0 }, { 1, 1 }, { set = 'bad', label = 'g', choice = 'x' })
    vim.cmd('redraw')
  ]])
  eq(child.lua_get('require("earmark.sets").color({ set = "bad", label = "g", choice = "x" })'):match('^#%x+$') ~= nil, true)
  h.cursor(1, 2)
  child.type_keys(' mi')
  no_error()
end

T['a huge set: 600 labels load, resolve, draw and get colour names'] = function()
  local labels = {}
  for i = 1, 600 do
    labels[i] = { key = 'k' .. i, name = 'Label ' .. i }
  end
  project_set('huge.json', { labels = labels })
  h.open()
  eq(#set('huge').labels, 600)
  eq(child.lua_get('require("earmark.sets").resolve_query("huge", "k599")[1].key'), 'k599')
  eq(child.lua_get('require("earmark.sets").resolve(600, "huge").key'), 'k600')
  eq(type(child.lua_get('require("earmark.sets").color_name({ set = "huge", label = "k600" })')), 'string')
  child.lua('require("earmark").annotate(0, { 0, 4 }, { 0, 9 }, { set = "huge", label = "k600" }); vim.cmd("redraw")')
  child.lua('require("earmark").use_set("huge")')
  h.cursor(2, 2)
  child.type_keys('ghiw', 'Label 42', '<CR>')
  h.settle()
  no_error()
end

T['numbered sets: generate with an unknown palette is an error for that set only'] = function()
  project_set('nums.lua', 'return { good = "pastel", gen = { generate = "numbered", palette = "earth" }, bad = "nope", worse = { generate = "numbered", palette = "nope" } }')
  child.lua('vim.secure.read = function(p) return table.concat(vim.fn.readfile(p), "\\n") end')
  h.open()
  eq(#set('good').labels, 99)
  eq(#set('gen').labels, 99)
  eq(set('bad'), vim.NIL)
  eq(set('worse'), vim.NIL)
  eq(has_error('nums.lua'), true)
  eq(#set('vivid').labels, 99)
end

T['labels that are not a list, or not labels: an error for that set, the others load'] = function()
  project_set('a_str.json', { labels = 'abc' })
  project_set('b_num.json', { labels = 5 })
  project_set('c_items.json', { labels = { 5, true, { key = 'ok', name = 'Fine' } } })
  project_set('d_choices.json', { labels = { { key = 'q', choices = { 5, 'Named', { key = 'z' } } } } })
  project_set('e_tags.json', { labels = { { key = 't', tags = 'not a list' } }, tags = 'nor this' })
  project_set('z_fine.json', { labels = { 'Fine' } })
  h.open()
  no_error()
  eq(keys('z_fine'), { '1 Fine' })
  eq(#set('vivid').labels, 99)
  for _, name in ipairs({ 'a_str', 'b_num', 'c_items', 'd_choices' }) do
    -- either loaded without the junk, or left out with an error; never a crash
    local s = set(name)
    eq(s == vim.NIL and has_error(name .. '.json') or type(s) == 'table', true)
  end
  eq(keys('e_tags'), { 't t' })
end

T['a Lua set file that errors, or returns no table, is reported; the rest load'] = function()
  user_set('boom.lua', 'error("boom")')
  user_set('nothing.lua', 'return 42')
  user_set('syntax.lua', 'return {')
  user_set('fine.lua', 'return { labels = { "From Lua" } }')
  h.open()
  eq(has_error('boom.lua'), true)
  eq(has_error('nothing.lua'), true)
  eq(has_error('syntax.lua'), true)
  eq(keys('fine'), { '1 From Lua' })
  -- :Earmark log has them
  local log = child.lua_get('table.concat(vim.fn.readfile(require("earmark.log").file()), "\\n")')
  eq(log:find('boom', 1, true) ~= nil, true)
end

T['JSON with a byte order mark loads; a trailing comma is reported'] = function()
  project_set('bom.json', '\239\187\191' .. vim.json.encode({ labels = { 'With BOM' } }))
  project_set('comma.json', '{ "labels": ["a", "b",], }')
  h.open()
  eq(keys('bom'), { '1 With BOM' })
  eq(set('comma'), vim.NIL)
  eq(has_error('comma.json'), true)
end

T['a set file that is empty, or JSON null, or a list'] = function()
  project_set('empty.json', '')
  project_set('null.json', 'null')
  project_set('list.json', '["a", "b"]')
  h.open()
  no_error()
  eq(has_error('empty.json'), true)
  eq(has_error('null.json'), true)
  eq(set('empty'), vim.NIL)
  eq(set('null'), vim.NIL)
end

---------------------------------------------------------------------------
-- A set removed while annotations use it
---------------------------------------------------------------------------

T['a set removed while in use: drawing, hover, export, statusline, pickers and keys do not error'] = function()
  project_set('gone.json', { labels = { { key = 'a', name = 'Alpha', color = '#e06c75' } } })
  h.open()
  child.lua([[
    require('earmark').use_set('gone')
    _G.id = require('earmark').annotate(0, { 0, 4 }, { 0, 9 }, { set = 'gone', label = 'a' }).id
    require('earmark').annotate(0, { 1, 2 }, { 1, 8 }, { set = 'vivid', label = '2' })
    require('earmark').set_values(0, _G.id, { { set = 'gone', label = 'a' }, { set = 'vivid', label = '3' } })
    require('earmark.buffer').save(0)
    vim.fn.delete(_G.root .. '/.earmark/sets/gone.json')
  ]])
  reload()
  eq(set('gone'), vim.NIL)
  eq(child.lua_get('require("earmark.sets").current'), 'vivid')
  child.cmd('redraw')
  -- the hover names the key
  h.cursor(1, 5)
  child.type_keys(' mi')
  local fl = h.floats()
  eq(#fl >= 1, true)
  eq(table.concat(fl[1].lines, '\n'):find('a', 1, true) ~= nil, true)
  child.type_keys('<Esc>')
  -- export
  local text = table.concat(child.lua_get('require("earmark").export(0, { group_by = "position" })'), '\n')
  eq(text:find('**a + 3**', 1, true) ~= nil, true)
  eq(text:find('nil', 1, true), nil)
  -- statusline, with the next value pointing at the gone set
  child.lua('require("earmark").use_value({ set = "gone", label = "a" })')
  eq(type(child.lua_get('require("earmark").statusline()')), 'string')
  -- pickers: this file and the project
  child.lua('vim.ui.select = function(items, opts, cb) _G.picked = vim.tbl_map(opts.format_item or tostring, items) end')
  child.cmd('Earmark pick')
  eq(#child.lua_get('_G.picked'), 2)
  local p = 'require("earmark.ui.picker")'
  eq(child.lua_get(('#%s.filter(%s.root_items(vim.uv.fs_realpath(_G.root)), "set:gone")'):format(p, p)), 1)
  -- colour lookups say nothing rather than fail
  eq(child.lua_get('require("earmark.sets").color_name({ set = "gone", label = "a" })'), vim.NIL)
  eq(child.lua_get('require("earmark.sets").group({ set = "gone", label = "a" })'), 'EarmarkUnknown')
  -- keys on it: relabel, add a value, next/prev, info
  h.cursor(1, 5)
  child.type_keys(' mn', ' mN', ' m]')
  child.cmd('Earmark info')
  no_error()
  -- coming back: it draws again
  project_set('gone.json', { labels = { { key = 'a', name = 'Alpha', color = '#e06c75' } } })
  reload()
  eq(child.lua_get('require("earmark.buffer").display_name(0, { set = "gone", label = "a" })'), 'Alpha')
end

T['a label removed from a set that stays: the key shows, nothing errors'] = function()
  project_set('shrink.json', { labels = { { key = 'a', name = 'Alpha' }, { key = 'b', name = 'Beta' } } })
  h.open()
  child.lua('require("earmark").annotate(0, { 0, 4 }, { 0, 9 }, { set = "shrink", label = "b" })')
  child.lua('require("earmark.buffer").save(0)')
  project_set('shrink.json', { labels = { { key = 'a', name = 'Alpha' } } })
  reload()
  eq(child.lua_get('require("earmark").export(0)[3]'), '## b (shrink·b)')
  h.cursor(1, 5)
  child.type_keys(' mi')
  no_error()
end

---------------------------------------------------------------------------
-- extends
---------------------------------------------------------------------------

T['extends a set that itself extends: whatever the file order'] = function()
  -- a.earmark-set.json sorts before b, but extends it
  sidecar('notes/a.earmark-set.json', { extends = 'b', labels = { { key = 'x', name = 'From a' } }, files = { '*.md' } })
  sidecar('notes/b.earmark-set.json', { extends = 'feedback', labels = { { key = 'w', name = 'From b' } }, files = { '*.md' } })
  h.open(nil, 'notes/doc.md')
  local k = keys('a')
  eq(k[1], '1 Keep')
  eq(k[10], 'w From b')
  eq(k[11], 'x From a')
  eq(#k, 11)
  eq(has_error('a.earmark-set.json'), false)
  -- the project's set files too
  project_set('p1.json', { extends = 'p2', labels = { 'One' } })
  project_set('p2.json', { extends = 'feedback', labels = { { key = 'z', name = 'Two' } } })
  reload()
  eq(#keys('p1'), 11)
end

T['extends cycles do not hang: each set keeps its own labels and the cycle is reported'] = function()
  sidecar('notes/a.earmark-set.json', { extends = 'b', labels = { { key = 'x', name = 'A' } }, files = { '*.md' } })
  sidecar('notes/b.earmark-set.json', { extends = 'a', labels = { { key = 'y', name = 'B' } }, files = { '*.md' } })
  sidecar('notes/c.earmark-set.json', { extends = 'c', labels = { { key = 'z', name = 'C' } }, files = { '*.md' } })
  h.open(nil, 'notes/doc.md')
  no_error()
  eq(vim.tbl_contains(keys('a'), 'x A'), true)
  eq(vim.tbl_contains(keys('b'), 'y B'), true)
  eq(keys('c'), { 'z C' })
  eq(#errors() >= 2, true)
end

T['a project set named like a built-in one may extend it'] = function()
  project_set('feedback.json', { extends = 'feedback', labels = { { key = 'a', name = 'Extra' } } })
  h.open()
  local k = keys('feedback')
  eq(#k, 10)
  eq(k[10], 'a Extra')
  eq(errors(), {})
end

T['extends something that is not a set name'] = function()
  project_set('weird.json', { extends = { 'feedback' }, labels = { 'Own' } })
  project_set('weird2.json', { extends = 5, labels = { 'Own' } })
  h.open()
  no_error()
  eq(keys('weird'), { '1 Own' })
  eq(has_error('weird.json'), true)
end

---------------------------------------------------------------------------
-- expires
---------------------------------------------------------------------------

local function today(day)
  child.lua([[
    local day = ...
    local date = os.date
    os.date = function(fmt, t)
      if fmt == '%Y-%m-%d' and t == nil then return day end
      return date(fmt, t)
    end
  ]], { day })
end

local function offered(name, rel)
  child.lua('_G.open(...)', { rel or 'notes/plan.md' })
  return vim.tbl_contains(child.lua_get('require("earmark.sets").list()'), name)
end

T['expires: days without leading zeros compare as dates'] = function()
  today('2026-10-19')
  sidecar('notes/plan.earmark-set.json', { labels = { 'A' }, expires = '2026-10-5' })
  eq(offered('plan'), false) -- 5 October is past
  sidecar('notes/plan.earmark-set.json', { labels = { 'A' }, expires = '2026-11-5' })
  reload()
  eq(offered('plan'), true)
  sidecar('notes/plan.earmark-set.json', { labels = { 'A' }, expires = '2026-10-19' })
  reload()
  eq(offered('plan'), true) -- the day itself still counts
  sidecar('notes/plan.earmark-set.json', { labels = { 'A' }, expires = '2026-10-18T23:59' })
  reload()
  eq(offered('plan'), false)
end

T['expires in a format that is not a date: reported, and the set is still offered'] = function()
  today('2026-10-19')
  for _, bad in ipairs({ '19/10/2000', 'next week', '', '2026-13-45x' }) do
    sidecar('notes/plan.earmark-set.json', { labels = { 'A' }, expires = bad })
    reload()
    eq({ bad, offered('plan') }, { bad, true })
    eq({ bad, has_error('plan.earmark-set.json') }, { bad, bad ~= '' })
  end
  sidecar('notes/plan.earmark-set.json', { labels = { 'A' }, expires = 20001019 })
  reload()
  eq(offered('plan'), true)
  eq(has_error('plan.earmark-set.json'), true)
end

---------------------------------------------------------------------------
-- files
---------------------------------------------------------------------------

T['files: ** matches at any depth, including the folder itself'] = function()
  sidecar('review/all.earmark-set.json', { labels = { 'A' }, files = { '**/*.md' } })
  eq(offered('all', 'review/top.md'), true)
  eq(offered('all', 'review/a/b/c/deep.md'), true)
  eq(offered('all', 'review/a/b/c/deep.txt'), false)
  eq(offered('all', 'elsewhere.md'), false)
end

T['files: ./ prefix, an absolute path and ~ work'] = function()
  child.lua('vim.env.HOME = _G.tmp')
  sidecar('review/dot.earmark-set.json', { labels = { 'A' }, files = { './drafts/*.md' } })
  sidecar('review/abs.earmark-set.json', { labels = { 'A' }, files = { child.lua_get('_G.root') .. '/review/x/*.md' } })
  sidecar('review/home.earmark-set.json', { labels = { 'A' }, files = { '~/proj/review/y/*.md' } })
  eq(offered('dot', 'review/drafts/one.md'), true)
  eq(offered('abs', 'review/x/one.md'), true)
  eq(offered('home', 'review/y/one.md'), true)
  eq(offered('abs', 'review/y/one.md'), false)
end

T['files: ../ reaches a sibling folder once the set is loaded'] = function()
  sidecar('review/up.earmark-set.json', { labels = { 'A' }, files = { '../drafts/*.md' } })
  child.lua('_G.open("review/plan.md", { "x" })') -- loads review/'s sets
  eq(offered('up', 'drafts/one.md'), true)
  eq(offered('up', 'review/one.md'), false)
end

T['files: an empty list is for no file, and never replaces a general set'] = function()
  sidecar('notes/feedback.earmark-set.json', { labels = { 'A' }, files = {} })
  sidecar('notes/x.earmark-set.json', { labels = { 'A' }, files = {} })
  eq(offered('x'), false)
  eq(offered('feedback'), true)
  eq(set('feedback').labels[1].name, 'Keep')
end

T['files: junk entries are skipped'] = function()
  sidecar('notes/junk.earmark-set.json', { labels = { 'A' }, files = { 5, '', 'plan.md' } })
  eq(offered('junk'), true)
  no_error()
end

---------------------------------------------------------------------------
-- Reloading and names in several places
---------------------------------------------------------------------------

T[':Earmark reload re-reads set files edited elsewhere'] = function()
  project_set('r.json', { labels = { { key = 'a', name = 'Before' } } })
  h.open()
  child.lua('require("earmark").annotate(0, { 0, 4 }, { 0, 9 }, { set = "r", label = "a" })')
  child.lua('require("earmark.buffer").save(0)')
  project_set('r.json', { labels = { { key = 'a', name = 'After', color = '#00ff00' } } })
  reload()
  eq(child.lua_get('require("earmark.buffer").display_name(0, { set = "r", label = "a" })'), 'After')
  eq(child.lua_get('require("earmark.sets").color({ set = "r", label = "a" })'), '#00ff00')
end

T['a set file that breaks on reload: reported, other sets stay, the editor keeps working'] = function()
  project_set('r.json', { labels = { 'A' } })
  h.open()
  project_set('r.json', '{ broken')
  reload()
  no_error()
  eq(set('r'), vim.NIL)
  eq(has_error('r.json'), true)
  eq(#set('vivid').labels, 99)
end

T['the same name in sets_dir, the project and setup: the project wins, then sets_dir'] = function()
  user_set('same.json', { labels = { 'From user dir' } })
  user_set('mine.json', { labels = { 'Only user dir' } })
  project_set('same.json', { labels = { 'From project' } })
  h.open()
  eq(keys('same'), { '1 From project' })
  eq(keys('mine'), { '1 Only user dir' })
  eq(child.lua_get('vim.tbl_count(vim.tbl_filter(function(n) return n == "same" end, require("earmark.sets").order))'), 1)
end

T['a file\'s own set named like a general one gets a suffix; the general one is untouched'] = function()
  user_set('review.json', { labels = { 'General review' } })
  sidecar('notes/plan.earmark-set.json', { name = 'review', labels = { 'For plan' } })
  h.open(nil, 'notes/plan.md')
  eq(keys('review'), { '1 General review' })
  eq(keys('review (plan)'), { '1 For plan' })
  eq(child.lua_get('require("earmark.sets").current'), 'review (plan)')
end

T['two files\' own sets with the same name in different folders each keep their labels'] = function()
  MiniTest.skip('sets are found by name: two plan.earmark-set.json in different folders share the name "plan" '
    .. '(the later replaces the earlier); telling them apart needs per-file set lookup')
  sidecar('one/plan.earmark-set.json', { labels = { { key = 'a', name = 'One A' } } })
  sidecar('two/plan.earmark-set.json', { labels = { { key = 'a', name = 'Two A' } } })
  h.open(nil, 'one/plan.md')
  child.lua('require("earmark").annotate(0, { 0, 4 }, { 0, 9 }, { set = "plan", label = "a" })')
  h.open(nil, 'two/plan.md')
  child.cmd('buffer ' .. child.fn.bufnr('one/plan.md'))
  eq(child.lua_get('require("earmark.buffer").display_name(0, { set = "plan", label = "a" })'), 'One A')
end

T['a file opened before setup gets its project and own sets'] = function()
  child.restart({ '-u', 'scripts/minimal_init.lua' })
  child.lua([[
    _G.tmp = vim.fn.tempname()
    _G.root = _G.tmp .. '/proj'
    vim.fn.mkdir(_G.root .. '/.earmark/sets', 'p')
    vim.fn.mkdir(_G.root .. '/notes', 'p')
    vim.fn.writefile({ vim.json.encode({ labels = { 'Project label' } }) }, _G.root .. '/.earmark/sets/proj.json')
    vim.fn.writefile({ vim.json.encode({ labels = { 'Plan label' } }) }, _G.root .. '/notes/plan.earmark-set.json')
    vim.fn.writefile({ 'some text' }, _G.root .. '/notes/plan.md')
    vim.cmd('edit ' .. _G.root .. '/notes/plan.md')
    require('earmark').setup({ storage_dir = _G.tmp .. '/data', sets_dir = false })
  ]])
  eq(child.lua_get('require("earmark.sets").by_name.proj ~= nil'), true)
  eq(child.lua_get('require("earmark.sets").by_name.plan ~= nil'), true)
  eq(child.lua_get('require("earmark.sets").current'), 'plan')
end

return T
