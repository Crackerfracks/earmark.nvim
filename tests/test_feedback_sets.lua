local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child, [[{ prompt = { ask_name = 'never', confirm_stack = false }, sets_dir = false }]])

--- Write `tbl` as JSON to `rel` under the project root.
local function write(rel, tbl)
  child.lua([[
    local path = _G.root .. '/' .. select(1, ...)
    vim.fn.mkdir(vim.fs.dirname(path), 'p')
    vim.fn.writefile({ vim.json.encode(select(2, ...)) }, path)
  ]], { rel, tbl })
end

local function current()
  return child.lua_get('require("earmark.sets").current')
end

local function list()
  return child.lua_get('require("earmark.sets").list()')
end

local function first_value()
  return child.lua_get('require("earmark").list(0)[1].annotation.values[1]')
end

local CHOICES = {
  extends = 'feedback',
  labels = {
    { key = 'a', name = 'Option A', tags = { 'option-a' } },
    { key = 'b', name = 'Option B', tags = { 'option-b' } },
  },
  tags = { 'pick' },
}

T['feedback ships with earmark: keys 1-9 with names'] = function()
  h.open()
  local names = child.lua_get([[vim.tbl_map(function(l) return l.key .. ' ' .. l.name end,
    require('earmark.sets').by_name.feedback.labels)]])
  eq(names, { '1 Keep', '2 Change', '3 Wrong', '4 Question', '5 Unclear', '6 Cut', '7 Idea', '8 Prefer', '9 Later' })
  child.lua('require("earmark").use_set("feedback")')
  h.cursor(1, 4)
  child.type_keys('2ghiw')
  eq(first_value(), { set = 'feedback', label = '2' })
  eq(child.lua_get('require("earmark.buffer").display_name(0, { set = "feedback", label = "2" })'), 'Change')
end

T['a set next to a file is used there and only there'] = function()
  write('notes/plan.earmark-set.json', CHOICES)
  local general = current()
  h.open(nil, 'notes/plan.md')
  eq(current(), 'plan')
  eq(list()[1], 'plan')
  child.type_keys('gg0', 'ghiw', 'a', '<CR>')
  eq(first_value(), { set = 'plan', label = 'a' })
  -- another file in the same folder: not offered, and the general set comes back
  h.open(nil, 'notes/other.md')
  eq(current(), general)
  eq(vim.tbl_contains(list(), 'plan'), false)
  -- the file's own annotations still draw in their colour (the set stays loaded)
  child.cmd('buffer ' .. child.fn.bufnr('plan.md'))
  eq(current(), 'plan')
  eq(child.lua_get('require("earmark.sets").by_name.plan ~= nil'), true)
end

