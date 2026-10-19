-- Names for colours: the nearest of ~800 names from the xkcd colour survey, by distance in
-- OKLab (perceptual). Never exact, but close and consistent: the same colour always gets
-- the same name. A set's labels get distinct names (see `M.for_set`), so two shades of
-- one family don't both read "Coral".
local color = require('earmark.color')
local config = require('earmark.config')

local M = {}

local entries -- { { hex, name, L, a, b }, ... }
local cache = {} -- hex -> name

local function load()
  if entries then return entries end
  entries = {}
  for _, e in ipairs(require('earmark.colornames_data')) do
    local L, a, b = color.rgb_to_oklab(color.hex_to_rgb(e[1]))
    entries[#entries + 1] = { e[1], e[2], L, a, b }
  end
  return entries
end

local function valid(hex)
  return type(hex) == 'string' and hex:match('^#%x%x%x%x%x%x$') ~= nil
end

--- Names nearest to `hex`, best first: { { name = , hex = , d = }, ... } (up to n).
function M.nearest(hex, n)
  if not valid(hex) then return {} end
  local L, a, b = color.rgb_to_oklab(color.hex_to_rgb(hex))
  local best = {}
  for _, e in ipairs(load()) do
    local d = (e[3] - L) ^ 2 + (e[4] - a) ^ 2 + (e[5] - b) ^ 2
    if #best < n or d < best[#best].d then
      local i = #best + 1
      while i > 1 and best[i - 1].d > d do
        i = i - 1
      end
      table.insert(best, i, { name = e[2], hex = e[1], d = d })
      if #best > n then best[#best] = nil end
    end
  end
  return best
end

--- Name for a colour (nil for an invalid one, or when `color_names` is false).
--- `color_names` may be a function(hex) returning a name, or nil to use the list.
function M.name(hex)
  local o = config.options.color_names
  if o == false or not valid(hex) then return nil end
  hex = hex:lower()
  if type(o) == 'function' then
    local ok, name = pcall(o, hex)
    if ok and type(name) == 'string' and name ~= '' then return name end
  end
  if cache[hex] == nil then
    local n = M.nearest(hex, 1)[1]
    cache[hex] = n and n.name or false
  end
  return cache[hex] or nil
end

--- Distinct names for a list of colours (a set's labels, in order): each colour takes the
--- nearest name that no closer colour of the list took. Returns names by index.
function M.for_set(hexes)
  local o = config.options.color_names
  local out = {}
  if o == false then return out end
  local pairs_ = {}
  local first = {} -- hex -> index of its first use: the same colour gets the same name
  for i, hex in ipairs(hexes) do
    if valid(hex) and not first[hex:lower()] then
      first[hex:lower()] = i
      for _, c in ipairs(M.nearest(hex:lower(), 12)) do
        pairs_[#pairs_ + 1] = { i = i, name = c.name, d = c.d }
      end
    end
  end
  table.sort(pairs_, function(x, y)
    if x.d ~= y.d then return x.d < y.d end
    return x.i < y.i
  end)
  local taken = {}
  for _, p in ipairs(pairs_) do
    if not out[p.i] and not taken[p.name] then
      out[p.i], taken[p.name] = p.name, true
    end
  end
  -- colours whose few nearest names were all taken: the nearest name still free
  for i, hex in ipairs(hexes) do
    if not out[i] and valid(hex) and first[hex:lower()] == i then
      for _, c in ipairs(M.nearest(hex:lower(), 200)) do
        if not taken[c.name] then
          out[i], taken[c.name] = c.name, true
          break
        end
      end
    end
  end
  for i, hex in ipairs(hexes) do
    if valid(hex) and first[hex:lower()] ~= i then out[i] = out[first[hex:lower()]] end
    if type(o) == 'function' and valid(hex) then
      local ok, name = pcall(o, hex:lower())
      if ok and type(name) == 'string' and name ~= '' then out[i] = name end
    end
  end
  return out
end

return M
