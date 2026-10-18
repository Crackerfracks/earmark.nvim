local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child, "{ picker = 'select' }")

local function mark(s, e, label)
  return child.lua_get('require("earmark").annotate(0, ...).id', { s, e, { set = 'vivid', label = label or '3' } })
end

local function cur()
  return child.api.nvim_win_get_cursor(0)
end

-- vim.ui.select stub: records what was offered, picks the item whose text contains `want`
local function stub_select()
  child.lua([[
    _G.offered = {}
    _G.want = {}
    vim.ui.select = function(items, opts, cb)
      local labels = vim.tbl_map(function(it) return opts.format_item and opts.format_item(it) or tostring(it) end, items)
      table.insert(_G.offered, labels)
      local w = table.remove(_G.want, 1)
      for i, l in ipairs(labels) do
        if w and l:find(w, 1, true) then return cb(items[i]) end
      end
      cb(nil)
    end
    _G.msgs = {}
    vim.notify = function(m) table.insert(_G.msgs, m) end
  ]])
end

local function want(...)
  child.lua('_G.want = { ... }', { ... })
end

local function offered(n)
  return child.lua_get('_G.offered[' .. (n or '#_G.offered') .. ']')
end

T['<leader>mp lists this file and jumps to the choice'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 }, '1')
  local id = mark({ 1, 2 }, { 1, 8 }, '2')
  child.lua('require("earmark.buffer").set_note(0, ..., "check #todo")', { id })
  stub_select()
  want('second')
  h.cursor(1, 0)
  child.type_keys(' mp')
  local list = offered()
  eq(#list, 2)
  eq(list[1], '1:5  1  "quick"')
  eq(list[2], '2:3  2  "second"  #todo  ✎ check #todo')
  eq(cur(), { 2, 2 })
end

T['the query grammar narrows the list'] = function()
  h.open()
  local a = mark({ 0, 4 }, { 0, 9 }, '1')
  local b = mark({ 1, 2 }, { 1, 8 }, '2')
  mark({ 2, 0 }, { 2, 5 }, '1')
  child.lua('require("earmark.buffer").set_note(0, ..., "has #todo and @A")', { a })
  child.lua('require("earmark.buffer").set_tags(0, ..., { "todo" })', { b })
  local function n(q)
    return child.lua_get('#require("earmark.ui.picker").filter(require("earmark.ui.picker").doc_items(0), ...)', { q })
  end
  eq(n(''), 3)
  eq(n('#todo'), 2)
  eq(n('#todo label:1'), 1)
  eq(n('@a'), 1)
  eq(n('has:note'), 1)
  eq(n('set:vivid label:1'), 2)
  eq(n('third'), 1)
  eq(n('status:stale'), 0)
  eq(n('#nope'), 0)
end

T[':Earmark pick takes a query'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 }, '1')
  mark({ 1, 2 }, { 1, 8 }, '2')
  stub_select()
  child.cmd('Earmark pick label:2')
  eq(#offered(), 1)
end

T['<leader>mP lists every document in the project'] = function()
  h.open({ 'alpha beta gamma' }, 'a.md')
  mark({ 0, 6 }, { 0, 10 }, '1')
  child.lua('require("earmark.buffer").save(0)')
  h.open({ 'one two three' }, 'sub/b.md')
  mark({ 0, 4 }, { 0, 7 }, '2')
  child.cmd('bwipe! ' .. child.lua_get('vim.fn.bufnr(_G.root .. "/a.md")'))
  stub_select()
  want('a.md')
  child.type_keys(' mP')
  local list = offered()
  eq(#list, 2)
  eq(list[1]:sub(1, 9), 'a.md:1:7 ')
  eq(list[2]:sub(1, 13), 'sub/b.md:1:5 ')
  eq(child.api.nvim_buf_get_name(0):sub(-4), 'a.md')
  eq(cur(), { 1, 6 })
end

T['the review list re-attaches a detached annotation to a selection'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 }, '1') -- "quick"
  h.cursor(1, 4)
  child.type_keys('dw')
  child.lua('require("earmark.buffer").on_change(0)')
  eq(child.lua_get('require("earmark.buffer").annotation(0, ...).status', { id }), 'detached')
  stub_select()
  want('quick', 'Attach')
  child.type_keys(' md')
  eq(#offered(1), 1)
  eq(child.lua_get('_G.msgs[#_G.msgs]'), 'earmark: select the text it belongs to, then run :Earmark reanchor')
  child.type_keys('v', 'e', ':Earmark reanchor<CR>') -- select "brown"
  local a = child.lua_get('require("earmark.buffer").annotation(0, ...)', { id })
  eq(a.status, 'stale') -- "brown" is not "quick"
  eq(child.lua_get('_G.texts()'), { { text = 'brown', label = '1', status = 'stale' } })
end

T['accepting the current text clears stale'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 }, '1')
  h.cursor(1, 4)
  child.type_keys('ciw', 'speedy', '<Esc>')
  child.lua('require("earmark.buffer").on_change(0)')
  eq(child.lua_get('require("earmark.buffer").annotation(0, ...).status', { id }), 'stale')
  stub_select()
  want('speedy', 'Accept')
  child.type_keys(' md')
  local a = child.lua_get('require("earmark.buffer").annotation(0, ...)', { id })
  eq({ a.status, a.original_quote }, { 'ok', 'speedy' })
end

T['nothing to review'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 }, '1')
  stub_select()
  child.type_keys(' md')
  eq(child.lua_get('_G.msgs[1]'), 'earmark: nothing to review: every annotation is attached to its text')
