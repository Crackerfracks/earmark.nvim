local child = MiniTest.new_child_neovim()
local eq = MiniTest.expect.equality

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ '-u', 'scripts/minimal_init.lua' })
      child.lua([[
        _G.tmp = vim.fn.tempname()
        _G.root = _G.tmp .. '/proj'
        vim.fn.mkdir(_G.root .. '/.earmark', 'p')
        vim.g.mapleader = ' '
        require('earmark').setup({ storage_dir = _G.tmp .. '/data', debounce_ms = 10 })
        _G.texts = function()
          local out = {}
          for _, x in ipairs(require('earmark').list(0)) do
            local a = x.annotation
            local text = x.s and table.concat(vim.api.nvim_buf_get_text(0, x.s[1], x.s[2], x.e[1], x.e[2], {}), '\n') or nil
            out[#out + 1] = { text = text, label = a.values[1].label, status = a.status }
          end
          return out
        end
        _G.open = function(rel, lines)
          local path = _G.root .. '/' .. rel
          if lines then vim.fn.mkdir(vim.fs.dirname(path), 'p'); vim.fn.writefile(lines, path) end
          vim.cmd('edit ' .. vim.fn.fnameescape(path))
          return path
        end
      ]])
    end,
    post_once = child.stop,
  },
})

local function texts()
  return child.lua_get('_G.texts()')
end

local function set_cursor(row, col)
  child.api.nvim_win_set_cursor(0, { row, col })
end

local LINES = { 'The quick brown fox jumps over the lazy dog.', 'A second line with some words.', 'Third line: the end.' }

local function open(lines)
  return child.lua_get('_G.open(...)', { 'notes/doc.md', lines or LINES })
end

local function settle()
  child.lua('vim.wait(80, function() return false end)')
end

T['operator'] = MiniTest.new_set()

T['operator']['count picks the label and does not multiply the motion'] = function()
  open()
  set_cursor(1, 4)
  child.type_keys('3ghiw')
  eq(texts(), { { text = 'quick', label = '3', status = 'ok' } })
end

T['operator']['no count preselects the last label in the prompt; dot-repeat repeats it'] = function()
  open()
  set_cursor(1, 4)
  child.type_keys('7ghiw')
  set_cursor(1, 10)
  child.type_keys('.')
  set_cursor(2, 2)
  child.type_keys('ghiw')
  child.type_keys('<CR>') -- accept the preselected label 7
  child.type_keys('<CR>') -- skip naming it
  eq(texts(), {
    { text = 'quick', label = '7', status = 'ok' },
    { text = 'brown', label = '7', status = 'ok' },
    { text = 'second', label = '7', status = 'ok' },
  })
end

