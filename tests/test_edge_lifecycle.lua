-- Windows, buffers and tabs changing under an open prompt, hover, note editor, palette or
-- picker: closed, wiped or switched (by a command, a timer or an autocmd), :only, :tabnew,
-- :tabclose, <C-w>o, resizing, colour scheme changes and quitting.
local H = dofile('tests/helpers.lua')
local E = dofile('tests/edge_helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq
local h = H.helpers(child)

local T = H.new_set(child, "{ prompt = { ask_name = 'never' } }")

local function mark(s, e, label)
  return child.lua_get('require("earmark").annotate(0, ...).id', { s, e, { set = 'vivid', label = label or '3' } })
end

local function note_of(id)
  local buf = 'vim.fn.bufnr(_G.root .. "/notes/doc.md")'
  return child.lua_get(('(require("earmark.buffer").annotation(%s, ...) or {}).note or vim.NIL'):format(buf), { id })
end

-- the source file plus a second file, `other`, shown in a split above it
local function two_files()
  h.open(nil, 'notes/other.md')
  child.cmd('split')
  h.open()
  child.lua('_G.src_win, _G.src_buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()')
  child.lua('_G.other_buf = vim.fn.bufnr(_G.root .. "/notes/other.md")')
end

local function count_in(buf_expr)
  return child.lua_get(('#require("earmark").list(%s)'):format(buf_expr))
end

local function note_floats()
  return vim.tbl_filter(function(f) return f.name:match('^earmark://note/') ~= nil end, h.floats())
end

local function in_timer(code)
  child.lua(('vim.defer_fn(function() %s end, 10)'):format(code))
  h.settle(80)
end

local function prompt_active()
  return child.lua_get('require("earmark.ui.prompt").active ~= nil')
end

---------------------------------------------------------------------------
-- The label prompt
---------------------------------------------------------------------------

T['prompt: source window closed from a timer, then typing and <CR>'] = function()
  two_files()
  h.cursor(1, 10)
  E.watch(child)
  child.type_keys('ghiw')
  in_timer('vim.api.nvim_win_close(_G.src_win, true)')
  eq(prompt_active(), false) -- nothing left to label: it closed
  child.type_keys('5', '<CR>')
  h.settle(100)
  E.no_errors(child)
  eq(count_in('_G.other_buf'), 0) -- never the wrong buffer
  eq(#h.floats(), 0)
end

T['prompt: source window switched to another buffer, then <CR>'] = function()
  two_files()
  h.cursor(1, 10)
  E.watch(child)
  child.type_keys('ghiw')
  child.type_keys('5')
  in_timer('vim.api.nvim_win_set_buf(_G.src_win, _G.other_buf)')
  if prompt_active() then child.type_keys('<CR>') end
  h.settle(100)
  E.no_errors(child)
  eq(count_in('_G.other_buf'), 0)
end

T['prompt: source buffer wiped from a timer, then <CR>'] = function()
  two_files()
  h.cursor(1, 10)
  E.watch(child)
  child.type_keys('ghiw', '5')
  in_timer('vim.cmd("bwipeout! " .. _G.src_buf)')
  if prompt_active() then child.type_keys('<CR>') end
  h.settle(100)
  E.no_errors(child)
  eq(count_in('_G.other_buf'), 0)
  eq(#h.floats(), 0)
end

T['prompt: :tabnew from an autocmd while typing'] = function()
  h.open()
  h.cursor(1, 10)
  E.watch(child)
  child.type_keys('ghiw')
  child.lua([[vim.api.nvim_create_autocmd('TextChangedI', { once = true, callback = function()
    vim.schedule(function() vim.cmd('tabnew') end)
  end })]])
  child.type_keys('5')
  h.settle(250)
  E.no_errors(child)
  eq(#h.floats(), 0)
  eq(child.fn.tabpagenr('$'), 2)
end

T['prompt: <C-w>o and :only from inside it'] = function()
  two_files()
  h.cursor(1, 10)
  E.watch(child)
  child.type_keys('ghiw', '<Esc>')
  -- Vim's own refusal (E5601: only a float would remain) is not earmark's
  child.lua('pcall(vim.cmd, "wincmd o")')
  h.settle(250)
  child.lua('vim.v.errmsg = ""')
  if prompt_active() then child.lua('pcall(vim.cmd, "only")') end
  h.settle(250)
  child.lua('vim.v.errmsg = ""')
  E.no_errors(child)
end

T['prompt: VimResized and a colour scheme change while open'] = function()
  h.open()
  h.cursor(1, 10)
  E.watch(child)
  child.type_keys('ghiw', '3')
  child.lua('vim.o.lines, vim.o.columns = 8, 30')
  child.cmd('doautocmd VimResized')
  child.lua('vim.cmd.colorscheme("default"); vim.o.background = "light"')
  h.settle()
  child.type_keys('<CR>')
  h.settle()
  child.lua('vim.o.background = "dark"')
  E.no_errors(child)
  eq(#h.texts(), 1)
end

---------------------------------------------------------------------------
-- The hover
---------------------------------------------------------------------------

local function noted(s, e)
  local id = mark(s or { 0, 4 }, e or { 0, 9 })
  child.lua('require("earmark").set_note(0, ..., "a note")', { id })
  return id
end

local function hover_shown()
  return child.lua_get([[(function()
    local S = require('earmark.ui.hover').shown
    return S ~= nil and vim.api.nvim_win_is_valid(S.win)
  end)()]])
end

T['hover: source window closed, :only, <C-w>o, :tabnew, :tabclose'] = function()
  two_files()
  noted()
  h.cursor(1, 5)
  E.watch(child)
  child.type_keys('l')
  h.settle(250)
  eq(hover_shown(), true)
  child.type_keys('<C-w>o')
  h.settle(250)
  child.type_keys('h')
  h.settle(250)
  child.cmd('tabnew')
  h.settle(250)
  child.cmd('tabclose')
  h.settle(250)
  child.type_keys('l')
  h.settle(250)
  in_timer('vim.cmd("split"); vim.api.nvim_win_close(0, true)')
  child.cmd('vsplit')
  child.type_keys('h')
  h.settle(250)
  in_timer('vim.api.nvim_win_close(require("earmark.ui.hover").shown and require("earmark.ui.hover").shown.src_win or 0, true)')
  child.type_keys('l')
  h.settle(250)
  E.no_errors(child)
end

T['hover: source buffer wiped while shown'] = function()
  two_files()
  noted()
  h.cursor(1, 5)
  E.watch(child)
  child.type_keys('l')
  h.settle(250)
  eq(hover_shown(), true)
  in_timer('vim.cmd("bwipeout! " .. _G.src_buf)')
  child.type_keys('j', 'k')
  h.settle(250)
  E.no_errors(child)
  eq(hover_shown(), false)
end

T['hover: VimResized and colour scheme changes while shown'] = function()
  h.open()
  noted()
  h.cursor(1, 5)
  E.watch(child)
  child.type_keys('l')
  h.settle(250)
  child.lua('vim.o.lines, vim.o.columns = 6, 24')
  child.cmd('doautocmd VimResized')
  child.lua('vim.cmd.colorscheme("default"); vim.o.background = "light"; vim.o.background = "dark"')
  child.type_keys('l')
  h.settle(250)
  E.no_errors(child)
end

T['hover: focused (peek) and its source window closed'] = function()
  two_files()
  noted()
  h.cursor(1, 5)
  E.watch(child)
  child.type_keys(' mi')
  h.settle()
  in_timer('vim.api.nvim_win_close(_G.src_win, true)')
  child.type_keys('q')
  h.settle()
  E.no_errors(child)
  eq(hover_shown(), false)
end

---------------------------------------------------------------------------
-- The note editor
---------------------------------------------------------------------------

T['note: its buffer wiped while editing'] = function()
  h.open()
  local id = noted()
  h.cursor(1, 5)
  E.watch(child)
  child.type_keys(' mm', 'A', ' more')
  in_timer('vim.cmd("bwipeout! " .. require("earmark.ui.note").active.buf)')
  child.type_keys('<Esc>')
  h.settle(100)
  E.no_errors(child)
  eq(child.lua_get('require("earmark.ui.note").active'), vim.NIL)
  eq(#note_floats(), 0)
  eq(note_of(id), 'a note') -- :bwipeout! discards, as it does for any buffer
  child.type_keys(' mm') -- and it opens again
  eq(note_floats()[1].lines, { 'a note' })
end

T['note: :bdelete of a modified note is refused, the text stays'] = function()
  h.open()
  local id = noted()
  h.cursor(1, 5)
  E.watch(child)
  child.type_keys(' mm', 'A', ' more', '<Esc>')
  child.lua('pcall(vim.cmd, "bdelete")')
  child.lua('vim.v.errmsg = ""')
  child.type_keys('q')
  h.settle()
  E.no_errors(child, { 'E89' })
  eq(note_of(id), 'a note more')
end

T['note: source window closed while editing (float)'] = function()
  two_files()
  local id = noted()
  h.cursor(1, 5)
  E.watch(child)
  child.type_keys(' mm', 'A', ' more', '<Esc>')
  in_timer('vim.api.nvim_win_close(_G.src_win, true)')
  if child.lua_get('require("earmark.ui.note").active ~= nil') then child.type_keys('q') end
  h.settle()
  E.no_errors(child)
  eq(note_of(id), 'a note more')
end

T['note: source buffer wiped while editing'] = function()
  two_files()
  noted()
  h.cursor(1, 5)
  E.watch(child)
  child.type_keys(' mm', 'A', ' more', '<Esc>')
  in_timer('vim.cmd("bwipeout! " .. _G.src_buf)')
  if child.lua_get('require("earmark.ui.note").active ~= nil') then child.type_keys('q') end
  h.settle()
  E.no_errors(child, { 'annotation for this note is gone' })
end

T['note: :tabnew, :tabclose, :only and <C-w>o with the editor open'] = function()
  two_files()
  local id = noted()
  h.cursor(1, 5)
  E.watch(child)
  child.type_keys(' mm', 'A', ' 1', '<Esc>')
  child.cmd('tabnew')
  h.settle(250)
  eq(note_of(id), 'a note 1')
  child.cmd('tabclose')
  h.settle()
  child.type_keys(' mm', 'A', ' 2', '<Esc>')
  child.lua('pcall(vim.cmd, "only")')
  h.settle(250)
  child.lua('vim.v.errmsg = ""')
  if child.lua_get('require("earmark.ui.note").active ~= nil') then child.type_keys('q') end
  h.settle()
  eq(note_of(id), 'a note 1 2')
  child.type_keys(' mm', 'A', ' 3', '<Esc>')
  child.lua('pcall(vim.cmd, "wincmd o")')
  h.settle(250)
  child.lua('vim.v.errmsg = ""')
  if child.lua_get('require("earmark.ui.note").active ~= nil') then child.type_keys('q') end
  h.settle()
  E.no_errors(child)
  eq(note_of(id), 'a note 1 2 3')
end

T['note: split editor, :only from the source window saves it'] = function()
  h.open()
  local id = noted()
  h.cursor(1, 5)
  E.watch(child)
  child.type_keys(' mm', ',s', 'A', ' more', '<Esc>')
  child.lua('vim.api.nvim_set_current_win(vim.fn.win_getid(vim.fn.bufwinnr(_G.root .. "/notes/doc.md")))')
  child.cmd('only')
  h.settle()
  E.no_errors(child)
  eq(note_of(id), 'a note more')
  eq(child.lua_get('require("earmark.ui.note").active'), vim.NIL)
end

T['note: split editor as the last window of a tab, :tabclose from another tab'] = function()
  h.open()
  local id = noted()
  h.cursor(1, 5)
  E.watch(child)
  child.type_keys(' mm', ',s', 'A', ' more', '<Esc>')
  child.cmd('wincmd T') -- the note alone in a new tab
  child.cmd('tabprevious')
  child.lua('pcall(vim.cmd, "tabclose 2")')
  child.lua('vim.v.errmsg = ""')
  h.settle()
  E.no_errors(child)
  eq(note_of(id), 'a note more')
end

T['note: split editor, source window closed, then ,f back to a float'] = function()
  two_files()
  local id = noted()
  h.cursor(1, 5)
  E.watch(child)
  child.type_keys(' mm', ',s', 'A', ' more', '<Esc>')
  child.lua('vim.api.nvim_win_close(_G.src_win, true)')
  h.settle()
  child.type_keys(',f')
  h.settle()
  child.type_keys('A', '!', '<Esc>', 'q')
  h.settle()
  E.no_errors(child)
  eq(note_of(id), 'a note more!')
  eq(child.lua_get('require("earmark.ui.note").active'), vim.NIL)
end

T['prompt and note: :q, <C-w>c and <C-w>w from inside'] = function()
  two_files()
  local id = noted()
  h.cursor(1, 10)
  E.watch(child)
  for _, keys in ipairs({ { ':q<CR>' }, { '<C-w>c' }, { '<C-w>w' }, { ':close<CR>' } }) do
    child.type_keys('ghiw', '5', '<Esc>')
    child.type_keys(unpack(keys))
    h.settle(250)
    eq(child.lua_get('require("earmark.ui.prompt").active'), vim.NIL)
    child.lua('vim.api.nvim_set_current_win(_G.src_win)')
    h.cursor(1, 5)
    child.type_keys(' mm', 'A', 'x', '<Esc>')
    child.type_keys(unpack(keys))
    h.settle(250)
    eq(child.lua_get('require("earmark.ui.note").active'), vim.NIL)
    child.lua('vim.api.nvim_set_current_win(_G.src_win)')
    h.cursor(1, 10)
  end
  E.no_errors(child)
  eq(note_of(id), 'a notexxxx')
  eq(count_in('_G.src_buf'), 1) -- only the noted one: every prompt was left
end

T['note: :wq, :x, ZZ and :w then :q save and close'] = function()
  two_files()
  local id = noted()
  E.watch(child)
  for i, keys in ipairs({ { ':wq<CR>' }, { ':x<CR>' }, { 'ZZ' }, { ':w<CR>', ':q<CR>' }, { ':update | close<CR>' } }) do
    child.lua('vim.api.nvim_set_current_win(_G.src_win)')
    h.cursor(1, 5)
    child.type_keys(' mm', 'A', tostring(i), '<Esc>')
    child.type_keys(unpack(keys))
    h.settle(200)
    eq(child.lua_get('require("earmark.ui.note").active'), vim.NIL)
  end
  E.no_errors(child)
  eq(note_of(id), 'a note12345')
  eq(#child.api.nvim_list_wins() - #h.floats(), 2) -- (the hover may show: the cursor is on a note)
end

T['note: another file opened in its window saves it and closes the editor'] = function()
  two_files()
  local id = noted()
  E.watch(child)
  h.cursor(1, 5)
  child.type_keys(' mm', 'A', ' more', '<Esc>', ',s')
  child.cmd('edit ' .. child.lua_get('_G.root') .. '/notes/other.md')
  h.settle()
  E.no_errors(child)
  eq(note_of(id), 'a note more')
  eq(child.lua_get('require("earmark.ui.note").active'), vim.NIL)
  -- the window stays, with the file opened in it
  eq(child.api.nvim_buf_get_name(0):match('other%.md$') ~= nil, true)
  eq(#child.api.nvim_list_wins() - #h.floats(), 3)
  -- nothing unsaved is left to stop :qa
  eq(child.lua_get('#vim.tbl_filter(function(b) return vim.bo[b].modified end, vim.api.nvim_list_bufs())'), 0)
end

T['an annotation in an earmark float (the hover, entered) is not saved as a scratch document'] = function()
  h.open()
  noted()
  h.cursor(1, 5)
  child.type_keys(' mi', '3ghiw')
  h.settle()
  child.type_keys('q')
  h.settle(700)
  eq(child.lua_get('#vim.fn.globpath(_G.tmp .. "/data/scratch", "*.json", false, true)'), 0)
end

T['note: gh and the note key from inside the note editor'] = function()
  h.open()
  local id = noted()
  h.cursor(1, 5)
  E.watch(child)
  child.type_keys(' mm', 'A', ' more words', '<Esc>', 'b')
  child.type_keys('ghiw')
  h.settle(250)
  if child.lua_get('require("earmark.ui.prompt").active ~= nil') then child.type_keys('5', '<CR>') end
  h.settle(250)
  if child.lua_get('require("earmark.ui.note").active ~= nil') then
    child.type_keys('3ghiw', ' mm', ' mi')
    h.settle()
    child.lua('pcall(require("earmark.ui.hover").hide)')
    child.lua('if require("earmark.ui.note").active then require("earmark.ui.note").close() end')
  end
  h.settle()
  E.no_errors(child)
  eq(note_of(id), 'a note more words')
end

T["gh, the note key and the key list inside earmark's own floats"] = function()
  h.open()
  noted()
  E.watch(child)
  local function inside(open_keys)
    child.lua('vim.api.nvim_set_current_win(vim.fn.win_getid(vim.fn.bufwinnr(_G.root .. "/notes/doc.md")))')
    h.cursor(1, 5)
    child.type_keys(unpack(open_keys))
    h.settle()
    for _, keys in ipairs({ { '3ghiw' }, { 'ghh' }, { ' mm' }, { ' mi' } }) do
      if child.lua_get('vim.api.nvim_win_get_config(0).relative') == '' then break end
      child.lua('pcall(vim.api.nvim_input, ...)', { table.concat(keys) })
      h.settle(150)
      child.lua('pcall(vim.api.nvim_input, "<Esc><Esc>")')
      h.settle(100)
    end
    child.lua([[for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(w).relative ~= '' then pcall(vim.api.nvim_win_close, w, true) end
    end]])
    h.settle()
  end
  inside({ 'ghiw', '<Esc>' }) -- the label prompt, in Normal mode
  inside({ ' mi' }) -- the hover, entered
  inside({ ' mc' }) -- the palette
  inside({ ' m?' }) -- the key list
  child.lua('if require("earmark.ui.note").active then require("earmark.ui.note").close() end')
  h.settle()
  E.no_errors(child)
  for _, ui in ipairs({ 'prompt', 'note', 'palette', 'keys' }) do
    eq(child.lua_get(('require("earmark.ui.%s").active ~= nil'):format(ui)), false)
  end
end

T['in a floating window of another plugin: gh, the hover, the note editor'] = function()
  h.open()
  local id = noted()
  E.watch(child)
  child.lua([[
    _G.fwin = vim.api.nvim_open_win(0, true, { relative = 'editor', row = 3, col = 10, width = 50, height = 4, border = 'single' })
  ]])
  h.cursor(1, 5)
  child.type_keys('l')
  h.settle(250)
  h.cursor(1, 12)
  child.type_keys('ghiw', '5', '<CR>')
  h.settle()
  h.cursor(1, 5)
  child.type_keys(' mm', 'A', ' from a float', '<Esc>', 'q')
  h.settle()
  eq(child.api.nvim_get_current_win(), child.lua_get('_G.fwin'))
  child.type_keys(' mi')
  h.settle()
  child.type_keys('q')
  h.settle()
  -- the foreign float closes while the prompt is open over it
  child.type_keys('gh', 'iw')
  in_timer('vim.api.nvim_win_close(_G.fwin, true)')
  h.settle()
  E.no_errors(child)
  eq(note_of(id), 'a note from a float')
  eq(#h.texts(), 2)
  eq(child.lua_get('require("earmark.ui.prompt").active'), vim.NIL)
end

T['note: VimResized and a colour scheme change while open'] = function()
  h.open()
  local id = noted()
  h.cursor(1, 5)
  E.watch(child)
  child.type_keys(' mm', 'A', ' more')
  child.lua('vim.o.lines, vim.o.columns = 7, 25')
  child.cmd('doautocmd VimResized')
  child.lua('vim.cmd.colorscheme("default"); vim.o.background = "light"')
  child.type_keys('<Esc>', 'q')
  h.settle()
  E.no_errors(child)
  eq(note_of(id), 'a note more')
end

T['note: :bunload of the source buffer saves an unsaved split note first'] = function()
  two_files()
  local id = noted()
  h.cursor(1, 5)
  E.watch(child)
  child.type_keys(' mm', ',s', 'A', ' more', '<Esc>')
  child.lua('vim.cmd("noautocmd wincmd p")')
  child.cmd('bunload! ' .. child.lua_get('_G.src_buf'))
  h.settle()
  child.cmd('edit ' .. child.lua_get('_G.root') .. '/notes/doc.md')
  h.settle()
  -- (the markdown ftplugin's undo runs `silent! nunmap`, which still sets v:errmsg)
  E.no_errors(child, { 'E31: No such mapping' })
  eq(note_of(id), 'a note more')
end

T['note: VimLeavePre saves an unsaved note'] = function()
  h.open()
  noted()
  h.cursor(1, 5)
  local record = child.lua_get('_G.root .. "/.earmark/docs/notes/doc.md.json"')
  child.type_keys(' mm', 'A', ' unsaved', '<Esc>')
  child.lua('vim.cmd("doautocmd VimLeavePre")')
  local rec = vim.json.decode(table.concat(vim.fn.readfile(record), '\n'))
  eq(rec.annotations[1].note, 'a note unsaved')
end

T['note: :qa! with the note unsaved (from the source window)'] = function()
  h.open()
  noted()
  h.cursor(1, 5)
  -- the child's temp dir goes when it exits: copy the record out on VimLeave
  local out = vim.fn.tempname()
  child.lua([[local out = ...
    vim.api.nvim_create_autocmd('VimLeave', { callback = function()
      vim.fn.writefile(vim.fn.readfile(_G.root .. '/.earmark/docs/notes/doc.md.json'), out)
    end })]], { out })
  child.type_keys(' mm', ',s', 'A', ' unsaved', '<Esc>')
  -- a timer moves to the source window without WinLeave (as noautocmd plugins do)
  child.lua('vim.cmd("noautocmd wincmd p")')
  eq(child.lua_get('vim.bo.modified'), false) -- the source window: the note is not current
  child.api.nvim_input(':qa!<CR>')
  vim.wait(2000, function() return vim.fn.filereadable(out) == 1 end)
  local rec = vim.json.decode(table.concat(vim.fn.readfile(out), '\n'))
  eq(rec.annotations[1].note, 'a note unsaved')
end

---------------------------------------------------------------------------
-- Palette, key list, pickers
---------------------------------------------------------------------------

T['palette: source buffer wiped while open, then r, <Tab>, <CR>'] = function()
  two_files()
  E.watch(child)
  child.type_keys(' mc')
  in_timer('vim.cmd("bwipeout! " .. _G.src_buf)')
  child.lua('vim.ui.input = function(o, cb) cb("Name") end')
  if child.lua_get('require("earmark.ui.palette").active ~= nil') then
    child.type_keys('r')
    child.type_keys('<Tab>')
    child.type_keys('<CR>')
  end
  h.settle()
  E.no_errors(child)
end

T['palette: r with a floating vim.ui.input (snacks, dressing) still names the label'] = function()
  h.open()
  E.watch(child)
  child.lua([[
    -- an input in its own float, answered later, like snacks.input or dressing.nvim
    vim.ui.input = function(opts, cb)
      local b = vim.api.nvim_create_buf(false, true)
      local w = vim.api.nvim_open_win(b, true, { relative = 'editor', row = 1, col = 1, width = 20, height = 1 })
      vim.defer_fn(function()
        vim.api.nvim_win_close(w, true)
        cb('Claim')
      end, 50)
    end
  ]])
  child.type_keys(' mc', '3', 'r')
  h.settle(200)
  E.no_errors(child)
  eq(child.lua_get('require("earmark").names(0)["vivid/3"]'), 'Claim')
end

T['palette and key list: :tabnew, VimResized, colour scheme'] = function()
  h.open()
  E.watch(child)
  child.type_keys(' mc')
  child.lua('vim.o.lines, vim.o.columns = 6, 22')
  child.cmd('doautocmd VimResized')
  child.lua('vim.cmd.colorscheme("default")')
  child.type_keys('3', '<Tab>')
  child.cmd('tabnew')
  h.settle()
  eq(child.lua_get('require("earmark.ui.palette").active'), vim.NIL)
  child.type_keys(' m?')
  child.lua('vim.o.lines, vim.o.columns = 30, 100')
  child.cmd('doautocmd VimResized')
  child.cmd('tabclose')
  h.settle()
  E.no_errors(child)
  eq(#h.floats(), 0)
end

T['key list: <CR> after the source window closed'] = function()
  two_files()
  E.watch(child)
  child.type_keys(' m?')
  in_timer('vim.api.nvim_win_close(_G.src_win, true)')
  if child.lua_get('require("earmark.ui.keys").active ~= nil') then
    child.type_keys('/', 'next set', '<CR>', '<CR>')
  end
  h.settle()
  E.no_errors(child)
end

T['picker (select): source buffer wiped before the choice'] = function()
  two_files()
  mark({ 0, 4 }, { 0, 9 })
  E.watch(child)
  child.lua([[
    vim.ui.select = function(items, opts, cb)
      vim.defer_fn(function() cb(items[1]) end, 30)
    end
  ]])
  child.type_keys(' mp')
  child.cmd('bwipeout! ' .. child.lua_get('_G.src_buf'))
  h.settle(100)
  E.no_errors(child)
  -- the file was opened again to show the choice
  eq(child.api.nvim_buf_get_name(0):match('doc%.md$') ~= nil, true)
end

T['review: source buffer wiped before an action is chosen'] = function()
  two_files()
  mark({ 0, 4 }, { 0, 9 })
  child.lua('vim.cmd("normal! 0wdw"); require("earmark.buffer").on_change(0)')
  E.watch(child)
  child.lua([[
    _G.n = 0
    vim.ui.select = function(items, opts, cb)
      _G.n = _G.n + 1
      if _G.n == 1 then return cb(items[1]) end
      -- the action list: wipe the buffer, then choose each action in turn
      _G.actions = items
      vim.cmd('bwipeout! ' .. _G.src_buf)
    end
  ]])
  child.type_keys(' md')
  h.settle()
  eq(child.lua_get('_G.n'), 2)
  for i = 1, child.lua_get('#_G.actions') do
    child.lua([[local i = ...
      local ok, err = pcall(_G.actions[i].run)
      if not ok then table.insert(_G.errs, 'action ' .. i .. ': ' .. tostring(err)) end]], { i })
  end
  h.settle()
  E.no_errors(child)
end

T['tags list: annotation erased while the list is open'] = function()
  h.open()
  local id = mark({ 0, 4 }, { 0, 9 })
  E.watch(child)
  child.lua([[
    vim.ui.select = function(items, opts, cb)
      _G.tag_cb, _G.tag_items = cb, items
    end
  ]])
  h.cursor(1, 5)
  child.type_keys(' mt')
  child.lua('require("earmark").erase(0, { ... })', { id })
  child.lua('_G.tag_cb(_G.tag_items[2])')
  h.settle()
  E.no_errors(child)
end

return T
