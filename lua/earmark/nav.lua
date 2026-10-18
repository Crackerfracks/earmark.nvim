-- Moving between annotations: next/previous (wrapping, with a count), next/previous with
-- the same label as the one under the cursor, and flash-style jump labels.
local buffer = require('earmark.buffer')

local api = vim.api
local M = {}

local function notify(msg)
  vim.notify('earmark: ' .. msg)
end

local function before(p, q)
  return p[1] < q[1] or (p[1] == q[1] and p[2] < q[2])
end

local function cursor()
  local c = api.nvim_win_get_cursor(0)
  return { c[1] - 1, c[2] }
end

--- Start positions of live annotations in the current buffer, in order, optionally
--- filtered; duplicates (several annotations starting at one spot) collapse.
local function starts(filter)
  local out = {}
  for _, x in ipairs(buffer.list(0)) do
    if x.s and (not filter or filter(x.annotation)) then
      local last = out[#out]
      if not last or before(last, x.s) then out[#out + 1] = x.s end
    end
  end
  return out
end

--- Move `count` annotations forward (dir 1) or back (-1), wrapping around the buffer.
local function step(dir, count, filter, what)
  local list = starts(filter)
  if #list == 0 then return notify('no ' .. (what or 'annotations')) end
  local cur = cursor()
  -- index of the first start after (or last before) the cursor
  local i
  if dir > 0 then
    i = #list + 1
    for k, p in ipairs(list) do
      if before(cur, p) then
        i = k
        break
      end
    end
  else
    i = 0
    for k = #list, 1, -1 do
      if before(list[k], cur) then
        i = k
        break
      end
    end
  end
  i = i + dir * (math.max(1, count) - 1)
  local wrapped
  if i > #list then
    i, wrapped = (i - 1) % #list + 1, 'top'
  elseif i < 1 then
    i, wrapped = (i - 1) % #list + 1, 'bottom'
  end
  vim.cmd("normal! m'")
  api.nvim_win_set_cursor(0, { list[i][1] + 1, list[i][2] })
  if wrapped then notify('wrapped to ' .. wrapped) end
end

function M.next(count)
  step(1, count or vim.v.count1)
end

function M.prev(count)
  step(-1, count or vim.v.count1)
end

local function same_label(dir)
  local hits = buffer.find(0, cursor())
  if #hits == 0 then return notify('nothing under the cursor') end
  local v = hits[1].a.values[1]
  step(dir, vim.v.count1, function(a)
    local w = a.values[1]
    return w.set == v.set and w.label == v.label
  end, 'other annotations with this label')
end

function M.next_same()
  same_label(1)
end

function M.prev_same()
  same_label(-1)
end

--- Jump labels on every visible annotation (flash.nvim); without flash, the picker.
function M.jump()
  local ok, flash = pcall(require, 'flash')
  if not ok then
    local picker = require('earmark.ui.picker')
    return picker.pick(picker.doc_items(0), { prompt = 'Annotations', on_choice = picker.jump_to })
  end
  flash.jump({
    search = { mode = 'search', max_length = 0, multi_window = false },
    label = { after = false, before = true },
    pattern = '.',
    matcher = function(win)
      local buf = api.nvim_win_get_buf(win)
      local top, bot = vim.fn.line('w0', win) - 1, vim.fn.line('w$', win) - 1
      local out = {}
      for _, x in ipairs(buffer.list(buf)) do
        if x.s and x.s[1] >= top and x.s[1] <= bot then
          out[#out + 1] = { win = win, pos = { x.s[1] + 1, x.s[2] }, end_pos = { x.e[1] + 1, math.max(0, x.e[2] - 1) } }
        end
      end
      return out
    end,
  })
end

return M
