-- Label sets: normalisation, lookup, and highlight groups.
local color = require('earmark.color')

local M = {}

--- @class earmark.Label
--- @field key string
--- @field name string
--- @field color string  hex background
--- @field desc string?
--- @field group string  highlight group
--- @field choices {key: string, name: string, color: string?}[]?  asked after the label
--- @field choice_by_key table<string, table>?
--- @field text {when: string[]?, prompt: string?}?  free text asked after the choice
--- @field requires table<string, string[]>?  label key -> choices another value must have

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
    vim.api.nvim_set_hl(0, name, { fg = color.adapt(spec.fg), bold = spec.bold or nil })
    return
  end
  local bg = color.adapt(spec.bg)
  local hl = { bg = bg, fg = color.contrast_fg(bg) }
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

--- Choices in list form ({ {key=, name=, color=} | 'name', ... }) or map form
--- ({ a = 'Correct', b = { name = 'Minor', color = '#..' } }), as an ordered list.
local function norm_choices(c)
  if type(c) ~= 'table' then return nil end
  local out = {}
  if c[1] ~= nil then
    for i, x in ipairs(c) do
      if type(x) == 'string' then x = { name = x } end
      out[#out + 1] = { key = tostring(x.key or string.char(96 + i)), name = x.name or tostring(x.key), color = x.color }
    end
  else
    local keys = vim.tbl_keys(c)
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      local x = c[k]
      if type(x) == 'string' then x = { name = x } end
      out[#out + 1] = { key = tostring(k), name = x.name or tostring(k), color = x.color }
    end
  end
  return #out > 0 and out or nil
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
      local choices = norm_choices(l.choices)
      local text = l.text
      if type(text) == 'string' then text = { prompt = text } end
      if text == true then text = {} end
      labels[i] = {
        key = tostring(l.key or i),
        name = l.name or tostring(l.key or i),
        desc = l.desc,
        -- auto colours walk the vivid palette so neighbouring labels differ
        color = l.color or color.numbered('vivid', ((i - 1) % 99) + 1),
        color_name = l.color_name,
        choices = choices,
        text = type(text) == 'table' and text or nil,
        requires = type(l.requires) == 'table' and l.requires or nil,
      }
      if choices then
        labels[i].choice_by_key = {}
        for _, c in ipairs(choices) do
          labels[i].choice_by_key[c.key] = c
        end
      end
    end
  end
  local set = {
    name = name,
    labels = labels,
    by_key = {},
    desc = type(spec) == 'table' and spec.desc or nil,
    numbered = type(spec) == 'string' or spec.generate == 'numbered',
    source = type(spec) == 'table' and spec._source or nil,
  }
  for _, l in ipairs(labels) do
    l.group = group_for(name, l.key)
    set.by_key[l.key] = l
  end
  return set
end

---------------------------------------------------------------------------
-- Set files: ~/.config/earmark/sets/*.{lua,json}, <root>/.earmark/sets/*.{lua,json}
---------------------------------------------------------------------------

M.root = nil --- project root whose set files are loaded
M.files = {} --- path -> mtime of every set file read (for reloading)
M.errors = {} --- path -> message for files that failed to load

--- Default directory for your own set files.
function M.user_dir()
  local base = vim.env.XDG_CONFIG_HOME or (vim.env.HOME .. '/.config')
  return base .. '/earmark/sets'
end

local function mtime(path)
  local st = vim.uv.fs_stat(path)
  return st and (st.mtime.sec * 1e9 + st.mtime.nsec) or 0
end

--- Read one set file. Project Lua files run only once you trust them (`vim.secure`).
local function read_file(path, trusted)
  local data
  if trusted then
    local f = io.open(path, 'r')
    if not f then return nil, 'cannot read' end
    data = f:read('*a')
    f:close()
  else
    data = vim.secure.read(path)
    if not data then return nil, 'not trusted (run :trust on it)' end
  end
  if path:match('%.json$') then
    local ok, t = pcall(vim.json.decode, data, { luanil = { object = true, array = true } })
    if not ok then return nil, t end
    return t
  end
  local fn, err = load(data, '@' .. path)
  if not fn then return nil, err end
  local ok, t = pcall(fn)
  if not ok then return nil, t end
  return t
end

--- Sets defined in a directory: { { name, spec } ... }. A file returning one set (it has
--- `labels` or `generate`) is named after the file (or its `name`); a file returning a
--- table of sets defines each.
local function dir_sets(dir, trusted)
  local out = {}
  local files = vim.fn.globpath(dir, '*.lua', false, true)
  vim.list_extend(files, vim.fn.globpath(dir, '*.json', false, true))
  table.sort(files)
  for _, path in ipairs(files) do
    M.files[path] = mtime(path)
    -- JSON can't run code, so it never needs trust
    local t, err = read_file(path, trusted or path:match('%.json$') ~= nil)
    if type(t) ~= 'table' then
      M.errors[path] = tostring(err or 'did not return a table')
    else
      local base = vim.fn.fnamemodify(path, ':t:r')
      if t.labels or t.generate then
        t._source = path
        out[#out + 1] = { t.name or base, t }
      else
        for k, v in pairs(t) do
          if type(k) == 'string' and (type(v) == 'string' or type(v) == 'table') then
            if type(v) == 'table' then v._source = path end
            out[#out + 1] = { k, v }
          end
        end
      end
    end
  end
  return out
end

--- Build the sets: your setup() sets, then your set files, then the project's set files
--- (a later definition of the same name replaces the earlier one). `root` picks the
--- project; omitted, the last one is kept.
function M.load(opts, root)
  if root ~= nil then M.root = root or nil end
  local previous = M.current
  M.order, M.by_name, M.files, M.errors = {}, {}, {}, {}
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
  if opts.sets_dir ~= false then
    for _, x in ipairs(dir_sets(opts.sets_dir or M.user_dir(), true)) do
      add(x[1], x[2])
    end
  end
  if M.root then
    for _, x in ipairs(dir_sets(M.root .. '/.earmark/sets', false)) do
      add(x[1], x[2])
    end
  end
  for path, err in pairs(M.errors) do
    require('earmark.log').warn('label set file %s: %s', path, err)
  end
  if previous and M.by_name[previous] then
    M.current = previous
  else
    M.current = (opts.current and M.by_name[opts.current]) and opts.current or M.order[1]
  end
  M.apply_highlights()
end

--- Whether any set file changed (or appeared/disappeared) since it was read.
function M.files_changed(opts)
  for path, t in pairs(M.files) do
    if mtime(path) ~= t then return true end
  end
  local dirs = {}
  if opts.sets_dir ~= false then dirs[#dirs + 1] = opts.sets_dir or M.user_dir() end
  if M.root then dirs[#dirs + 1] = M.root .. '/.earmark/sets' end
  for _, d in ipairs(dirs) do
    for _, ext in ipairs({ '*.lua', '*.json' }) do
      for _, path in ipairs(vim.fn.globpath(d, ext, false, true)) do
        if not M.files[path] then return true end
      end
    end
  end
  return false
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

--- Choice {key, name, color} of a value, if it has one.
function M.choice(value)
  local l = M.label(value)
  return l and l.choice_by_key and value.choice and l.choice_by_key[value.choice] or nil
end

--- Colour of a value: a doc override (`colors`, "set/key" -> hex), its choice's colour, or
--- the label's colour.
function M.color(value, colors)
  local o = colors and value and colors[value.set .. '/' .. value.label]
  if o then return o end
  local c = M.choice(value)
  if c and c.color then return c.color end
  local l = M.label(value)
  return l and l.color or nil
end

--- Human name of a value's colour ("Tangerine"): the label's `color_name` if its set gives
--- one, else the nearest name from the colour-name list. A set's own colours get distinct
--- names; a doc override or a choice's colour is named on its own.
function M.color_name(value, colors)
  local hex = M.color(value, colors)
  if not hex then return nil end
  local l = M.label(value)
  if l and hex == l.color then
    if l.color_name then return l.color_name end
    local set = M.by_name[value.set]
    if not set.color_names then
      set.color_names = require('earmark.colornames').for_set(vim.tbl_map(function(x)
        return x.color
      end, set.labels))
      for i, x in ipairs(set.labels) do
        set.color_names[x.key] = set.color_names[i]
      end
    end
    return set.color_names[l.key]
  end
  return require('earmark.colornames').name(hex)
end

--- Whether label `l` may be added next to `others` (values already on the annotation):
--- returns true, or false and the reason.
function M.allowed(set_name, l, others)
  if not l.requires then return true end
  for key, choices in pairs(l.requires) do
    local ok = false
    for _, v in ipairs(others or {}) do
      if v.set == set_name and v.label == key and (choices == true or vim.tbl_contains(choices, v.choice)) then
        ok = true
      end
    end
    if not ok then
      local want = type(choices) == 'table' and table.concat(choices, '/') or 'any'
      return false, ('needs %s = %s'):format(key, want)
    end
  end
  return true
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
