-- The transient popup shown when switching label sets: the set's name and its first
-- colours, at the top of the screen, gone after a moment or the next key.
local config = require('earmark.config')
local sets = require('earmark.sets')

local api = vim.api
local M = {}

M.ns = api.nvim_create_namespace('earmark_set_popup')
M.win = nil

local timer

function M.close()
  if timer then timer:stop() end
  if M.win and api.nvim_win_is_valid(M.win) then
    local buf = api.nvim_win_get_buf(M.win)
    pcall(api.nvim_win_close, M.win, true)
    pcall(api.nvim_buf_delete, buf, { force = true })
  end
  M.win = nil
end

--- Chunks { text, group } describing a set: name, then swatches (numbered sets: the first
--- ten; named sets: "■ name" pairs while they fit in `width`).
function M.chunks(set_name, width)
  local set = sets.by_name[set_name]
  if not set then return {} end
  local glyph = vim.g.have_nerd_font == false and '#' or '■'
  local out = { { ' ' .. set_name .. '  ', 'NormalFloat' } }
  local w = vim.fn.strdisplaywidth(out[1][1])
  for i, l in ipairs(set.labels) do
    local text = set.numbered and (glyph .. ' ') or (glyph .. ' ' .. l.name .. '  ')
    if (set.numbered and i > 10) or w + vim.fn.strdisplaywidth(text) > width then break end
    out[#out + 1] = { text, sets.fg_group(l.color) }
    w = w + vim.fn.strdisplaywidth(text)
  end
  return out
end

function M.show(set_name, ms)
  M.close()
  local chunks = M.chunks(set_name, math.min(70, vim.o.columns - 4))
  if #chunks == 0 then return end
  local text, marks, col = '', {}, 0
  for _, c in ipairs(chunks) do
    text = text .. c[1]
    marks[#marks + 1] = { col, col + #c[1], c[2] }
    col = col + #c[1]
  end
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  api.nvim_buf_set_lines(buf, 0, -1, false, { text })
  for _, m in ipairs(marks) do
    api.nvim_buf_set_extmark(buf, M.ns, 0, m[1], { end_col = m[2], hl_group = m[3] })
  end
  local width = vim.fn.strdisplaywidth(text)
  M.win = api.nvim_open_win(buf, false, {
    relative = 'editor',
    row = 1,
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = 1,
    style = 'minimal',
    border = config.options.ui.border,
    focusable = false,
    zindex = 70,
    noautocmd = true,
  })
  timer = timer or vim.uv.new_timer()
  timer:stop()
  timer:start(ms or 1500, 0, vim.schedule_wrap(M.close))
  api.nvim_create_autocmd({ 'CursorMoved', 'InsertEnter', 'CmdlineEnter' }, {
    once = true,
    callback = function()
      vim.schedule(M.close)
    end,
  })
end

return M
