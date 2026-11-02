-- A Visual-block selection is one annotation to work with: one row each in the text, one
-- label, one note and one set of tags (on the first row), erased and restored together,
-- and one entry in the picker and the export.
local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child, "{ prompt = { ask_name = 'never' } }")

local LINES = { 'alpha beta gamma', 'delta epsil zeta', 'theta iota kappa', 'lambda mu nu' }

local function block()
  h.open(LINES)
  h.cursor(1, 6)
  child.type_keys('<C-v>', '2j', '3l', '5gh')
  h.settle()
end

local function rows()
  return child.lua_get([[vim.tbl_map(function(x)
    local a = x.annotation
    return { text = vim.api.nvim_buf_get_text(0, x.s[1], x.s[2], x.e[1], x.e[2], {})[1], label = a.values[1].label,
      note = a.note or '', tags = table.concat(a.tags or {}, ','), lead = a.group == nil or a.group == a.id }
  end, require('earmark').list(0))]])
end

T['a block makes one annotation per row, linked as one'] = function()
  block()
  local r = rows()
  eq(vim.tbl_map(function(x) return x.text end, r), { 'beta', 'epsi', 'iota' })
  eq(vim.tbl_map(function(x) return x.label end, r), { '5', '5', '5' })
  local groups = child.lua_get('vim.tbl_map(function(x) return x.annotation.group end, require("earmark").list(0))')
  eq(groups[1] ~= nil and groups[1] == groups[2] and groups[2] == groups[3], true)
end

T['the note from any row is the block note'] = function()
  block()
  h.cursor(3, 7) -- last row
  child.type_keys(' mm', 'one note', '<Esc>', 'q')
  h.settle()
  local r = rows()
  eq(r[1].note, 'one note')
  eq(r[2].note .. r[3].note, '')
  -- opening it from the middle row shows the same note
  h.cursor(2, 7)
  child.type_keys(' mm')
  h.settle()
  eq(child.lua_get('vim.api.nvim_get_current_line()'), 'one note')
  child.type_keys('q')
  -- the hover on any row shows it
  h.cursor(3, 7)
  child.lua('require("earmark.ui.hover").show(0, require("earmark.buffer").find(0, { 2, 7 }), false)')
  local lines = child.lua_get('vim.api.nvim_buf_get_lines(require("earmark.ui.hover").shown.buf, 0, -1, false)')
  eq(vim.tbl_contains(lines, 'one note'), true)
end

T['relabel, tags and erase act on the whole block; restore brings it back'] = function()
  block()
  h.cursor(2, 7)
  child.lua('require("earmark").set_tags(0, require("earmark").at(0)[1].annotation.id, { "todo" })')
  child.lua('local id = require("earmark").at(0)[1].annotation.id; require("earmark.buffer").set_values(0, id, { { set = "vivid", label = "7" } })')
  local r = rows()
  eq(vim.tbl_map(function(x) return x.label end, r), { '7', '7', '7' })
  eq(r[1].tags, 'todo')
  h.cursor(3, 7)
  child.type_keys(' mx')
  h.settle()
  eq(#h.ids(), 0)
  child.type_keys(' mu')
  h.settle()
  eq(#h.ids(), 3)
  eq(rows()[1].tags, 'todo')
end

T['the picker and the export show a block once'] = function()
  block()
  h.cursor(1, 7)
  child.type_keys(' mm', 'block note', '<Esc>', 'q')
  h.settle()
  eq(#child.lua_get('require("earmark.ui.picker").doc_items(0)'), 1)
  local md = table.concat(child.lua_get('require("earmark").export(0)'), '\n')
  local _, quotes = md:gsub('beta', '')
  eq(quotes, 1)
  eq(md:find('epsi', 1, true) ~= nil and md:find('iota', 1, true) ~= nil, true)
  eq(select(2, md:gsub('block note', '')), 1)
end

T['the block survives a save and reload'] = function()
  block()
  h.cursor(1, 7)
  child.type_keys(' mm', 'kept', '<Esc>', 'q')
  h.settle(100)
  child.lua('require("earmark.buffer").save(0)')
  child.cmd('edit!')
  h.settle(100)
  local groups = child.lua_get('vim.tbl_map(function(x) return x.annotation.group or false end, require("earmark").list(0))')
  eq(#groups, 3)
  eq(groups[1] ~= false and groups[1] == groups[3], true)
  h.cursor(3, 7)
  child.type_keys(' mm')
  h.settle()
  eq(child.lua_get('vim.api.nvim_get_current_line()'), 'kept')
end

T['a one-row block and a charwise selection are not blocks'] = function()
  h.open(LINES)
  h.cursor(1, 6)
  child.type_keys('<C-v>', '3l', '5gh')
  h.settle()
  child.type_keys('v', 'j', '3gh')
  h.settle()
  local groups = child.lua_get('vim.tbl_map(function(x) return x.annotation.group or false end, require("earmark").list(0))')
  eq(groups, { false, false })
end

return T