end

T['the diff float marks what changed'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 19 }, '1') -- "quick brown fox"
  h.cursor(1, 10)
  child.type_keys('ciw', 'red', '<Esc>')
  child.lua('require("earmark.buffer").on_change(0)')
  h.cursor(1, 5)
  child.type_keys(' mD')
  local fl = h.floats()
  eq(#fl, 1)
  eq(fl[1].lines, { 'originally', 'quick brown fox', 'now', 'quick red fox' })
  local d = child.lua_get('require("earmark.ui.review").char_diff("quick brown fox", "quick red fox")')
  eq(d.a[1][1] >= 6 and d.a[#d.a][2] <= 11, true)
  eq(d.b[1][1] >= 6 and d.b[#d.b][2] <= 9, true)
  child.type_keys('q')
  eq(#h.floats(), 0)
end

T[':Earmark qf fills the quickfix list'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 }, '1')
  mark({ 1, 2 }, { 1, 8 }, '2')
  child.cmd('Earmark qf')
  local qf = child.fn.getqflist({ items = 1, title = 1 })
  eq(qf.title, 'earmark')
  eq(#qf.items, 2)
  eq({ qf.items[1].lnum, qf.items[1].col, qf.items[1].end_col }, { 1, 5, 10 })
  eq(qf.items[1].text, '1  "quick"')
  eq(qf.items[1].user_data, { earmark = id })
end

T[':Earmark scratch reopens a scratch buffer with its annotations'] = function()
  child.cmd('enew')
  child.api.nvim_buf_set_lines(0, 0, -1, false, { 'scratch text here', 'more' })
  child.lua('require("earmark.buffer").get(0)')
  mark({ 0, 8 }, { 0, 12 }, '4')
  child.lua('require("earmark.buffer").save(0)')
  child.cmd('bwipe!')
  stub_select()
  want('scratch text')
  child.cmd('Earmark scratch')
  eq(child.api.nvim_buf_get_lines(0, 0, -1, false), { 'scratch text here', 'more' })
  eq(child.lua_get('_G.texts()'), { { text = 'text', label = '4', status = 'ok' } })
end

T['a broken backend falls back to vim.ui.select'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 }, '1')
  stub_select()
  child.lua([[
    require('earmark.config').options.picker = 'snacks'
    require('earmark.ui.picker').backends.snacks = function() error('api drift') end
  ]])
  child.type_keys(' mp')
  eq(#offered(), 1)
end

return T
