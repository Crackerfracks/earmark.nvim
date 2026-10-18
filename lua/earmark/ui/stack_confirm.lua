-- Asked when a label goes onto text that already has an annotation of exactly that span
-- (`prompt.confirm_stack`): a small float at the cursor shows the labels already there and
-- waits for one key: a (or <CR>) adds the new label as another one, r replaces the first
-- label, anything else cancels.
local buffer = require('earmark.buffer')
local config = require('earmark.config')
local sets = require('earmark.sets')

local api = vim.api
local M = {}

M.ns = api.nvim_create_namespace('earmark_stack_confirm')
M.win = nil

function M.close()
  if M.win and api.nvim_win_is_valid(M.win) then api.nvim_win_close(M.win, true) end
  M.win = nil
end

--- Lines and highlights for the float.
local function build(buf, hits, value)
  local colors = (buffer.state[buf] or {}).colors
  local lines, marks = {}, {}
  local function chip(row, line, v)
    local key = ' ' .. v.label .. ' '
    local s = #line
    marks[#marks + 1] = { row, s, s + #key, sets.group(v, colors) }
    local name = buffer.display_name(buf, v)
    local label = name ~= v.label and name or sets.color_name(v, colors)
    return line .. key .. (label and (' ' .. label) or '')
  end
  local line = ' Already labelled '
  for i, v in ipairs(hits[1].a.values) do
    line = chip(0, line .. (i > 1 and '  ' or ''), v)
  end
  if #hits > 1 then line = line .. ('  (and %d more spans)'):format(#hits - 1) end
  lines[1] = line .. ' '
  lines[2] = chip(1, ' New label ', value) .. ' '
  lines[3] = ' a add as another label   r replace   Esc cancel '
  marks[#marks + 1] = { 2, 1, 2, 'Special' }
  local rs = lines[3]:find('r replace', 1, true) - 1
  marks[#marks + 1] = { 2, rs, rs + 1, 'Special' }
  local es = lines[3]:find('Esc', 1, true) - 1
  marks[#marks + 1] = { 2, es, es + 3, 'Special' }
  return lines, marks
end

--- Ask what to do; calls `done('add' | 'replace' | nil)`. Waits for a key right away, so
--- call it from a scheduled callback, not from inside an operator.
function M.ask(buf, hits, value, done)
  M.close()
  local lines, marks = build(buf, hits, value)
  local fbuf = api.nvim_create_buf(false, true)
  vim.bo[fbuf].bufhidden = 'wipe'
  api.nvim_buf_set_lines(fbuf, 0, -1, false, lines)
  for _, m in ipairs(marks) do
    api.nvim_buf_set_extmark(fbuf, M.ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
  end
  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  local ok, win = pcall(api.nvim_open_win, fbuf, false, {
    relative = 'cursor',
    row = 1,
    col = 0,
    width = width,
    height = #lines,
    style = 'minimal',
    border = config.options.ui.border,
    title = ' earmark ',
    zindex = 70,
    focusable = false,
  })
  M.win = ok and win or nil
  vim.cmd.redraw()
  local got, key = pcall(vim.fn.getcharstr)
  M.close()
  if not got then return done(nil) end
  if key == 'a' or key == '\r' then return done('add') end
  if key == 'r' then return done('replace') end
  done(nil)
end

return M
