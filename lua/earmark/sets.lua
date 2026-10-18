-- Label sets: normalisation, lookup, and highlight groups.
local color = require('earmark.color')

local M = {}

--- @class earmark.Label
--- @field key string
--- @field name string
--- @field color string  hex background
--- @field desc string?
--- @field group string  highlight group

--- @class earmark.Set
--- @field name string
--- @field labels earmark.Label[]
--- @field by_key table<string, earmark.Label>

M.order = {} --- @type string[]
M.by_name = {} --- @type table<string, earmark.Set>
M.current = nil --- @type string?

-- Highlight groups are created lazily, the first time a label is drawn, and re-applied on
-- ColorScheme. Variants: a doc colour override, and the stale/ambiguous looks.
local groups = {} -- group name -> { bg = hex, style = nil|'stale'|'ambiguous' }
local group_ids = {} -- "set\0key" -> base group name
local n_groups = 0

local function group_for(set, key)
  local k = set .. '\0' .. key
  if not group_ids[k] then
    n_groups = n_groups + 1
    group_ids[k] = 'EarmarkLabel' .. n_groups
  end
  return group_ids[k]
end

local function define(name, spec)
  if spec.fg then
    vim.api.nvim_set_hl(0, name, { fg = spec.fg, bold = spec.bold or nil })
    return
  end
  local hl = { bg = spec.bg, fg = color.contrast_fg(spec.bg) }
  if spec.style == 'stale' then
    hl.underdashed, hl.sp = true, hl.fg
  elseif spec.style == 'ambiguous' then
    hl.underdotted, hl.sp = true, hl.fg
  end
  vim.api.nvim_set_hl(0, name, hl)
end

--- Highlight group with background `bg` and an optional status style, created on demand.
local function ensure(name, bg, style)
  local g = groups[name]
  if not g or g.bg ~= bg then
    groups[name] = { bg = bg, style = style }
    define(name, groups[name])
  end
  return name
end

local function numbered(name, palette)
  local labels = {}
  for i = 1, 99 do
    labels[i] = { key = tostring(i), name = tostring(i), color = color.numbered(palette, i) }
  end
  return labels
end

local function normalize(name, spec)
  local labels
  if type(spec) == 'string' then
    labels = numbered(name, spec)
  elseif spec.generate == 'numbered' then
    labels = numbered(name, spec.palette or name)
  else
    labels = {}
    for i, l in ipairs(spec.labels or {}) do
      if type(l) == 'string' then l = { name = l } end
      labels[i] = {
        key = tostring(l.key or i),
        name = l.name or tostring(l.key or i),
        desc = l.desc,
        -- auto colours walk the vivid palette so neighbouring labels differ
        color = l.color or color.numbered('vivid', ((i - 1) % 99) + 1),
      }
    end
  end
  local set = {
    name = name,
    labels = labels,
    by_key = {},
    desc = type(spec) == 'table' and spec.desc or nil,
    numbered = type(spec) == 'string' or spec.generate == 'numbered',
  }
  for _, l in ipairs(labels) do
    l.group = group_for(name, l.key)
    set.by_key[l.key] = l
  end
  return set
end

