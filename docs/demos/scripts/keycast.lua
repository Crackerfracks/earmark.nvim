-- On-screen helpers for the demo recordings (loaded only when EARMARK_DEMO_REC is set).
--   * a title line (the editing window's winbar) saying what the clip demonstrates;
--   * a key box at the bottom right: the keys you typed (vim.on_key), with an optional note
--     above them saying what the current step does.
-- record.py sets the title/note and clears the keys between steps over RPC (Demo_step).
local api = vim.api
local ns = api.nvim_create_namespace('earmark_keycast')
local keys, note, title = {}, '', ''
local buf, win

api.nvim_set_hl(0, 'KeycastKeys', { fg = '#1a1b26', bg = '#e0af68', bold = true })
api.nvim_set_hl(0, 'KeycastNote', { fg = '#c0caf5', bg = '#2f3549', italic = true })
api.nvim_set_hl(0, 'KeycastBorder', { fg = '#e0af68', bg = '#2f3549' })
api.nvim_set_hl(0, 'DemoTitle', { fg = '#1a1b26', bg = '#7aa2f7', bold = true })
api.nvim_set_hl(0, 'DemoTitleFill', { bg = '#1f2335' })

-- How keys are shown: <leader> for Space outside Insert mode, readable names for the rest.
local NAMES = {
  ['<CR>'] = ' ⏎Enter ', ['<Esc>'] = ' Esc ', ['<Tab>'] = ' Tab ', ['<S-Tab>'] = ' S-Tab ',
  ['<BS>'] = ' ⌫ ', ['<Down>'] = ' ↓ ', ['<Up>'] = ' ↑ ', ['<C-N>'] = ' Ctrl-n ',
  ['<C-P>'] = ' Ctrl-p ', ['<C-S>'] = ' Ctrl-s ', ['<C-V>'] = ' Ctrl-v ', ['<C-U>'] = ' Ctrl-u ',
  ['<lt>'] = '<',
}

local function render()
  if not (buf and api.nvim_buf_is_valid(buf)) then buf = api.nvim_create_buf(false, true) end
  local shown = table.concat(keys)
  if shown == '' and note == '' then
    if win and api.nvim_win_is_valid(win) then api.nvim_win_close(win, true) end
    win = nil
    return
  end
  local lines, hls = {}, {}
  if note ~= '' then
    lines[#lines + 1] = ' ' .. note .. ' '
    hls[#lines] = 'KeycastNote'
  end
  lines[#lines + 1] = ' keys: ' .. (shown ~= '' and shown or '…') .. ' '
  hls[#lines] = 'KeycastKeys'
  local width = 0
  for _, l in ipairs(lines) do width = math.max(width, vim.fn.strdisplaywidth(l)) end
  for i, l in ipairs(lines) do lines[i] = l .. string.rep(' ', width - vim.fn.strdisplaywidth(l)) end
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for i, l in ipairs(lines) do
    api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { end_col = #l, hl_group = hls[i] })
  end
  local cfg = {
    relative = 'editor', anchor = 'SE', row = vim.o.lines - 3, col = vim.o.columns - 1,
    width = width, height = #lines, style = 'minimal', focusable = false,
    zindex = 40, -- under earmark's own floats, so it never hides them
    border = 'rounded',
  }
  if win and api.nvim_win_is_valid(win) then
    api.nvim_win_set_config(win, cfg)
  else
    cfg.noautocmd = true
    win = api.nvim_open_win(buf, false, cfg)
    vim.wo[win].winhighlight = 'Normal:KeycastNote,FloatBorder:KeycastBorder'
  end
end

local pending = false
local function schedule_render()
  if pending then return end
  pending = true
  vim.schedule(function()
    pending = false
    pcall(render)
  end)
end

vim.on_key(function(_, typed)
  if not typed or typed == '' then return end
  local k = vim.fn.keytrans(typed)
  if k:match('Mouse') or k:match('^<Scroll') or k:match('^<Cursor') or k:match('^<Ignore') then return end
  -- a completed mapping can arrive as one chunk ("<Space>mx"), so translate inside it
  local mode = api.nvim_get_mode().mode:sub(1, 1)
  local space = (mode == 'i' or mode == 'c' or mode == 'R') and ' ' or '<leader>'
  k = k:gsub('<[%w%-]+>', function(name)
    if name == '<Space>' then return space end
    return NAMES[name]
  end)
  keys[#keys + 1] = k
  while #keys > 40 do table.remove(keys, 1) end
  schedule_render()
end, ns)

local function title_bar()
  if title == '' then return '' end
  return '%#DemoTitle# ▶ ' .. title:gsub('%%', '%%%%') .. ' %#DemoTitleFill#'
end

local function set_winbars()
  for _, w in ipairs(api.nvim_list_wins()) do
    local b = api.nvim_win_get_buf(w)
    local editing = api.nvim_win_get_config(w).relative == '' and not vim.bo[b].filetype:match('^snacks')
      and (vim.bo[b].buftype == '' or vim.bo[b].buftype == 'quickfix' or vim.bo[b].buftype == 'nofile')
    if w ~= win and editing and not vim.w[w].snacks_win then
      vim.wo[w].winbar = title_bar()
    elseif w ~= win and vim.wo[w].winbar ~= '' and vim.wo[w].winbar:find('DemoTitle', 1, true) and not editing then
      vim.wo[w].winbar = ''
    end
  end
end

--- Set the clip title (nil keeps it) and the step note, and clear the keys.
function _G.Demo_step(t, n)
  if type(t) == 'string' then title = t end
  note = type(n) == 'string' and n or ''
  keys = {}
  set_winbars()
  pcall(render)
  vim.cmd.redraw()
  return ''
end

-- Splits and the quickfix window get the title too.
api.nvim_create_autocmd({ 'WinNew', 'BufWinEnter' }, {
  callback = function() vim.schedule(set_winbars) end,
})
