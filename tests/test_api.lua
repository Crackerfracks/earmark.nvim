local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child)

T['API round trip'] = function()
  h.open()
  local r = child.lua_get([[(function()
    local em = require('earmark')
    local a = em.annotate(0, { 0, 4 }, { 0, 9 }, { set = 'vivid', label = '3' })
    em.set_note(0, a.id, 'a note #t')
    em.set_tags(0, a.id, { 'x' })
    em.set_values(0, a.id, { { set = 'vivid', label = '3' }, { set = 'vivid', label = '5' } })
    em.rename_label(0, { set = 'vivid', label = '3' }, 'Three')
    local got = em.get(0, a.id)
    local at = em.at(0, { 0, 6 })
    local out = {
      note = got.note, tags = got.tags, n_values = #got.values,
      names = em.names(0), at = at[1].annotation.id == a.id, list = #em.list(0),
      export = em.export(0)[3],
    }
    out.erased = em.erase(0, { a.id })
    out.after_erase = #em.list(0)
    em.restore(0)
    out.after_restore = #em.list(0)
    return out
  end)()]])
  eq(r, {
    note = 'a note #t', tags = { 'x' }, n_values = 2, names = { ['vivid/3'] = 'Three' }, at = true, list = 1,
    export = '## Three (vivid·3)', erased = 1, after_erase = 0, after_restore = 1,
  })
end

T['on() runs a function on earmark events'] = function()
  h.open()
  child.lua([[
    _G.seen = {}
    local em = require('earmark')
    em.on('Note', function(d) table.insert(_G.seen, 'note:' .. d.action) end)
    em.on('EarmarkAdd', function(d) table.insert(_G.seen, 'add:' .. #d.ids) end)
    local a = em.annotate(0, { 0, 4 }, { 0, 9 }, { set = 'vivid', label = '3' })
    em.set_note(0, a.id, 'n')
  ]])
  eq(child.lua_get('_G.seen'), { 'add:1', 'note:note' })
end

T['hover.show / hover.hide'] = function()
  h.open()
  child.lua('require("earmark").annotate(0, { 0, 4 }, { 0, 9 }, { set = "vivid", label = "3" })')
  h.cursor(1, 5)
  child.lua('require("earmark").hover.show()')
  eq(#h.floats(), 1)
  child.lua('require("earmark").hover.hide()')
  eq(#h.floats(), 0)
end

return T