function M.load(opts)
  M.order, M.by_name = {}, {}
  local function add(name, spec)
    if not M.by_name[name] then M.order[#M.order + 1] = name end
    M.by_name[name] = normalize(name, spec)
  end
  for _, v in ipairs(opts.sets) do
    add(v, v)
  end
  local named = {}
  for k in pairs(opts.sets) do
    if type(k) == 'string' then named[#named + 1] = k end
  end
  table.sort(named)
  for _, k in ipairs(named) do
    add(k, opts.sets[k])
  end
  M.current = (opts.current and M.by_name[opts.current]) and opts.current or M.order[1]
  M.apply_highlights()
end

function M.apply_highlights()
  for name, spec in pairs(groups) do
    define(name, spec)
  end
  -- annotations whose label no longer exists
  vim.api.nvim_set_hl(0, 'EarmarkUnknown', { default = true, link = 'Visual' })
end

--- Label for a value {set=, label=}, or nil if the set/label no longer exists.
function M.label(value)
  local set = value and M.by_name[value.set]
  return set and set.by_key[value.label] or nil
end

--- Colour of a value: a doc override (`colors`, "set/key" -> hex) or the label's colour.
function M.color(value, colors)
  local o = colors and value and colors[value.set .. '/' .. value.label]
  if o then return o end
  local l = M.label(value)
  return l and l.color or nil
end

--- Highlight group for a value. `colors` are the doc's overrides; `status` picks the
--- stale/ambiguous look.
function M.group(value, colors, status)
  local l = M.label(value)
  local bg = M.color(value, colors)
  if not bg then return 'EarmarkUnknown' end
  local style = (status == 'stale' or status == 'ambiguous') and status or nil
  local name
  if l and bg == l.color then
    name = l.group
  else
    name = 'EarmarkHex' .. bg:gsub('#', '')
  end
  if style then name = name .. (style == 'stale' and 'Stale' or 'Ambiguous') end
  return ensure(name, bg, style)
end

--- Foreground-only group in colour `hex` (indicators, swatches, names in floats).
function M.fg_group(hex, bold)
  local name = 'EarmarkFg' .. hex:gsub('#', '') .. (bold and 'Bold' or '')
  local g = groups[name]
  if not g then
    groups[name] = { fg = hex, bold = bold }
    define(name, groups[name])
  end
  return name
end

--- Whether a set's labels are generated numbers (1-99).
function M.is_numbered(set_name)
  local set = M.by_name[set_name]
  return set and set.numbered or false
end

--- Candidate labels of a set for what was typed in the label prompt, best first.
--- ctx.name(label) -> display name (doc names); ctx.uses[key] -> times used in the doc;
--- ctx.first -> key to list first when nothing is typed.
--- Digits pick keys: the exact key first, then (numbered sets) the other shades of its
--- family (3 -> 13, 23 ... 93), then keys starting with the digits. Anything else is
--- fuzzy-matched against "key name".
function M.resolve_query(set_name, text, ctx)
  local set = M.by_name[set_name]
  if not set then return {} end
  ctx = ctx or {}
  local uses = ctx.uses or {}
  local function name_of(l)
    return ctx.name and ctx.name(l) or l.name
  end
  text = vim.trim(text or '')
  local out, seen = {}, {}
  local function add(l)
    if l and not seen[l.key] then
      seen[l.key] = true
      out[#out + 1] = l
    end
  end
  if text == '' then
    add(set.by_key[ctx.first or ''])
    local used = vim.tbl_filter(function(l)
      return (uses[l.key] or 0) > 0
    end, set.labels)
    table.sort(used, function(a, b)
      return uses[a.key] > uses[b.key]
    end)
    for _, l in ipairs(used) do
      add(l)
    end
    for _, l in ipairs(set.labels) do
      add(l)
    end
    return out
  end
  if text:match('^%d+$') then
    add(set.by_key[text])
    local n = tonumber(text)
    if set.numbered and n >= 1 and n <= 99 then
      local fam = ((n - 1) % 10) + 1
      for k = fam, 99, 10 do
        add(set.by_key[tostring(k)])
      end
    end
    for _, l in ipairs(set.labels) do
      if vim.startswith(l.key, text) then add(l) end
    end
    if #out > 0 or set.numbered then return out end
  end
  for _, l in ipairs(set.labels) do
    if l.key == text then add(l) end
  end
  for _, l in ipairs(set.labels) do
    if vim.startswith(l.key:lower(), text:lower()) then add(l) end
  end
  local hay = {}
  for _, l in ipairs(set.labels) do
    hay[#hay + 1] = { text = l.key .. ' ' .. name_of(l), label = l }
  end
  for _, m in ipairs(vim.fn.matchfuzzy(hay, text, { key = 'text' })) do
    add(m.label)
  end
  return out
end

--- Display name of a label (without doc names): its name, or "set·key".
function M.label_name(value)
  local l = M.label(value)
  return l and l.name or value.label
end

--- Resolve a count in the current set: the label whose key is the count, else the
--- count-th label.
function M.resolve(count, set_name)
  local set = M.by_name[set_name or M.current]
  if not set then return nil end
  return set.by_key[tostring(count)] or set.labels[count]
end

function M.cycle(step)
  if #M.order == 0 then return end
  local idx = 1
  for i, n in ipairs(M.order) do
    if n == M.current then idx = i end
  end
  M.current = M.order[((idx - 1 + (step or 1)) % #M.order) + 1]
  return M.current
end

return M
