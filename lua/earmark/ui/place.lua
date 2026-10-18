-- Where to put a float next to a span of text: below the span's last screen line, or
-- above its first, always inside the window and never covering the span. Shared by the
-- label prompt, the note editor and the hover.
local api = vim.api
local M = {}

-- Last vertical cursor direction per window: 1 = moved down, -1 = up.
local last_row, direction = {}, {}

--- Called on CursorMoved: remembers which way the cursor last moved vertically, so floats
--- can open on the other side (moving down = reading below, so show the float above).
function M.track(win)
  win = win or api.nvim_get_current_win()
  local row = api.nvim_win_get_cursor(win)[1]
  local prev = last_row[win]
  if prev and row ~= prev then direction[win] = row > prev and 1 or -1 end
  last_row[win] = row
end

function M.forget(win)
  last_row[win], direction[win] = nil, nil
end

function M.direction(win)
  return direction[win]
end

--- Screen position (1-based row, col) of a buffer position, or nil if not visible.
local function screen(win, row, col)
  local ok, p = pcall(vim.fn.screenpos, win, row + 1, col + 1)
  if not ok or p.row == 0 then return nil end
  return p
end

--- Float config for a window `w`×`h` next to span `s`..`e` (0-based, end-exclusive) in `win`.
--- opts.prefer: 'below'|'above' (default: below, unless the cursor last moved down);
--- opts.min_h: smallest acceptable height before trying the other side (default 3);
--- opts.bordered: the float has a border (2 extra rows and columns).
--- `w`/`h` and the returned width/height are the float's inner size.
--- Returns { relative, win, row, col, width, height, side }.
function M.for_span(win, s, e, w, h, opts)
  opts = opts or {}
  local pad = opts.bordered and 2 or 0
  w, h = w + pad, h + pad
  local H, W = api.nvim_win_get_height(win), api.nvim_win_get_width(win)
  local wrow, wcol = unpack(api.nvim_win_get_position(win))
  local info = vim.fn.getwininfo(win)[1]
  local textoff = info and info.textoff or 0
  -- the span's last line may end with an empty end column: use the last included char
  local erow, ecol = e[1], e[2]
  if ecol == 0 and erow > s[1] then erow = erow - 1 end
  local last = screen(win, erow, math.max(0, ecol - 1))
  local first = screen(win, s[1], s[2])
  -- rows (0-based, window-relative) available below the span's last screen line and above
  -- its first; wrapped lines may take more screen rows than one
  local below_row
  if last then
    local line = api.nvim_buf_get_lines(api.nvim_win_get_buf(win), erow, erow + 1, false)[1] or ''
    local line_end = screen(win, erow, math.max(0, #line - 1)) or last
    below_row = line_end.row - wrow -- row just below the line's last screen row
  else
    below_row = H
  end
  local above_room = first and (first.row - wrow - 1) or 0
  local below_room = H - below_row
  local prefer = opts.prefer or (direction[win] == 1 and 'above' or 'below')
  local need = math.min(h, (opts.min_h or 3) + pad)
  local side
  if prefer == 'below' then
    side = below_room >= need and 'below' or (above_room >= need and 'above' or nil)
  else
    side = above_room >= need and 'above' or (below_room >= need and 'below' or nil)
  end
  side = side or (below_room >= above_room and 'below' or 'above')
  local room = side == 'below' and below_room or above_room
  local height = math.max(1 + pad, math.min(h, room))
  local row = side == 'below' and below_row or math.max(0, above_room - height)
  local width = math.max(1 + pad, math.min(w, W))
  local anchor_col = first and (first.col - wcol - 1) or textoff
  local col = math.max(0, math.min(anchor_col, W - width))
  return {
    relative = 'win',
    win = win,
    row = row,
    col = col,
    width = width - pad,
    height = height - pad,
    side = side,
  }
end

--- Usable border for window titles: a float without a border can't show a title.
function M.border_opts(border, title, footer)
  local out = { border = border }
  if border and border ~= 'none' and border ~= '' then
    out.title, out.title_pos = title, title and 'left' or nil
    out.footer, out.footer_pos = footer, footer and 'right' or nil
  end
  return out
end

--- Called on WinLeave of a float that should close when you leave it. Leaving for an
--- operator (a flash.nvim remote yank, `yr`, from inside the float) doesn't count: earmark
--- waits until the operator is done and only calls `on_gone` if you didn't come back.
function M.on_leave(win, on_gone)
  if not vim.fn.mode(1):match('^no') then return vim.schedule(on_gone) end
  local timer = vim.uv.new_timer()
  timer:start(100, 100, vim.schedule_wrap(function()
    if not api.nvim_win_is_valid(win) or api.nvim_get_current_win() == win then
      timer:stop()
      timer:close()
      if not api.nvim_win_is_valid(win) then on_gone() end
      return
    end
    if vim.fn.mode(1):match('^no') then return end
    timer:stop()
    timer:close()
    -- give a remote operation a moment to restore the window it started from
    vim.defer_fn(function()
      if api.nvim_win_is_valid(win) and api.nvim_get_current_win() == win then return end
      on_gone()
    end, 50)
  end))
end

return M
