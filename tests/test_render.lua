local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child)

local LINE = { 'this is a test of overlapping marks', 'second line here', 'third line' }

-- annotate(s, e, label[, set]) with 0-based {row, col} positions; returns the id
local function mark(s, e, label, set)
  return child.lua_get('require("earmark").annotate(0, ...).id', { s, e, { set = set or 'vivid', label = label } })
end

local function segments(top, bot)
  return child.lua_get('require("earmark.render").segments(0, ...)', { top or 0, bot or 10 })
end

local function hex(label)
  return child.lua_get('require("earmark.sets").color({ set = "vivid", label = ... })', { label })
end

local function hl(group)
  return child.lua_get(
    [[(function(g)
      local d = vim.api.nvim_get_hl(0, { name = g })
      local out = {}
      for k, v in pairs(d) do out[k] = type(v) == 'number' and string.format('#%06x', v) or v end
      return out
    end)(...)]],
    { group }
  )
end

-- attribute id of a screen cell (1-based row/col)
local function attr(shot, row, col)
  return shot.attr[row][col]
end

local function shot()
  child.cmd('redraw!')
  return child.get_screenshot()
end

T['nested spans of the same label are visible (his "this is" probe)'] = function()
  h.open(LINE)
  mark({ 0, 0 }, { 0, 7 }, '2')
  mark({ 0, 5 }, { 0, 7 }, '2')
  local segs = segments()
  eq(#segs.overlaps, 1)
  eq(segs.overlaps[1].s, { 0, 5 })
  eq(segs.overlaps[1].e, { 0, 7 })
  local g = child.lua_get('require("earmark.render").overlap_group(...)', { segs.overlaps[1].hexes })
  local d = hl(g)
  -- a deeper shade of the label's colour, nothing underneath
  MiniTest.expect.no_equality(d.bg, hex('2'))
  eq(child.lua_get('require("earmark.color").distance(...)', { d.bg, hex('2') }) < 0.2, true)
  eq(d.underline, nil)
  local s = shot()
  -- "this " vs "is": same label, different look
  MiniTest.expect.no_equality(attr(s, 1, 1), attr(s, 1, 6))
  eq(attr(s, 1, 6), attr(s, 1, 7))
end

T['each level of one label is a deeper shade'] = function()
  h.open(LINE)
  mark({ 0, 0 }, { 0, 14 }, '4')
  mark({ 0, 5 }, { 0, 14 }, '4')
  mark({ 0, 8 }, { 0, 9 }, '4')
  local segs = segments()
  eq(#segs.overlaps, 3) -- [5,8) two deep, [8,9) three deep, [9,14) two deep
  local g2 = child.lua_get('require("earmark.render").overlap_group(...)', { segs.overlaps[1].hexes })
  local g3 = child.lua_get('require("earmark.render").overlap_group(...)', { segs.overlaps[2].hexes })
  eq(segs.overlaps[2].s, { 0, 8 })
  local L = function(x)
    return child.lua_get('(function(h) return (require("earmark.color").rgb_to_oklab(require("earmark.color").hex_to_rgb(h))) end)(...)', { x })
  end
  local l1, l2, l3 = L(hex('4')), L(hl(g2).bg), L(hl(g3).bg)
  eq(l1 > l2 and l2 > l3, true)
end

T['partial overlap of two colours is drawn in their mix, underlined in the outer colour'] = function()
  h.open(LINE)
  local outer = mark({ 0, 0 }, { 0, 14 }, '1')
  local inner = mark({ 0, 10 }, { 0, 22 }, '5')
  local segs = segments()
  eq(#segs.overlaps, 1)
  local o = segs.overlaps[1]
  eq({ o.s, o.e }, { { 0, 10 }, { 0, 14 } })
  eq(o.ids, { outer, inner }) -- the larger span counts as outer
  local d = hl(child.lua_get('require("earmark.render").overlap_group(...)', { o.hexes }))
  MiniTest.expect.no_equality(d.bg, hex('1'))
  MiniTest.expect.no_equality(d.bg, hex('5'))
  eq(d.sp, hex('1'))
  eq(d.underline, true)
  local s = shot()
  MiniTest.expect.no_equality(attr(s, 1, 11), attr(s, 1, 1))
  MiniTest.expect.no_equality(attr(s, 1, 11), attr(s, 1, 20))
end

T['an overlap across lines is one segment'] = function()
  h.open(LINE)
  mark({ 0, 20 }, { 1, 10 }, '1')
  mark({ 0, 25 }, { 2, 3 }, '7')
  local segs = segments()
  eq(#segs.overlaps, 1)
  eq({ segs.overlaps[1].s, segs.overlaps[1].e }, { { 0, 25 }, { 1, 10 } })
  local s = shot()
  MiniTest.expect.no_equality(attr(s, 2, 2), attr(s, 2, 14))
end

T['disjoint and adjacent spans do not overlap'] = function()
  h.open(LINE)
  mark({ 0, 0 }, { 0, 4 }, '1')
  mark({ 0, 4 }, { 0, 7 }, '2')
  mark({ 0, 10 }, { 0, 14 }, '3')
  eq(#segments().overlaps, 0)
end

T['overlap.style = top turns composites off'] = function()
  h.open(LINE)
  child.lua('require("earmark.config").options.overlap.style = "top"')
  mark({ 0, 0 }, { 0, 7 }, '2')
  mark({ 0, 5 }, { 0, 7 }, '2')
  eq(#segments().overlaps, 0)
end

T['with overlap.extra = squares, labels 3+ are swatches after the span'] = function()
  h.open(LINE)
  child.lua('require("earmark.config").options.overlap.extra = "squares"')
  local id = mark({ 0, 0 }, { 0, 4 }, '1')
  child.lua(
    'require("earmark.buffer").set_values(0, ..., { {set="vivid",label="1"}, {set="vivid",label="2"}, {set="vivid",label="3"}, {set="vivid",label="4"} })',
    { id }
  )
  local segs = segments()
  eq(#segs.curls, 1)
  eq(segs.curls[1].hex, hex('2'))
  local d = hl(child.lua_get('require("earmark.render").curl_group(...)', { hex('2') }))
  eq(d.undercurl, true)
  eq(d.sp, hex('2'))
  local s = shot()
  eq(s.text[1][5] .. s.text[1][6], '■■')
  eq(s.text[1][7], ' ')
  MiniTest.expect.no_equality(attr(s, 1, 5), attr(s, 1, 6))
  -- back to one label: no swatches
  child.lua('require("earmark.buffer").set_values(0, ..., { {set="vivid",label="1"} })', { id })
  s = shot()
  eq(s.text[1][5], ' ')
  eq(#segments().curls, 0)
end

T['swatches stay after the span while typing right after it, and go with an erase'] = function()
  h.open(LINE)
  child.lua('require("earmark.config").options.overlap.extra = "squares"')
  local id = mark({ 0, 0 }, { 0, 4 }, '1')
  child.lua(
    'require("earmark.buffer").set_values(0, ..., { {set="vivid",label="1"}, {set="vivid",label="2"}, {set="vivid",label="3"} })',
    { id }
  )
  h.cursor(1, 4)
  child.type_keys('i', 'XY', '<Esc>')
  local s = shot()
  eq(table.concat(s.text[1], '', 1, 8), 'this■XY ')
  child.lua('require("earmark.buffer").erase(0, { ... })', { id })
  s = shot()
  eq(table.concat(s.text[1], '', 1, 7), 'thisXY ')
end

T['labels 3+ share the undercurl in equal runs; the line is not shifted'] = function()
  h.open(LINE)
  local id = mark({ 0, 0 }, { 0, 7 }, '1') -- "this is"
  child.lua(
    'require("earmark.buffer").set_values(0, ..., { {set="vivid",label="1"}, {set="vivid",label="2"}, {set="vivid",label="3"}, {set="vivid",label="4"} })',
    { id }
  )
  local curls = segments().curls
  eq(#curls, 3)
  eq({ curls[1].s, curls[1].e, curls[1].hex }, { { 0, 0 }, { 0, 2 }, hex('2') })
  eq({ curls[2].s, curls[2].e, curls[2].hex }, { { 0, 2 }, { 0, 4 }, hex('3') })
  eq({ curls[3].s, curls[3].e, curls[3].hex }, { { 0, 4 }, { 0, 7 }, hex('4') })
  local s = shot()
  eq(table.concat(s.text[1], '', 1, 10), 'this is a ')
  MiniTest.expect.no_equality(attr(s, 1, 1), attr(s, 1, 3))
end

T['a stale annotation is drawn faded'] = function()
  h.open(LINE)
  local base = child.lua_get('require("earmark.sets").group({ set = "vivid", label = "3" })')
  local stale = child.lua_get('require("earmark.sets").group({ set = "vivid", label = "3" }, nil, "stale")')
  local b, f = hl(base), hl(stale)
  eq(f.underdashed, true)
  local C = function(x)
    return child.lua_get('(function(h) local _, a, b = require("earmark.color").rgb_to_oklab(require("earmark.color").hex_to_rgb(h)); return math.sqrt(a*a+b*b) end)(...)', { x })
  end
  eq(C(f.bg) < C(b.bg) * 0.5, true)
end

T['buffers without annotations cost nothing'] = function()
  h.open(LINE)
  eq(child.lua_get('require("earmark.render").segments(vim.api.nvim_create_buf(false, true), 0, 10)'), { overlaps = {}, curls = {} })
end

T['a failing provider turns itself off for that buffer with one warning'] = function()
  h.open(LINE)
  mark({ 0, 0 }, { 0, 7 }, '2')
  mark({ 0, 5 }, { 0, 7 }, '2')
  child.lua([[
    _G.notes = {}
    vim.notify = function(msg, lvl) table.insert(_G.notes, msg) end
    local r = require('earmark.render')
    _G.real = r.segments
    r.segments = function() error('boom') end
  ]])
  shot()
  shot()
  h.settle()
  eq(#child.lua_get('_G.notes'), 1)
  eq(child.lua_get('require("earmark.log").entries[#require("earmark.log").entries]'):find('boom') ~= nil, true)
  child.lua('require("earmark.render").segments = _G.real')
  shot()
  eq(#child.lua_get('_G.notes'), 1)
end

T[':colorscheme keeps overlaps and labels visible'] = function()
  h.open(LINE)
  mark({ 0, 0 }, { 0, 14 }, '1')
  mark({ 0, 10 }, { 0, 22 }, '5')
  local before = shot()
  child.cmd('colorscheme default')
  local after = shot()
  local g = child.lua_get('require("earmark.render").overlap_group(...)', { segments().overlaps[1].hexes })
  MiniTest.expect.no_equality(hl(g).bg, nil)
  MiniTest.expect.no_equality(attr(after, 1, 11), attr(after, 1, 1))
  MiniTest.expect.no_equality(attr(after, 1, 11), attr(after, 1, 30))
  eq(before.text, after.text)
end

return T
