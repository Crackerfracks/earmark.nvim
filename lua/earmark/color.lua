-- Color math (OKLab/OKLCH <-> sRGB) and palette generation.
-- Reference: https://bottosson.github.io/posts/oklab/
local M = {}

local function srgb_to_linear(c)
  return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
end

local function linear_to_srgb(c)
  return c <= 0.0031308 and 12.92 * c or 1.055 * c ^ (1 / 2.4) - 0.055
end

local function cbrt(x)
  return x < 0 and -((-x) ^ (1 / 3)) or x ^ (1 / 3)
end

function M.hex_to_rgb(hex)
  hex = hex:gsub('^#', '')
  return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

function M.rgb_to_hex(r, g, b)
  local function byte(c)
    return math.floor(math.max(0, math.min(1, c)) * 255 + 0.5)
  end
  return string.format('#%02x%02x%02x', byte(r), byte(g), byte(b))
end

--- sRGB (0..1) -> OKLab
function M.rgb_to_oklab(r, g, b)
  r, g, b = srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b)
  local l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
  local m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
  local s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
  return 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
end

--- OKLab -> linear-light sRGB (may be out of gamut)
local function oklab_to_linear(L, a, b)
  local l = (L + 0.3963377774 * a + 0.2158037573 * b) ^ 3
  local m = (L - 0.1055613458 * a - 0.0638541728 * b) ^ 3
  local s = (L - 0.0894841775 * a - 1.2914855480 * b) ^ 3
  return 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
end

local function in_gamut(r, g, b)
  local eps = 1e-4
  return r >= -eps and r <= 1 + eps and g >= -eps and g <= 1 + eps and b >= -eps and b <= 1 + eps
end

--- OKLCH -> hex, reducing chroma until the color fits in sRGB.
function M.oklch_to_hex(L, C, h)
  local hr = math.rad(h % 360)
  local function try(c)
    return oklab_to_linear(L, c * math.cos(hr), c * math.sin(hr))
  end
  local r, g, b = try(C)
  if not in_gamut(r, g, b) then
    local lo, hi = 0, C
    for _ = 1, 24 do
      local mid = (lo + hi) / 2
      if in_gamut(try(mid)) then lo = mid else hi = mid end
    end
    r, g, b = try(lo)
  end
  return M.rgb_to_hex(linear_to_srgb(r), linear_to_srgb(g), linear_to_srgb(b))
end

--- Perceptual distance between two hex colors (Euclidean in OKLab).
function M.distance(hex1, hex2)
  local L1, a1, b1 = M.rgb_to_oklab(M.hex_to_rgb(hex1))
  local L2, a2, b2 = M.rgb_to_oklab(M.hex_to_rgb(hex2))
  return math.sqrt((L1 - L2) ^ 2 + (a1 - a2) ^ 2 + (b1 - b2) ^ 2)
end

local function luminance(hex)
  local r, g, b = M.hex_to_rgb(hex)
  return 0.2126 * srgb_to_linear(r) + 0.7152 * srgb_to_linear(g) + 0.0722 * srgb_to_linear(b)
end

function M.contrast_ratio(hex1, hex2)
  local l1, l2 = luminance(hex1), luminance(hex2)
  if l1 < l2 then l1, l2 = l2, l1 end
  return (l1 + 0.05) / (l2 + 0.05)
end

M.dark_fg, M.light_fg = '#111111', '#ffffff'

--- Readable text color on top of `bg`.
function M.contrast_fg(bg)
  return M.contrast_ratio(bg, M.dark_fg) >= M.contrast_ratio(bg, M.light_fg) and M.dark_fg or M.light_fg
end

-- Palette presets for the `numbered` generator.
--   L, C: base lightness/chroma; h0: hue of key 1; zig: lightness alternation between
--   neighbouring base hues (helps low-chroma palettes stay distinguishable).
M.palettes = {
  vivid = { L = 0.70, C = 0.17, h0 = 25, zig = 0.04 },
  pastel = { L = 0.86, C = 0.08, h0 = 10, zig = 0.035 },
  earth = { L = 0.64, C = 0.09, h0 = 50, zig = 0.08 },
  metal = { L = 0.74, C = 0.06, h0 = 60, zig = 0.09 },
  cyber = { L = 0.76, C = 0.21, h0 = 330, zig = 0.05 },
}

-- Shades 11..99: key k belongs to the hue family of key ((k - 1) % 10) + 1, so 11, 21, ... 91
-- are all variants of 1. Shades are picked greedily (row by row) from a grid of lightness,
-- chroma and small hue shifts around each family, maximising the distance to every colour
-- already chosen. Computed once per palette and cached.
local cache = {}

local function lab_of(hex)
  return { M.rgb_to_oklab(M.hex_to_rgb(hex)) }
end

local function dist2(p, q)
  return (p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2 + (p[3] - q[3]) ^ 2
end

local function build(p)
  local Lmin, Lmax = math.max(0.36, p.L - 0.22), math.min(0.94, p.L + 0.14)
  local hexes, labs = {}, {}
  local families = {}
  for base = 0, 9 do
    local h = p.h0 + base * 36
    local Lb = p.L + (base % 2 == 0 and p.zig or -p.zig)
    hexes[base + 1] = M.oklch_to_hex(Lb, p.C, h)
    labs[base + 1] = lab_of(hexes[base + 1])
    local cands = {}
    for li = 0, 7 do
      for _, cm in ipairs({ 0.35, 0.6, 0.85, 1.1, 1.3 }) do
        for _, dh in ipairs({ -10, 0, 10 }) do
          local hex = M.oklch_to_hex(Lmin + (Lmax - Lmin) * li / 7, math.max(0.02, p.C * cm), h + dh)
          cands[#cands + 1] = { hex = hex, lab = lab_of(hex) }
        end
      end
    end
    families[base] = cands
  end
  for row = 1, 9 do
    for base = 0, 9 do
      local best, best_d = nil, -1
      for _, c in ipairs(families[base]) do
        local d = math.huge
        for i = 1, #labs do
          d = math.min(d, dist2(c.lab, labs[i]))
          if d <= best_d then break end
        end
        if d > best_d then best, best_d = c, d end
      end
      local k = row * 10 + base + 1
      hexes[k], labs[k] = best.hex, best.lab
    end
  end
  return hexes
end

--- Color for key `n` (1..99) of a numbered palette.
--- `spec` is a preset name or a table like the entries of `M.palettes`.
function M.numbered(spec, n)
  local p = type(spec) == 'string' and M.palettes[spec] or spec
  assert(p, 'earmark: unknown palette ' .. tostring(spec))
  cache[p] = cache[p] or build(p)
  return cache[p][n]
end

return M
