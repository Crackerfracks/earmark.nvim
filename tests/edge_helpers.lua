-- Shared by the test_edge_*.lua files: catching errors that a keymap, timer or autocmd
-- raised (or earmark's log swallowed) while a test drove the UI.
local E = {}

--- Start recording: clears v:errmsg and :messages, records ERROR-level notifications.
function E.watch(child)
  child.lua([[
    _G.errs = {}
    local orig = vim.notify
    vim.notify = function(m, l, o)
      if l and l >= vim.log.levels.ERROR then table.insert(_G.errs, 'notify: ' .. tostring(m)) end
      return orig(m, l, o)
    end
    vim.v.errmsg = ''
    pcall(vim.cmd, 'messages clear')
    require('earmark.log').entries = {}
  ]])
end

--- Every error seen since `watch`: v:errmsg, error lines in :messages, earmark log
--- warnings and errors, ERROR notifications. `allow`: Lua patterns of entries to ignore.
function E.errors(child, allow)
  local out = child.lua_get([[(function()
    local out = vim.deepcopy(_G.errs or {})
    if vim.v.errmsg ~= '' then out[#out + 1] = 'errmsg: ' .. vim.v.errmsg end
    for _, l in ipairs(require('earmark.log').entries) do
      if l:match(' ERROR ') or l:match(' WARN ') then out[#out + 1] = 'log: ' .. l end
    end
    local ok, msgs = pcall(vim.api.nvim_exec2, 'messages', { output = true })
    for _, l in ipairs(vim.split(ok and msgs.output or '', '\n')) do
      if l:match('^E%d+') or l:match('[Ee]rror') or l:match('traceback') then out[#out + 1] = 'msg: ' .. l end
    end
    return out
  end)()]])
  return vim.tbl_filter(function(e)
    for _, p in ipairs(allow or {}) do
      if e:match(p) then return false end
    end
    return true
  end, out)
end

--- Assert nothing went wrong (after letting scheduled callbacks run).
function E.no_errors(child, allow)
  child.lua('vim.wait(60, function() return false end)')
  MiniTest.expect.equality(E.errors(child, allow), {})
end

return E