T['extends: the base labels first, then its own; same key replaces'] = function()
  write('notes/plan.earmark-set.json', {
    extends = 'feedback',
    labels = { { key = '8', name = 'Pick this one' }, { key = 'a', name = 'Option A' } },
  })
  h.open(nil, 'notes/plan.md')
  local names = child.lua_get([[vim.tbl_map(function(l) return l.key .. ' ' .. l.name end,
    require('earmark.sets').by_name.plan.labels)]])
  eq(names[1], '1 Keep')
  eq(names[8], '8 Pick this one')
  eq(names[10], 'a Option A')
  eq(#names, 10)
  -- the base set's suggested tags carry over
  eq(child.lua_get('require("earmark.sets").by_name.plan.tags'), { 'todo', 'blocker', 'nit' })
end

T['a label with tags adds them to the annotation'] = function()
  write('notes/plan.earmark-set.json', CHOICES)
  h.open(nil, 'notes/plan.md')
  child.type_keys('gg0', 'ghiw', 'b', '<CR>')
  eq(child.lua_get('require("earmark").list(0)[1].annotation.tags'), { 'option-b' })
  -- adding the label again on the same text doesn't add the tag twice
  child.type_keys('ghiw', 'b', '<CR>')
  eq(child.lua_get('require("earmark").list(0)[1].annotation.tags'), { 'option-b' })
end

T['the set\'s tags come first in <leader>mt'] = function()
  write('notes/plan.earmark-set.json', CHOICES)
  h.open(nil, 'notes/plan.md')
  child.type_keys('gg0', 'ghiw', 'a', '<CR>')
  child.lua([[
    vim.ui.select = function(items, opts, cb)
      _G.items = vim.tbl_map(function(it) return opts.format_item(it) end, items)
    end
  ]])
  child.type_keys(' mt')
  h.settle()
  local items = child.lua_get('_G.items')
  local text = table.concat(items, '\n')
  eq(text:find('option%-a') ~= nil, true)
  eq(text:find('pick', 1, true) ~= nil, true)
end

T['a set for one file never replaces a general set of the same name'] = function()
  write('notes/plan.earmark-set.json', vim.tbl_extend('force', CHOICES, { name = 'feedback' }))
  h.open(nil, 'notes/plan.md')
  eq(child.lua_get('require("earmark.sets").by_name.feedback.labels[1].name'), 'Keep')
  eq(child.lua_get('require("earmark.sets").by_name.feedback.files'), vim.NIL)
  eq(current(), 'feedback (plan)')
end

T['files: globs relative to the set file\'s folder'] = function()
  write('review/round1.earmark-set.json', vim.tbl_extend('force', CHOICES, { files = { 'drafts/*.md' } }))
  h.open(nil, 'review/drafts/one.md')
  eq(current(), 'round1')
  h.open(nil, 'review/round1.md') -- the default (round1.*) no longer applies
  eq(vim.tbl_contains(list(), 'round1'), false)
end

T['a folder name with glob characters still matches'] = function()
  write('[draft] {v2}/plan.earmark-set.json', CHOICES)
  h.open(nil, '[draft] {v2}/plan.md')
  eq(current(), 'plan')
end

T['an expired set is not offered but still draws'] = function()
  write('notes/plan.earmark-set.json', vim.tbl_extend('force', CHOICES, { expires = '2000-01-01' }))
  local general = current()
  h.open(nil, 'notes/plan.md')
  eq(current(), general)
  eq(vim.tbl_contains(list(), 'plan'), false)
  eq(child.lua_get('require("earmark.sets").by_name.plan ~= nil'), true)
end

T['auto = false: offered first, but not switched to'] = function()
  write('notes/plan.earmark-set.json', vim.tbl_extend('force', CHOICES, { auto = false }))
  local general = current()
  h.open(nil, 'notes/plan.md')
  eq(current(), general)
  eq(list()[1], 'plan')
end

T['a set file added while Neovim runs is picked up'] = function()
  write('notes/other.earmark-set.json', CHOICES) -- makes the folder a watched one
  h.open(nil, 'notes/plan.md')
  write('notes/plan.earmark-set.json', CHOICES)
  child.cmd('doautocmd FocusGained')
  eq(current(), 'plan')
end

T['cycling sets elsewhere never lands on a file\'s set'] = function()
  write('notes/plan.earmark-set.json', CHOICES)
  h.open(nil, 'notes/plan.md')
  h.open(nil, 'notes/other.md')
  local seen = {}
  for _ = 1, 10 do
    seen[child.lua_get('require("earmark.sets").cycle(1)')] = true
  end
  eq(seen.plan, nil)
end

T['a set picked by hand in that file stays while you are in it'] = function()
  write('notes/plan.earmark-set.json', CHOICES)
  h.open(nil, 'notes/plan.md')
  child.lua('require("earmark").use_set("vivid")')
  child.cmd('doautocmd BufEnter')
  eq(current(), 'vivid')
  -- leaving and coming back offers the file's set again
  h.open(nil, 'notes/other.md')
  child.cmd('buffer ' .. child.fn.bufnr('plan.md'))
  eq(current(), 'plan')
end

T['a broken set file is reported, the rest still load'] = function()
  child.lua([[
    local dir = _G.root .. '/notes'
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile({ '{ not json' }, dir .. '/bad.earmark-set.json')
  ]])
  write('notes/plan.earmark-set.json', CHOICES)
  h.open(nil, 'notes/plan.md')
  eq(current(), 'plan')
  eq(child.lua_get('vim.tbl_count(require("earmark.sets").errors)'), 1)
end

T['extends an unknown set: reported, the set keeps its own labels'] = function()
  write('notes/plan.earmark-set.json', { extends = 'nope', labels = { { key = 'a', name = 'A' } } })
  h.open(nil, 'notes/plan.md')
  eq(child.lua_get('#require("earmark.sets").by_name.plan.labels'), 1)
  eq(child.lua_get('vim.tbl_count(require("earmark.sets").errors)'), 1)
end

return T
