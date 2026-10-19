-- After a count picks the label (3gh), a small float at the cursor shows which one: its
-- colour, key, your name for it and the colour's name, while the motion is still to come.
-- It closes when the operator finishes or is cancelled.
local buffer = require('earmark.buffer')
local config = require('earmark.config')
local sets = require('earmark.sets')

local api = vim.api
local M = {}

M.ns = api.nvim_create_namespace('earmark_count_hint')
M.win = nil

function M.close()
  if M.win and api.nvim_win_is_valid(M.win) then api.nvim_win_close(M.win, true) end
  M.win = nil
end

--- Show the hint for `value` if an operator is still waiting for its motion.
function M.show(value)
  M.close()
  if not api.nvim_get_mode().mode:match('^no') then return end
  local src = api.nvim_get_current_buf()
  local colors = (buffer.state[src] or {}).colors
  local hex = sets.color(value, colors)
  local name = buffer.display_name(src, value)
  local cname = sets.color_name(value, colors)
  local key = ' ' .. value.label .. ' '
  local text = ' ' .. key .. ' ' .. (name ~= value.label and (name .. '  ') or '') .. (cname or '') .. ' '
  local buf = api.nvim_create_buf(false, true)
  vim.b[buf].earmark_ui = true -- never annotated (store.doc)
  vim.bo[buf].bufhidden = 'wipe'
  api.nvim_buf_set_lines(buf, 0, -1, false, { text })
  api.nvim_buf_set_extmark(buf, M.ns, 0, 1, { end_col = 1 + #key, hl_group = sets.group(value, colors) })
  if cname and hex then
    local cs = #text - #cname - 1
    api.nvim_buf_set_extmark(buf, M.ns, 0, cs, { end_col = cs + #cname, hl_group = sets.fg_group(hex) })
  end
  local ok, win = pcall(api.nvim_open_win, buf, false, {
    relative = 'cursor',
    row = 1,
    col = 0,
    width = vim.fn.strdisplaywidth(text),
    height = 1,
    style = 'minimal',
    border = config.options.ui.border,
    focusable = false,
    zindex = 80,
    noautocmd = true,
  })
  if not ok then return end
  M.win = win
  api.nvim_create_autocmd('ModeChanged', {
    pattern = 'no*:*',
    once = true,
    callback = function()
      vim.schedule(M.close)
    end,
  })
  vim.cmd('redraw')
end

return M
