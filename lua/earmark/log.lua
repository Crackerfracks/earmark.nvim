-- Diagnostics: a ring buffer of recent messages, warnings mirrored to a log file.
-- `:Earmark log` shows both. Debug messages are kept only when vim.g.earmark_debug is set.
local M = {}

M.max = 200
M.entries = {}

local levels = { 'DEBUG', 'INFO', 'WARN', 'ERROR' }

function M.file()
  local config = require('earmark.config')
  return config.options.storage_dir .. '/earmark.log'
end

local function add(level, msg, ...)
  if select('#', ...) > 0 then msg = msg:format(...) end
  local line = ('%s %-5s %s'):format(os.date('%Y-%m-%d %H:%M:%S'), levels[level], msg)
  M.entries[#M.entries + 1] = line
  if #M.entries > M.max then table.remove(M.entries, 1) end
  if level >= 3 then
    local path = M.file()
    pcall(vim.fn.mkdir, vim.fs.dirname(path), 'p') -- (an unusable storage_dir must not throw here)
    local f = io.open(path, 'a')
    if f then
      f:write(line, '\n')
      f:close()
    end
  end
end

function M.debug(msg, ...)
  if vim.g.earmark_debug then add(1, msg, ...) end
end

function M.info(msg, ...)
  add(2, msg, ...)
end

function M.warn(msg, ...)
  add(3, msg, ...)
end

function M.error(msg, ...)
  add(4, msg, ...)
end

--- Run `fn(...)`; on error, log it with `where` and return nil. Used around every
--- callback that Neovim invokes (autocmds, timers, decoration providers).
function M.guard(where, fn, ...)
  local ok, res = xpcall(fn, debug.traceback, ...)
  if not ok then
    M.error('%s: %s', where, res)
    return nil, res
  end
  return res
end

--- Open the log in a split: this session's messages, then the log file's tail.
function M.show()
  local lines = { '# earmark log (this session)', '' }
  vim.list_extend(lines, #M.entries > 0 and M.entries or { '(nothing logged)' })
  local f = io.open(M.file(), 'r')
  if f then
    local file_lines = vim.split(f:read('*a'), '\n', { trimempty = true })
    f:close()
    lines[#lines + 1] = ''
    lines[#lines + 1] = '# ' .. M.file() .. ' (last 100 lines)'
    lines[#lines + 1] = ''
    vim.list_extend(lines, file_lines, math.max(1, #file_lines - 99))
  end
  -- reuse the log window if it is open, so a second :Earmark log refreshes it
  local buf = vim.fn.bufnr('earmark://log')
  local win = buf > 0 and vim.fn.bufwinid(buf) or -1
  if win > 0 then
    vim.api.nvim_set_current_win(win)
  else
    if buf > 0 then pcall(vim.api.nvim_buf_delete, buf, { force = true }) end
    vim.cmd('botright new')
    buf = vim.api.nvim_get_current_buf()
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].filetype = 'markdown'
    vim.api.nvim_buf_set_name(buf, 'earmark://log')
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

return M
