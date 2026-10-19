-- The hover at the edges of windows (top and last line, last column, winbar, tabline,
-- statusline, number and sign columns), over annotations larger than the window, with very
-- long notes or many labels, toggled off and on; and flash / picker backends missing.
local H = dofile('tests/helpers.lua')
local E = dofile('tests/edge_helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child, "{ prompt = { ask_name = 'never' } }")

local function mark(s, e, label, note)
  local id = child.lua_get('require("earmark").annotate(0, ...).id', { s, e, { set = 'vivid', label = label or '3' } })
  child.lua('require("earmark").set_note(0, ...)', { id, note or 'a note' })
  return id
end

--- The shown hover's screen rectangle (border included) and the screen rows of the span
--- under the cursor, 0-based; nil when no hover is shown.
local function geometry()
  return child.lua_get([[(function()
    local S = require('earmark.ui.hover').shown
    if not S or not vim.api.nvim_win_is_valid(S.win) then return vim.NIL end
    vim.cmd('redraw') -- a float's position is worked out when it's drawn
    local c = vim.api.nvim_win_get_config(S.win)
    local pos = vim.api.nvim_win_get_position(S.win)
    local b = (c.border and c.border ~= 'none') and 1 or 0
    local hit = require('earmark').at(0)[1]
    local rows = {}
    if hit then
      for r = hit.s[1], hit.e[1] do
        local p = vim.fn.screenpos(S.src_win, r + 1, 1)
        if p.row > 0 then rows[#rows + 1] = p.row - 1 end
      end
    end
    local wpos = vim.api.nvim_win_get_position(S.src_win)
    return {
      -- (a float's position is its border's top left corner)
      top = pos[1], bottom = pos[1] + c.height - 1 + 2 * b, left = pos[2], right = pos[2] + c.width - 1 + 2 * b,
      span_rows = rows, lines = vim.o.lines, columns = vim.o.columns,
      win_top = wpos[1], win_bottom = wpos[1] + vim.api.nvim_win_get_height(S.src_win) - 1,
      height = c.height, width = c.width, cursor_row = vim.fn.screenpos(S.src_win, vim.fn.line('.', S.src_win), 1).row - 1,
    }
  end)()]])
end

--- The hover is on screen and doesn't cover the span's rows.
local function sane(g)
  eq(g ~= vim.NIL, true)
  eq(g.top >= 0 and g.left >= 0, true)
  eq(g.bottom <= g.lines - 1 and g.right <= g.columns - 1, true)
  for _, r in ipairs(g.span_rows) do
    eq(r < g.top or r > g.bottom, true)
  end
end

local function rest(keys)
  child.type_keys(keys or 'l')
  h.settle(250)
end

local LONG = {}
for i = 1, 60 do
  LONG[i] = ('line %d with some words to annotate'):format(i)
end

T['on the top line, under a tabline and a winbar'] = function()
  h.open(LONG)
  child.lua('vim.o.showtabline = 2; vim.wo.winbar = "the winbar"')
  mark({ 0, 0 }, { 0, 4 })
  E.watch(child)
  h.cursor(1, 0)
  rest()
  local g = geometry()
  sane(g)
  eq(g.top > g.span_rows[1], true) -- below it: there's no room above
  E.no_errors(child)
end

T['on the last visible line, above the statusline'] = function()
  h.open(LONG)
  child.lua('vim.o.laststatus = 2')
  E.watch(child)
  child.type_keys('40G', 'zb')
  mark({ 39, 0 }, { 39, 4 })
  h.cursor(40, 0)
  rest()
  local g = geometry()
  sane(g)
  eq(g.bottom < g.span_rows[1], true) -- above it
  E.no_errors(child)
end

T['on the last line with cmdheight=0 and a global statusline'] = function()
  h.open(LONG)
  child.lua('vim.o.cmdheight = 0; vim.o.laststatus = 3')
  E.watch(child)
  child.type_keys('G', 'zb')
  mark({ 59, 0 }, { 59, 4 })
  h.cursor(60, 0)
  rest()
  sane(geometry())
  E.no_errors(child)
end

T['at the last column, nowrap, wide number and sign columns'] = function()
  local lines = { ('x'):rep(300) .. ' end', 'second' }
  h.open(lines)
  child.lua('vim.wo.wrap = false; vim.wo.number = true; vim.wo.signcolumn = "yes:9"; vim.wo.numberwidth = 10')
  mark({ 0, 301 }, { 0, 304 })
  E.watch(child)
  child.type_keys('$')
  h.settle(250)
  rest('h')
  local g = geometry()
  sane(g)
  eq(g.right <= g.columns - 1, true)
  E.no_errors(child)
end

T['in a window split to the right, bottom of the screen'] = function()
  h.open(LONG)
  child.cmd('vsplit | split')
  child.cmd('wincmd j')
  E.watch(child)
  child.type_keys('G', 'zb')
  mark({ 59, 10 }, { 59, 20 })
  h.cursor(60, 12)
  rest()
  local g = geometry()
  sane(g)
  E.no_errors(child)
end

T['an annotation larger than the window'] = function()
  h.open(LONG)
  mark({ 0, 0 }, { 59, 4 })
  E.watch(child)
  child.type_keys('30G', 'zz')
  rest()
  local g = geometry()
  eq(g ~= vim.NIL, true)
  -- every visible row is the annotation: the hover stays inside the window, off the
  -- cursor's line
  eq(g.top >= g.win_top and g.bottom <= g.win_bottom, true)
  eq(g.cursor_row < g.top or g.cursor_row > g.bottom, true)
  eq(g.height, 2) -- room for the whole hover
  eq(g.left >= 0 and g.right <= g.columns - 1, true)
  E.no_errors(child)
end

T['an annotation whose start is scrolled off the top'] = function()
  h.open(LONG)
  mark({ 2, 5 }, { 40, 4 })
  E.watch(child)
  child.type_keys('35G', 'zt')
  rest()
  local g = geometry()
  sane(g)
  E.no_errors(child)
end

T['in a split above another window, an annotation running off its bottom'] = function()
  h.open(LONG)
  child.cmd('split')
  child.cmd('resize 8')
  mark({ 3, 0 }, { 50, 4 })
  E.watch(child)
  child.type_keys('gg', '5G')
  rest()
  local g = geometry()
  eq(g ~= vim.NIL, true)
  eq(g.bottom <= g.win_bottom + 1, true) -- not drawn over the window below
  E.no_errors(child)
end

T['a very long note and many labels'] = function()
  h.open(LONG)
  local note = {}
  for i = 1, 200 do
    note[i] = ('note line %d '):format(i) .. ('word '):rep(i % 7 == 0 and 120 or 3)
  end
  local id = mark({ 10, 0 }, { 10, 4 }, '3', table.concat(note, '\n'))
  local values = {}
  for k = 1, 12 do
    values[k] = { set = 'vivid', label = tostring(k) }
  end
  child.lua('require("earmark").set_values(0, ...)', { id, values })
  child.lua('require("earmark").set_tags(0, ...)', { id, { 'one', 'two', ('long'):rep(30) } })
  E.watch(child)
  h.cursor(11, 0)
  rest()
  local g = geometry()
  sane(g)
  eq(g.height <= 15, true) -- hover.max_height = 0.5 of the window
  eq(g.width <= 50, true) -- hover.max_width = 0.5
  child.type_keys(' mi') -- focusable now: scrolls
  child.type_keys('G', 'gg', 'q')
  h.settle()
  E.no_errors(child)
end

T['many overlapping annotations under the cursor'] = function()
  h.open(LONG)
  for k = 1, 12 do
    mark({ 5, 0 }, { 5, 4 + k }, tostring(k), 'note ' .. k)
  end
  E.watch(child)
  h.cursor(6, 1)
  rest()
  sane(geometry())
  child.type_keys('3 mi', 'q')
  h.settle()
  E.no_errors(child)
end

T['auto hover toggled off and on'] = function()
  h.open(LONG)
  mark({ 0, 5 }, { 0, 9 })
  E.watch(child)
  h.cursor(1, 5)
  rest()
  eq(geometry() ~= vim.NIL, true)
  child.type_keys(' mh')
  eq(geometry(), vim.NIL)
  rest()
  rest('h')
  eq(geometry(), vim.NIL)
  child.type_keys(' mh')
  rest()
  eq(geometry() ~= vim.NIL, true)
  -- toggled while a peeked (focused) hover is open
  child.type_keys(' mi', ' mh')
  h.settle()
  child.lua('pcall(require("earmark.ui.hover").hide)')
  child.type_keys(' mh')
  E.no_errors(child)
end

T['hover in a closed fold and with conceal'] = function()
  h.open({ 'a [link](http://example.com/very/long) here', 'two', 'three', 'four' })
  child.lua('vim.wo.conceallevel = 2; vim.bo.filetype = "markdown"; pcall(vim.treesitter.start)')
  mark({ 0, 2 }, { 0, 38 })
  mark({ 2, 0 }, { 2, 5 })
  child.cmd('2,4fold')
  E.watch(child)
  h.cursor(1, 4)
  rest()
  sane(geometry())
  child.type_keys('j')
  h.settle(250)
  child.type_keys('k')
  h.settle(250)
  E.no_errors(child)
end

---------------------------------------------------------------------------
-- flash and picker backends
---------------------------------------------------------------------------

T['jump without flash, select fallback, no snacks or telescope'] = function()
  h.open(LONG)
  mark({ 2, 0 }, { 2, 4 })
  mark({ 7, 0 }, { 7, 4 })
  child.lua([[
    package.loaded.flash, package.preload.flash = nil, function() error('no flash') end
    package.preload.snacks = function() error('no snacks') end
    package.preload.telescope = function() error('no telescope') end
    vim.ui.select = function(items, opts, cb) _G.offered = #items; cb(items[2]) end
  ]])
  E.watch(child)
  child.type_keys(' mj')
  h.settle()
  eq(child.lua_get('_G.offered'), 2)
  eq(child.api.nvim_win_get_cursor(0), { 8, 0 })
  child.type_keys(' mp')
  h.settle()
  child.type_keys(' mP')
  h.settle()
  E.no_errors(child)
end

T['picker = snacks or telescope while neither is installed falls back to select'] = function()
  h.open(LONG)
  mark({ 2, 0 }, { 2, 4 })
  child.lua([[
    package.preload.snacks = function() error('no snacks') end
    package.preload.telescope = function() error('no telescope') end
    vim.ui.select = function(items, opts, cb) _G.offered = (_G.offered or 0) + 1; cb(items[1]) end
  ]])
  E.watch(child)
  for _, name in ipairs({ 'snacks', 'telescope', 'select', 'nonsense' }) do
    child.lua('require("earmark.config").options.picker = ...', { name })
    child.type_keys(' mp')
    h.settle()
  end
  eq(child.lua_get('_G.offered'), 4)
  E.no_errors(child)
end

T['jump with flash present'] = function()
  if vim.fn.isdirectory('deps/flash.nvim') == 0 then MiniTest.skip('flash.nvim not in deps/') end
  h.open(LONG)
  mark({ 2, 0 }, { 2, 4 })
  mark({ 7, 0 }, { 7, 4 })
  child.lua('vim.opt.rtp:append("deps/flash.nvim"); require("flash").setup({ label = { uppercase = false } })')
  E.watch(child)
  child.type_keys(' mj')
  h.settle()
  child.type_keys('<Esc>')
  h.settle()
  -- in a tiny window too
  child.lua('vim.o.lines, vim.o.columns = 5, 20')
  child.type_keys(' mj')
  h.settle()
  child.type_keys('<Esc>')
  h.settle()
  E.no_errors(child)
end

return T
