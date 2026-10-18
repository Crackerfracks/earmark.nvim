-- `require('earmark').statusline()`: the label `gh` would use next, how many annotations
-- and notes the buffer has, problems, and the current set's colours as digits. A plain
-- function returning a statusline string; it never patches anyone's statusline.
local buffer = require('earmark.buffer')
local config = require('earmark.config')
local sets = require('earmark.sets')

local api = vim.api
local M = {}

local defined = {} -- group -> fg..host

local function bg_of(host)
  local ok, hl = pcall(api.nvim_get_hl, 0, { name = host or 'StatusLine', link = false })
  if ok and hl.bg then return hl.bg end
  if host then return bg_of(nil) end
end

--- Statusline group in colour `hex` on the background of `host` (the statusline section
--- earmark sits in; default StatusLine), so it never leaves a patch of another colour.
local function group(name, hex, host, bold)
  if host then name = name .. '_' .. host:gsub('[^%w_]', '') end
  local key = tostring(hex) .. (bold and 'b' or '') .. (host or '')
  if defined[name] ~= key then
    api.nvim_set_hl(0, name, { fg = hex, bg = bg_of(host), bold = bold or nil })
    defined[name] = key
  end
  return name
end

function M.apply_highlights()
  defined = {}
end

local function esc(s)
  return (s:gsub('%%', '%%%%'))
end

local last_buf -- the last buffer drawn with annotations state

--- The buffer whose statusline is being drawn. A global statusline (laststatus=3) follows
--- focus into floating windows (earmark's prompt, a picker); it keeps showing the buffer
--- being annotated instead of going blank.
local function target_buf()
  local win = vim.g.statusline_winid
  if not (win and api.nvim_win_is_valid(win)) then win = api.nvim_get_current_win() end
  local buf = api.nvim_win_get_buf(win)
  if buffer.state[buf] then
    last_buf = buf
  elseif vim.o.laststatus == 3 and api.nvim_win_get_config(win).relative ~= ''
    and last_buf and buffer.state[last_buf] then
    return last_buf
  end
  return buf
end

--- Statusline text for the current buffer ('' when it has no annotations state).
--- `next_value` is the label the next `gh` would use. opts.hl: the highlight group of the
--- section the string goes in; colours sit on its background and it is restored after them.
function M.render(next_value, opts)
  local host = opts and opts.hl
  local reset = host and ('%#' .. host .. '#') or '%*'
  local function hl(name, hex, bold)
    return '%#' .. group(name, hex, host, bold) .. '#'
  end
  local buf = target_buf()
  local S = buffer.state[buf]
  if not S then return '' end
  local set = sets.by_name[sets.current]
  local v = next_value
  if not (v and v.set == sets.current and sets.label(v)) then
    v = set and set.labels[1] and { set = set.name, label = set.labels[1].key } or nil
  end
  local parts = {}
  if v then
    local hex = sets.color(v, S.colors)
    if hex then parts[#parts + 1] = hl('EarmarkStlSwatch' .. hex:sub(2), hex) .. '▍' .. reset end
    parts[#parts + 1] = esc(v.set .. '·' .. v.label)
    local name = buffer.display_name(buf, v)
    if name ~= v.label then
      local fg = (api.nvim_get_hl(0, { name = host or 'StatusLine', link = false }).fg)
      parts[#parts + 1] = hl('EarmarkStlName', fg and ('#%06x'):format(fg) or nil, true) .. esc(name) .. reset
    end
  end
  local n, notes, warn = 0, 0, 0
  for _, a in pairs(S.annos) do
    n = n + 1
    if a.note then notes = notes + 1 end
    if a.status == 'detached' or a.status == 'ambiguous' then warn = warn + 1 end
  end
  if n > 0 then parts[#parts + 1] = tostring(n) end
  if notes > 0 then parts[#parts + 1] = (vim.g.have_nerd_font == false and '*' or '✎') .. notes end
  if warn > 0 then parts[#parts + 1] = '⚠' .. warn end
  local o = config.options.statusline
  if o.digits and set and set.numbered then
    local d = {}
    for k = 1, 10 do
      local l = set.by_key[tostring(k)]
      local digit = tostring(k % 10)
      d[#d + 1] = l and (hl('EarmarkStlDigit' .. k, l.color) .. digit) or digit
    end
    parts[#parts + 1] = table.concat(d) .. reset
  end
  return table.concat(parts, ' ')
end

return M
