local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child)

local function mark(s, e, label)
  return child.lua_get('require("earmark").annotate(0, ...).id', { s, e, { set = 'vivid', label = label or '3' } })
end

local function note(id, text)
  child.lua('require("earmark.buffer").set_note(0, ...)', { id, text })
end

local function items(row)
  return child.lua_get(
    [[(function(row)
      local it = require('earmark.render').eol_items(0, row)
      if not it then return vim.NIL end
      local t = {}
      for _, c in ipairs(it.chunks) do t[#t + 1] = c[1] end
      return { text = table.concat(t), groups = vim.tbl_map(function(c) return c[2] end, it.chunks) }
    end)(...)]],
    { row }
  )
end

local function shot()
  child.cmd('redraw!')
  child.lua('vim.wait(30, function() return false end)')
  child.cmd('redraw!')
  return child.get_screenshot()
end

local function row_text(s, r)
  return table.concat(s.text[r])
end

local function virt_lines()
  return child.lua_get([[vim.tbl_map(function(m)
    local t = {}
    for _, c in ipairs(m[4].virt_lines[1]) do t[#t + 1] = c[1] end
    return { row = m[2], text = table.concat(t) }
  end, vim.api.nvim_buf_get_extmarks(0, require('earmark.render').ns_lines, 0, -1, { details = true }))]])
end

T['a note shows a pencil and its tags at the end of the line, in the label colour'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  note(id, 'wrong #a #b')
  local it = items(0)
  eq(it.text, '✎ #a #b')
  local hex = child.lua_get('require("earmark.sets").color({ set = "vivid", label = "3" })')
  eq(it.groups[1], child.lua_get('require("earmark.sets").fg_group(...)', { hex }))
  local d = child.lua_get('vim.api.nvim_get_hl(0, { name = ... })', { it.groups[1] })
  eq(d.bg, nil) -- foreground only
  eq(row_text(shot(), 1):find('dog. ✎ #a #b', 1, true) ~= nil, true)
end

T['no note, no tags: nothing'] = function()
  h.open()
  mark({ 0, 4 }, { 0, 9 })
  eq(items(0), vim.NIL)
end

T['several notes on a line: pencils, then +N after three'] = function()
  h.open()
  for i = 0, 3 do
    note(mark({ 0, i * 10 }, { 0, i * 10 + 3 }, tostring(i + 1)), 'n' .. i)
  end
  eq(items(0).text, '✎✎✎ +1')
end

T['explicit tags and identifiers, deduplicated per line'] = function()
  h.open()
  local a = mark({ 0, 0 }, { 0, 3 }, '1')
  local b = mark({ 0, 4 }, { 0, 9 }, '2')
  note(a, 'model @A #x')
  note(b, '@B #x')
  child.lua('require("earmark.buffer").set_tags(0, ..., { "y" })', { b })
  eq(items(0).text, '✎✎ #x #y [A][B]')
end

T['indicators go on the line where the annotation ends'] = function()
  h.open()
  note(mark({ 0, 30 }, { 1, 5 }), 'spans two lines')
  eq(items(0), vim.NIL)
  eq(items(1).text, '✎')
end

T['a line too long for them gets a virtual line below'] = function()
  local long = string.rep('word ', 19) .. 'end' -- 98 columns in a 100-column window
  h.open({ long, 'next line' })
  local id = mark({ 0, 10 }, { 0, 14 })
  note(id, 'tagged #longtag #another')
  local s = shot()
  eq(virt_lines(), { { row = 0, text = string.rep(' ', 10) .. '✎ #longtag #another' } })
  eq(row_text(s, 3):sub(1, 9), 'next line') -- pushed down one row
  -- shorten the line: back to the end of the line, virtual line gone
  child.api.nvim_buf_set_lines(0, 0, 1, false, { 'short ' .. 'word' })
  h.settle(250)
  child.lua('require("earmark.buffer").on_change(0)')
  s = shot()
  eq(virt_lines(), {})
end

T['<leader>mv toggles indicators without touching the record'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  note(id, 'n #t')
  child.lua('require("earmark.buffer").save(0)')
  local path = child.lua_get('_G.root .. "/.earmark/docs/notes/doc.md.json"')
  local before = child.fn.readfile(path)
  eq(row_text(shot(), 1):find('✎ #t', 1, true) ~= nil, true)
  child.type_keys(' mv')
  eq(child.lua_get('require("earmark.config").options.indicators.mode'), 'none')
  eq(row_text(shot(), 1):find('✎', 1, true), nil)
  child.type_keys(' mv')
  eq(row_text(shot(), 1):find('✎ #t', 1, true) ~= nil, true)
  child.lua('require("earmark.buffer").save(0)')
  eq(child.fn.readfile(path), before)
  eq(#child.lua_get('require("earmark").list(0)'), 1)
end

T['the tag list adds and removes explicit tags and remembers them'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  note(id, 'about #fromnote')
  -- stub vim.ui.select / input: pick "new", type "fresh", then "done"
  child.lua([[
    _G.script = { 'new', 'done' }
    _G.seen = {}
    vim.ui.select = function(items, opts, cb)
      local want = table.remove(_G.script, 1)
      local labels = vim.tbl_map(opts.format_item, items)
      table.insert(_G.seen, labels)
      for _, it in ipairs(items) do
        if it.kind == want or it.name == want then return cb(it) end
      end
      cb(nil)
    end
    vim.ui.input = function(opts, cb) cb('#fresh') end
  ]])
  h.cursor(1, 6)
  child.type_keys(' mt')
  h.settle(100)
  eq(child.lua_get('require("earmark.buffer").annotation(0, ...).tags', { id }), { 'fresh' })
  local last = child.lua_get('_G.seen[#_G.seen]')
  eq(vim.tbl_contains(last, '✓ #fresh  (1)'), true)
  eq(vim.tbl_contains(last, '✎ #fromnote  (1)'), true)
  eq(child.lua_get('require("earmark.tags").known()')[1].count, 1)
  -- remove it again; a note tag can't be removed here
  child.lua([[_G.script = { 'fresh', 'fromnote', 'done' }
    _G.msgs = {}
    vim.notify = function(m) table.insert(_G.msgs, m) end]])
  child.type_keys(' mt')
  h.settle(100)
  eq(child.lua_get('require("earmark.buffer").annotation(0, ...).tags or vim.NIL', { id }), vim.NIL)
  eq(child.lua_get('_G.msgs')[1], 'earmark: "#fromnote" comes from the note text; edit the note to remove it')
end

T['nothing is ever put in the sign column'] = function()
  local files = vim.fn.globpath('lua', '**/*.lua', false, true)
  for _, f in ipairs(files) do
    local text = table.concat(vim.fn.readfile(f), '\n')
    eq({ f, text:find('sign_text', 1, true) }, { f, nil })
  end
end

return T