T['operator']['line, visual and block selections'] = function()
  open()
  set_cursor(2, 0)
  child.type_keys('2ghh')
  eq(texts()[1], { text = LINES[2], label = '2', status = 'ok' })
  child.lua('require("earmark.buffer").erase(0, vim.tbl_map(function(x) return x.annotation.id end, require("earmark").list(0)))')
  set_cursor(1, 4)
  child.type_keys('v', 'e', 'w', 'e', '4gh')
  eq(texts(), { { text = 'quick brown', label = '4', status = 'ok' } })
  set_cursor(2, 2)
  child.type_keys('<C-v>', 'j', 'l', 'l', '5gh')
  local t = texts()
  eq(#t, 3)
  eq(t[2], { text = 'sec', label = '5', status = 'ok' })
  eq(t[3], { text = 'ird', label = '5', status = 'ok' })
end

T['operator']['uses the current motion, never a stale visual selection'] = function()
  open()
  set_cursor(3, 0)
  child.type_keys('v', 'e', '<Esc>')
  set_cursor(1, 10)
  child.type_keys('6ghiw')
  eq(texts(), { { text = 'brown', label = '6', status = 'ok' } })
end

T['operator']['multibyte word'] = function()
  open({ 'un café naïve ici' })
  set_cursor(1, 9)
  child.type_keys('1ghiw')
  eq(texts(), { { text = 'naïve', label = '1', status = 'ok' } })
end

T['operator']['same span is re-labelled, overlaps stack smallest-first'] = function()
  open()
  set_cursor(1, 10)
  child.type_keys('2ghiw')
  child.type_keys('5ghiw')
  eq(texts(), { { text = 'brown', label = '5', status = 'ok' } })
  set_cursor(1, 0)
  child.type_keys('9gh$')
  local at = child.lua_get('vim.tbl_map(function(h) return h.a.quote end, require("earmark").at(0, {0, 11}))')
  eq(at, { 'brown', LINES[1] })
end

T['erase and restore'] = function()
  open()
  set_cursor(1, 10)
  child.type_keys('2ghiw')
  child.type_keys(' mx')
  eq(texts(), {})
  child.type_keys(' mu')
  eq(texts(), { { text = 'brown', label = '2', status = 'ok' } })
end

T['live edits'] = MiniTest.new_set()

T['live edits']['typing inside a span keeps it; outside does not grow it'] = function()
  open()
  set_cursor(1, 4)
  child.type_keys('1ghe')
  set_cursor(1, 6)
  child.type_keys('iXX<Esc>')
  set_cursor(1, 0)
  child.type_keys('iStart <Esc>')
  eq(texts(), { { text = 'quXXick', label = '1', status = 'ok' } })
end

T['live edits']['whole-buffer replace (formatter) is repaired'] = function()
  open({ 'function foo()  ', 'local x = 1   ', 'return x + 2', 'end' })
  set_cursor(2, 6)
  child.type_keys('3gh5l')
  set_cursor(3, 0)
  child.type_keys('4ghe')
  child.api.nvim_buf_set_lines(0, 0, -1, false, { 'function foo()', '  local x = 1', '  return x + 2', 'end' })
  settle()
  eq(texts(), { { text = 'x = 1', label = '3', status = 'ok' }, { text = 'return', label = '4', status = 'ok' } })
end

T['live edits']['deleting the text detaches; undo brings it back'] = function()
  open()
  set_cursor(1, 10)
  child.type_keys('2ghiw')
  child.type_keys('daw')
  settle()
  eq(texts(), { { label = '2', status = 'detached' } })
  child.type_keys('u')
  settle()
  eq(texts(), { { text = 'brown', label = '2', status = 'ok' } })
end

T['live edits']['rewriting the span marks it stale'] = function()
  open()
  set_cursor(1, 4)
  child.type_keys('1gh2e') -- "quick brown"
  set_cursor(1, 4)
  child.type_keys('c2eslow red<Esc>')
  settle()
  child.lua('require("earmark.buffer").save(0)')
  local t = texts()
  eq(t[1].status, 'stale')
  eq(t[1].text, 'slow red')
end

T['live edits'][':e! after the file changed on disk'] = function()
  open()
  set_cursor(1, 10)
  child.type_keys('2ghiw')
  child.cmd('write')
  child.lua([[vim.fn.writefile({ 'Inserted above.', 'The quick brown fox jumps over the lazy dog.', 'A second line with some words.', 'Third line: the end.' }, _G.root .. '/notes/doc.md')]])
  child.cmd('edit!')
  settle()
  eq(texts(), { { text = 'brown', label = '2', status = 'ok' } })
end

T['persistence'] = MiniTest.new_set()

T['persistence']['round trip through the project store'] = function()
  open()
  set_cursor(1, 10)
  child.type_keys('2ghiw')
  child.cmd('write | bwipe')
  eq(child.lua_get('vim.fn.filereadable(_G.root .. "/.earmark/docs/notes/doc.md.json")'), 1)
  open(nil)
  child.cmd('edit')
  eq(texts(), { { text = 'brown', label = '2', status = 'ok' } })
end

T['persistence']['external edit while closed'] = function()
  open()
  set_cursor(1, 10)
  child.type_keys('2ghiw')
  set_cursor(2, 25)
  child.type_keys('3ghiw')
  child.cmd('write | bwipe')
  child.lua([[vim.fn.writefile({ '# Title', '', 'The quick brown fox leaps over the lazy dog.', 'A second line with many words.', 'Third line: the end.' }, _G.root .. '/notes/doc.md')]])
  child.lua('_G.open("notes/doc.md")')
  eq(texts(), {
    { text = 'brown', label = '2', status = 'ok' },
    { text = 'words', label = '3', status = 'ok' },
  })
end

T['persistence']['unsaved buffer changes are accounted for'] = function()
  open()
  child.type_keys('ggOinserted line<Esc>')
  set_cursor(2, 10)
  child.type_keys('2ghiw')
  child.cmd('bwipe!') -- discard: disk text never had the inserted line
  child.lua('_G.open("notes/doc.md")')
  eq(texts(), { { text = 'brown', label = '2', status = 'ok' } })
end

T['persistence']['renamed file keeps its annotations'] = function()
  open()
  set_cursor(1, 10)
  child.type_keys('2ghiw')
  child.cmd('write | bwipe')
  child.lua([[vim.uv.fs_rename(_G.root .. '/notes/doc.md', _G.root .. '/moved.md')]])
  child.lua('_G.open("moved.md")')
  eq(texts(), { { text = 'brown', label = '2', status = 'ok' } })
  child.lua('vim.wait(700, function() return false end)')
  eq(child.lua_get('vim.fn.filereadable(_G.root .. "/.earmark/docs/notes/doc.md.json")'), 0)
  eq(child.lua_get('vim.fn.filereadable(_G.root .. "/.earmark/docs/moved.md.json")'), 1)
end

T['persistence']['unparseable record is never overwritten'] = function()
  child.lua([[
    vim.fn.mkdir(_G.root .. '/.earmark/docs/notes', 'p')
    vim.fn.writefile({ '{ not json' }, _G.root .. '/.earmark/docs/notes/doc.md.json')
  ]])
  open()
  set_cursor(1, 10)
  child.type_keys('2ghiw')
  child.cmd('write')
  child.lua('vim.wait(700, function() return false end)')
  eq(child.lua_get('vim.fn.readfile(_G.root .. "/.earmark/docs/notes/doc.md.json")'), { '{ not json' })
end

T['persistence']['scratch buffers are stored by id'] = function()
  child.cmd('enew')
  child.api.nvim_buf_set_lines(0, 0, -1, false, { 'scratch text here' })
  set_cursor(1, 8)
  child.type_keys('1ghiw')
  child.lua('require("earmark.buffer").save(0)')
  local id = child.lua_get('vim.b.earmark_doc')
  eq(child.lua_get('vim.fn.filereadable(_G.tmp .. "/data/scratch/" .. ... .. ".json")', { id }), 1)
end

T['persistence']['files outside a project use the global store'] = function()
  child.lua([[vim.fn.writefile({ 'loose file text' }, _G.tmp .. '/loose.txt'); vim.cmd('edit ' .. _G.tmp .. '/loose.txt')]])
  set_cursor(1, 6)
  child.type_keys('1ghiw')
  child.lua('require("earmark.buffer").save(0)')
  local path = child.lua_get('(vim.uv.fs_realpath(_G.tmp) .. "/loose.txt"):gsub("^/", "")')
  eq(child.lua_get('vim.fn.filereadable(_G.tmp .. "/data/files/" .. ... .. ".json")', { path }), 1)
end

return T
