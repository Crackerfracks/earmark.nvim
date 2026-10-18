-- Colour names, the palette and the count hint.
local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child)

local function cname(label, set)
  return child.lua_get('(function(s, l) return require("earmark.sets").color_name({ set = s, label = l }) end)(...)',
    { set or 'vivid', label })
end

T['a colour gets the name of the nearest listed colour'] = function()
  eq(child.lua_get('require("earmark.colornames").name("#ffffff")'), 'White')
  eq(child.lua_get('require("earmark.colornames").name("#000000")'), 'Black')
  eq(child.lua_get('require("earmark.colornames").name("#e50001")'), 'Red')
  eq(child.lua_get('require("earmark.colornames").name("nonsense")'), vim.NIL)
end

T['every label of a set has its own colour name'] = function()
  for _, set in ipairs({ 'vivid', 'pastel', 'earth', 'metal', 'cyber' }) do
    local names = child.lua_get([[(function(set)
      local out = {}
      for _, l in ipairs(require('earmark.sets').by_name[set].labels) do
        out[#out + 1] = require('earmark.sets').color_name({ set = set, label = l.key })
      end
      return out
    end)(...)]], { set })
    eq(#names, 99)
    local seen = {}
    for _, n in ipairs(names) do
      eq(seen[n], nil)
      seen[n] = true
    end
  end
end

T['color_names = false hides them; a function supplies your own'] = function()
  child.lua('require("earmark.config").options.color_names = false')
  eq(child.lua_get('require("earmark.colornames").name("#ffffff")'), vim.NIL)
  child.lua([[require("earmark.config").options.color_names = function(hex) return hex == '#ffffff' and 'Paper' or nil end]])
  eq(child.lua_get('require("earmark.colornames").name("#ffffff")'), 'Paper')
  eq(child.lua_get('require("earmark.colornames").name("#000000")'), 'Black')
end

T['the prompt lists each label with its colour name'] = function()
  h.open()
  h.cursor(1, 4)
  child.type_keys('ghiw')
  h.settle(50)
  local fl = h.floats()
  local text = table.concat(child.get_screenshot().text[3] or {})
  local all = table.concat(vim.tbl_map(function(l) return table.concat(l) end, child.get_screenshot().text), '\n')
  eq(all:find(cname('1'), 1, true) ~= nil, true)
  eq(#fl > 0 and text ~= nil, true)
end

T['the palette shows patches with names; <CR> makes a label the next one'] = function()
  h.open()
  child.lua('require("earmark").rename_label(0, { set = "vivid", label = "3" }, "Vague")')
  child.type_keys(' mc')
  local P = child.lua_get('require("earmark.ui.palette").active ~= nil')
  eq(P, true)
  local lines = child.lua_get('vim.api.nvim_buf_get_lines(require("earmark.ui.palette").active.buf, 0, -1, false)')
  eq(#lines, 99)
  eq(lines[3]:find('Vague', 1, true) ~= nil, true)
  eq(lines[3]:find(cname('3'), 1, true) ~= nil, true)
  -- the patch is drawn in the label's own highlight
  local marks = child.lua_get([[vim.tbl_map(function(m) return m[4].hl_group end, vim.api.nvim_buf_get_extmarks(
    require("earmark.ui.palette").active.buf, require("earmark.ui.palette").ns, { 2, 0 }, { 2, -1 }, { details = true }))]])
  eq(marks[1], child.lua_get('require("earmark.sets").group({ set = "vivid", label = "3" })'))
  -- digits jump: 2 then 3 goes to label 23
  child.type_keys('2', '3')
  eq(child.lua_get('vim.api.nvim_win_get_cursor(0)[1]'), 23)
  child.type_keys('<CR>')
  eq(child.lua_get('require("earmark.ui.palette").active'), vim.NIL)
  eq(child.lua_get('require("earmark").next_value()'), { set = 'vivid', label = '23' })
end

T['<Tab> in the palette shows the next set'] = function()
  h.open()
  child.type_keys(' mc', '<Tab>')
  eq(child.lua_get('require("earmark.ui.palette").active.set'), 'pastel')
  child.type_keys('<CR>')
  eq(child.lua_get('require("earmark.sets").current'), 'pastel')
end

T['a count shows which label it picked until the motion is typed'] = function()
  h.open()
  h.cursor(1, 4)
  -- the child can't be asked anything while it waits for the motion: record what was shown
  child.lua([[
    local hint = require('earmark.ui.count_hint')
    local show = hint.show
    hint.show = function(v)
      show(v)
      _G.hint = hint.win and vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(hint.win), 0, -1, false)[1]
    end
  ]])
  child.type_keys('3gh')
  vim.uv.sleep(60)
  child.type_keys('iw')
  h.settle(30)
  local hint = child.lua_get('_G.hint')
  eq(hint:find(' 3 ', 1, true) ~= nil, true)
  eq(hint:find(cname('3'), 1, true) ~= nil, true)
  eq(#h.floats(), 0)
  eq(h.texts()[1].text, 'quick')
end

T['colours adapt to a light colour scheme and back'] = function()
  local L = function(hex)
    return child.lua_get('(function(h) return (require("earmark.color").rgb_to_oklab(require("earmark.color").hex_to_rgb(h))) end)(...)', { hex })
  end
  local base = child.lua_get('require("earmark.sets").color({ set = "vivid", label = "3" })')
  local function drawn()
    local g = child.lua_get('require("earmark.sets").group({ set = "vivid", label = "3" })')
    return ('#%06x'):format(child.lua_get('vim.api.nvim_get_hl(0, { name = ... }).bg', { g }))
  end
  -- the default dark scheme: exactly the label's colour
  eq(drawn(), base)
  child.lua('vim.o.background = "light"; vim.api.nvim_set_hl(0, "Normal", { bg = "#ffffff", fg = "#000000" }); vim.cmd("doautocmd ColorScheme")')
  local light = drawn()
  eq(light ~= base, true)
  eq(L(light) < 0.88, true) -- clearly darker than the white page
  eq(child.lua_get('require("earmark.sets").color({ set = "vivid", label = "3" })'), base) -- the label itself is unchanged
  child.lua('require("earmark.config").options.color_adapt = false; vim.cmd("doautocmd ColorScheme")')
  eq(drawn(), base)
end

T['the statusline names the colour of an unnamed next label'] = function()
  h.open()
  local s = child.lua_get('require("earmark").statusline()')
  eq(s:find(cname('1'), 1, true) ~= nil, true)
  child.lua('require("earmark").rename_label(0, { set = "vivid", label = "1" }, "Claim")')
  s = child.lua_get('require("earmark").statusline()')
  eq(s:find(cname('1'), 1, true), nil)
end

return T
