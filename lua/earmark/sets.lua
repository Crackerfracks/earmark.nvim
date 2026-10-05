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

local group_ids = {} -- "set\0key" -> group name
local n_groups = 0

local function group_for(set, key)
  local k = set .. '\0' .. key
  if not group_ids[k] then
    n_groups = n_groups + 1
    group_ids[k] = 'EarmarkLabel' .. n_groups
  end
  return group_ids[k]
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
  local set = { name = name, labels = labels, by_key = {}, desc = type(spec) == 'table' and spec.desc or nil }
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
  for _, set in pairs(M.by_name) do
    for _, l in ipairs(set.labels) do
      vim.api.nvim_set_hl(0, l.group, { bg = l.color, fg = color.contrast_fg(l.color), default = false })
    end
  end
  -- annotations whose label no longer exists
  vim.api.nvim_set_hl(0, 'EarmarkUnknown', { default = true, link = 'Visual' })
end

--- Label for a value {set=, label=}, or nil if the set/label no longer exists.
function M.label(value)
  local set = value and M.by_name[value.set]
  return set and set.by_key[value.label] or nil
end

function M.group(value)
  local l = M.label(value)
  return l and l.group or 'EarmarkUnknown'
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
