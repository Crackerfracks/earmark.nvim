-- Highlight styles: fill (default), tint, underline, undercurl, text or a function; set
-- globally, per set or per label, and switched live with `:Earmark style`.
local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child, [[{ prompt = { ask_name = 'never' }, sets = { mine = { style = 'underline',
  labels = { { key = 'a', name = 'A', color = '#cc3333' }, { key = 'b', name = 'B', color = '#3333cc', style = 'text' } } },
  plain = { labels = { { key = '1', name = 'One', color = '#33aa33' } } } } }]])

--- Attributes of the highlight drawn on (row, col): the annotation extmark's group.
local function drawn(row, col)
  return child.lua_get([[(function(r, c)
    for _, ns in pairs(vim.api.nvim_get_namespaces()) do
      for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, { r, c }, { r, c }, { details = true, overlap = true })) do
        local g = m[4].hl_group
        if g and g:match('^Earmark') then
          local d = vim.api.nvim_get_hl(0, { name = g, link = false })
          local out = { group = g }
          for k, v in pairs(d) do out[k] = v end
          return out
        end
      end
    end
    return vim.NIL
  end)(...)]], { row, col })
end

local function mark(label, set)
  return child.lua('local s, l = ...; return require("earmark").annotate(0, {0,4}, {0,9}, { set = s, label = l }).id', { set or 'plain', label or '1' })
end

T['fill is the default; :Earmark style switches every annotation live'] = function()
  h.open()
  mark()
  local d = drawn(0, 5)
  eq(d.bg ~= nil and not d.underline, true)
  for _, st in ipairs({ 'underline', 'undercurl', 'text', 'tint', 'fill' }) do
    child.cmd('Earmark style ' .. st)
    d = drawn(0, 5)
    if st == 'underline' then eq({ d.underline, d.bg }, { true, nil }) end
    if st == 'undercurl' then eq({ d.undercurl, d.bg }, { true, nil }) end
    if st == 'text' then eq({ d.fg ~= nil, d.bg }, { true, nil }) end
    if st == 'tint' then eq({ d.underline, d.bg ~= nil }, { true, true }) end
    if st == 'fill' then eq({ d.underline, d.bg ~= nil }, { nil, true }) end
  end
  -- no name: the next style
  child.cmd('Earmark style')
  eq(child.lua_get('require("earmark.config").options.style'), 'tint')
end

T['a set or a label can have its own style, kept when the global one changes'] = function()
  h.open()
  child.lua('require("earmark").annotate(0, {0,0}, {0,3}, { set = "mine", label = "a" })')
  child.lua('require("earmark").annotate(0, {1,0}, {1,1}, { set = "mine", label = "b" })')
  eq(drawn(0, 1).underline, true)
  eq(drawn(1, 0).bold, true)
  child.cmd('Earmark style undercurl')
  eq(drawn(0, 1).underline, true)
  eq(drawn(1, 0).bold, true)
end

T['stale annotations stay recognisable in a line style'] = function()
  h.open()
  mark()
  child.cmd('Earmark style underline')
  child.api.nvim_buf_set_text(0, 0, 4, 0, 9, { 'qu1ck' })
  h.settle(100)
  local status = child.lua_get('require("earmark").list(0)[1].annotation.status')
  if status == 'stale' then eq(drawn(0, 5).underdashed, true) end
end

T['a function style and a bad style name'] = function()
  h.open()
  mark()
  child.lua([[require('earmark.config').options.style = function(hex) return { fg = hex, italic = true } end
    require('earmark.buffer').rerender(0)]])
  eq(drawn(0, 5).italic, true)
  child.cmd('Earmark style sparkly')
  eq(child.lua_get('type(require("earmark.config").options.style)'), 'function')
end

return T
