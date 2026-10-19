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
--- @field tags string[]?  tags offered first in <leader>mt
--- @field files {[1]: string, [2]: string}[]?  { dir, glob }: the set is listed only for these files
--- @field expires string?  YYYY-MM-DD: after that day the set is no longer listed

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
    -- faded: most of the colour drained from the fill, underdashed
    hl.bg = color.shift(bg, 0.35, 0)
    hl.fg = color.contrast_fg(hl.bg)
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

--- Report a problem with set `name` (under its file, when it has one).
local function report(name, spec, msg)
  M.errors[type(spec) == 'table' and spec._source or name] = ('set "%s": %s'):format(name, msg)
end

--- `c` as #rrggbb (#rgb is widened), or nil when it isn't a colour.
local function hex(c)
  if type(c) ~= 'string' then return nil end
  if c:match('^#%x%x%x$') then c = c:gsub('%x', '%0%0') end
  return c:match('^#%x%x%x%x%x%x$') and c or nil
end

--- A label's or choice's colour: nil when not given; an invalid one is reported and dropped.
local function color_of(name, spec, c, what)
  if c == nil then return nil end
  local out = hex(c)
  if not out then report(name, spec, ('%s: colour %s is not #rrggbb'):format(what, vim.inspect(c))) end
  return out
end

--- `expires` as YYYY-MM-DD (2026-1-5 too), or nil; anything else is reported and ignored.
local function expiry(name, spec)
  local e = type(spec) == 'table' and spec.expires or nil
  if e == nil or e == '' then return nil end
  local y, m, d = (type(e) == 'string' and e or ''):match('^%s*(%d%d%d%d)%-(%d%d?)%-(%d%d?)')
  m, d = tonumber(m or ''), tonumber(d or '')
  if y and m >= 1 and m <= 12 and d >= 1 and d <= 31 then return ('%s-%02d-%02d'):format(y, m, d) end
  report(name, spec, ('expires %s is not a date (YYYY-MM-DD); the set does not expire'):format(vim.inspect(e)))
  return nil
end

--- Choices in list form ({ {key=, name=, color=} | 'name', ... }) or map form
--- ({ a = 'Correct', b = { name = 'Minor', color = '#..' } }), as an ordered list.
local function norm_choices(c, name, spec)
  if type(c) ~= 'table' then return nil end
  local out = {}
  if c[1] ~= nil then
    for i, x in ipairs(c) do
      if type(x) == 'string' then x = { name = x } end
      out[#out + 1] = { key = tostring(x.key or string.char(96 + i)), name = x.name or tostring(x.key),
        color = color_of(name, spec, x.color, 'choice ' .. tostring(x.key or i)) }
    end
  else
    local keys = vim.tbl_keys(c)
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      local x = c[k]
      if type(x) == 'string' then x = { name = x } end
      out[#out + 1] = { key = tostring(k), name = x.name or tostring(k),
        color = color_of(name, spec, x.color, 'choice ' .. tostring(k)) }
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
    local at = {} -- key -> index: a later label with the same key replaces the earlier one
    for i, l in ipairs(spec.labels or {}) do
      if type(l) == 'string' then l = { name = l } end
      local choices = norm_choices(l.choices, name, spec)
      local text = l.text
      if type(text) == 'string' then text = { prompt = text } end
      if text == true then text = {} end
      local key = tostring(l.key or i)
      local label = {
        key = key,
        name = (l.name ~= nil and l.name ~= '') and tostring(l.name) or key,
        desc = l.desc,
        -- auto colours walk the vivid palette so neighbouring labels differ
        color = color_of(name, spec, l.color, 'label ' .. key) or color.numbered('vivid', ((i - 1) % 99) + 1),
        color_name = l.color_name,
        choices = choices,
        text = type(text) == 'table' and text or nil,
        requires = type(l.requires) == 'table' and l.requires or nil,
        tags = type(l.tags) == 'table' and #l.tags > 0 and l.tags or nil,
      }
      if choices then
        label.choice_by_key = {}
        for _, c in ipairs(choices) do
          label.choice_by_key[c.key] = c
        end
      end
      if at[key] then
        labels[at[key]] = label
      else
        labels[#labels + 1] = label
        at[key] = #labels
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
    tags = type(spec) == 'table' and type(spec.tags) == 'table' and #spec.tags > 0 and spec.tags or nil,
    files = type(spec) == 'table' and spec._files or nil,
    expires = expiry(name, spec),
    auto = not (type(spec) == 'table' and spec.auto == false),
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
  data = data:gsub('^\239\187\191', '') -- a byte order mark (Windows editors)
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
--- table of sets defines each. `sidecar`: only `*.earmark-set.json` files, each a set for
--- the files next to it (see M.sidecar_dirs).
local function dir_sets(dir, trusted, sidecar)
  local out = {}
  local files
  if sidecar then
    files = M.sidecars(dir)
  else
    files = vim.fn.globpath(dir, '*.lua', false, true)
    vim.list_extend(files, vim.fn.globpath(dir, '*.json', false, true))
  end
  table.sort(files)
  for _, path in ipairs(files) do
    M.files[path] = mtime(path)
    -- JSON can't run code, so it never needs trust
    local t, err = read_file(path, trusted or path:match('%.json$') ~= nil)
    if type(t) ~= 'table' then
      M.errors[path] = tostring(err or 'did not return a table')
    else
      local base = vim.fn.fnamemodify(path, ':t:r')
      if sidecar then
        base = vim.fn.fnamemodify(path, ':t'):sub(1, -#M.SIDECAR - 1)
        -- by default a sidecar is for the files named like it: plan.earmark-set.json -> plan.*
        if t.files == nil then t.files = { base, base .. '.*' } end
      end
      if t.labels or t.generate or t.extends then
        t._source, t._dir, t._stem = path, sidecar and dir or nil, base
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

M.SIDECAR = '.earmark-set.json'
--- Directories whose `*.earmark-set.json` files are loaded (those of files you opened).
M.sidecar_dirs = {}
--- The set in use before a file's own set took over (restored when you leave that file).
M.general = nil

--- `spec` with the labels of the set it `extends` first (its own labels with the same key
--- replace them).
local function extended(spec)
  local base = M.by_name[spec.extends]
  if not base then
    M.errors[spec._source or tostring(spec.extends)] = ('extends unknown set "%s"'):format(tostring(spec.extends))
    return spec
  end
  local out = vim.tbl_extend('force', {}, spec)
  out.extends, out.generate = nil, nil
  local labels, at = {}, {}
  for _, l in ipairs(base.labels) do
    labels[#labels + 1] = {
      key = l.key, name = l.name, desc = l.desc, color = l.color, color_name = l.color_name,
      choices = l.choices, text = l.text, requires = l.requires, tags = l.tags,
    }
    at[l.key] = #labels
  end
  for i, l in ipairs(spec.labels or {}) do
    if type(l) == 'string' then l = { name = l } end
    local key = tostring(l.key or (#base.labels + i))
    l = vim.tbl_extend('force', {}, l, { key = key })
    if at[key] then labels[at[key]] = l else labels[#labels + 1] = l end
  end
  out.labels = labels
  if base.tags and not spec.tags then out.tags = base.tags end
  return out
end

--- `files` globs of a scoped set as { dir, glob } pairs: the glob matches paths relative
--- to dir (so the characters of the folder's own name never count as glob syntax).
local function scope_globs(files, dir)
  if type(files) == 'string' then files = { files } end
  if type(files) ~= 'table' or not dir then return nil end
  local out = {}
  for _, g in ipairs(files) do
    if type(g) == 'string' and g ~= '' then
      if g:sub(1, 1) == '~' then g = vim.env.HOME .. g:sub(2) end
      if g:sub(1, 1) == '/' then
        out[#out + 1] = { '/', g:sub(2) }
      else
        -- ./x is x; ../x is x in the folder above
        local d = vim.fs.normalize(dir)
        while g:sub(1, 2) == './' or g:sub(1, 3) == '../' do
          if g:sub(1, 3) == '../' then d = vim.fs.dirname(d) end
          g = g:gsub('^%.%.?/', '')
        end
        out[#out + 1] = { d, g }
      end
    end
  end
  -- an empty list is a set for no file (never a general one)
  return out
end

--- Build the sets: your setup() sets, then your set files, then the project's set files
--- (a later definition of the same name replaces the earlier one), then the sets next to
--- files you opened. `root` picks the project; omitted, the last one is kept.
function M.load(opts, root)
  if root ~= nil then M.root = root or nil end
  local previous = M.current
  M.order, M.by_name, M.files, M.errors = {}, {}, {}, {}
  local builtin = require('earmark.builtin_sets')
  local function add(name, spec, scope_dir)
    if type(spec) == 'string' and builtin[spec] then spec = builtin[spec] end
    -- a broken set (labels = 5, an unknown palette ...) is reported; the others still load
    local ok, set = pcall(function()
      if type(spec) == 'table' then
        if spec.extends then spec = extended(spec) end
        spec._files = scope_globs(spec.files, scope_dir)
        if spec._files and M.by_name[name] and not M.by_name[name].files then
          -- a set for some files never replaces a general one of the same name
          name = name .. ' (' .. (spec._stem or 'file') .. ')'
        end
      end
      return normalize(name, spec)
    end)
    if not ok then return report(name, spec, set) end
    if not M.by_name[name] then M.order[#M.order + 1] = name end
    M.by_name[name] = set
  end
  --- The sets of one place, a set its neighbours extend before them (in any file order);
  --- what still waits after that (an unknown name, a cycle) is added as it is.
  local function add_all(list, scope_dir)
    while #list > 0 do
      local waiting = {}
      for _, x in ipairs(list) do
        local ext = type(x[2]) == 'table' and x[2].extends
        if ext and not M.by_name[ext] then waiting[#waiting + 1] = x else add(x[1], x[2], scope_dir) end
      end
      if #waiting == #list then
        for _, x in ipairs(waiting) do
          add(x[1], x[2], scope_dir)
        end
        return
      end
      list = waiting
    end
  end
  for _, v in ipairs(opts.sets) do
    add(v, v)
  end
  local named = {}
  for k in pairs(opts.sets) do
    if type(k) == 'string' then named[#named + 1] = { k, opts.sets[k] } end
  end
  table.sort(named, function(a, b) return a[1] < b[1] end)
  add_all(named)
  if opts.sets_dir ~= false then
    add_all(dir_sets(opts.sets_dir or M.user_dir(), true), vim.env.HOME)
  end
  if M.root then
    add_all(dir_sets(M.root .. '/.earmark/sets', false), M.root)
  end
  local dirs = vim.tbl_keys(M.sidecar_dirs)
  table.sort(dirs)
  for _, d in ipairs(dirs) do
    add_all(dir_sets(d, true, true), d)
  end
  for path, err in pairs(M.errors) do
    require('earmark.log').warn('label set file %s: %s', path, err)
  end
  if previous and M.by_name[previous] then
    M.current = previous
  else
    M.current = (opts.current and M.by_name[opts.current]) and opts.current or M.order[1]
  end
  if M.general and not M.by_name[M.general] then M.general = nil end
  M.focused = nil -- a file's set may have appeared or gone: look again
  M.apply_highlights()
end

--- Whether any set file changed (or appeared/disappeared) since it was read.
function M.files_changed(opts)
  for path, t in pairs(M.files) do
    if mtime(path) ~= t then return true end
  end
  local dirs = {}
  if opts.sets_dir ~= false then dirs[#dirs + 1] = { opts.sets_dir or M.user_dir(), { '*.lua', '*.json' } } end
  if M.root then dirs[#dirs + 1] = { M.root .. '/.earmark/sets', { '*.lua', '*.json' } } end
  for d in pairs(M.sidecar_dirs) do
    for _, path in ipairs(M.sidecars(d)) do
      if not M.files[path] then return true end
    end
  end
  for _, d in ipairs(dirs) do
    for _, ext in ipairs(d[2]) do
      for _, path in ipairs(vim.fn.globpath(d[1], ext, false, true)) do
        if not M.files[path] then return true end
      end
    end
  end
  return false
end

--- Paths of the `*.earmark-set.json` files in `dir` (not globpath: a folder named
--- "[draft]" would be read as a pattern).
function M.sidecars(dir)
  local out = {}
  local ok, iter = pcall(vim.fs.dir, dir)
  if not ok then return out end
  for name, kind in iter do
    if (kind == 'file' or kind == 'link') and name:sub(-#M.SIDECAR) == M.SIDECAR and #name > #M.SIDECAR then
      out[#out + 1] = dir .. '/' .. name
    end
  end
  table.sort(out)
  return out
end

--- Start loading the `*.earmark-set.json` files in `dirs`; true if one of them has any and
--- wasn't watched yet (the sets need loading again).
function M.watch_dirs(dirs)
  local new = false
  for _, dir in ipairs(dirs) do
    if dir ~= '' and not M.sidecar_dirs[dir] and #M.sidecars(dir) > 0 then
      M.sidecar_dirs[dir] = true
      new = true
    end
  end
  return new
end

local function today()
  return os.date('%Y-%m-%d')
end

--- Whether set `name` is offered for the file at `path` (nil: no file): not past its
--- `expires` day, and, if it is for some files only, `path` is one of them.
function M.visible(name, path)
  local set = M.by_name[name]
  if not set then return false end
  if set.expires and set.expires < today() then return false end
  if not set.files then return true end
  if not path or path == '' then return false end
  for _, g in ipairs(set.files) do
    local rel = g[1] == '/' and path:sub(2) or vim.fs.relpath(g[1], path)
    local ok, pat = pcall(vim.glob.to_lpeg, g[2])
    if rel and ok and pat:match(rel) then return true end
  end
  return false
end

local function path_of(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= '' then return nil end
  local name = vim.api.nvim_buf_get_name(buf)
  return name ~= '' and vim.fs.normalize(vim.fn.fnamemodify(name, ':p')) or nil
end

--- The sets offered in buffer `buf` (default: current), in order: those for this file
--- first, then the general ones. Sets for other files and expired ones are left out.
function M.list(buf)
  local path = path_of(buf)
  local own, general = {}, {}
  for _, n in ipairs(M.order) do
    if M.visible(n, path) then
      table.insert(M.by_name[n].files and own or general, n)
    end
  end
  return vim.list_extend(own, general)
end

--- On entering `buf`: a set made for this file becomes the current one (unless it says
--- `auto = false`); leaving for a file without one brings back the set used before.
--- Returns true if the current set changed.
function M.focus(buf)
  local path = path_of(buf)
  -- only on arriving in another file: a set you picked by hand here stays
  if not path or path == M.focused then return false end
  M.focused = path
  local cur = M.by_name[M.current]
  local here
  for _, n in ipairs(M.order) do
    local set = M.by_name[n]
    if set.files and set.auto and M.visible(n, path) then
      here = n
      break
    end
  end
  if cur and cur.files and M.visible(M.current, path) then return false end -- already on one for here
  if here then
    if not (cur and cur.files) then M.general = M.current end
    M.current = here
    return true
  end
  if cur and (cur.files or not M.visible(M.current, path)) then
    local back = M.general and M.visible(M.general, path) and M.general or M.list(buf)[1]
    if back and back ~= M.current then
      M.current = back
      return true
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
  local list = M.list()
  if #list == 0 then return end
  local idx = 1
  for i, n in ipairs(list) do
    if n == M.current then idx = i end
  end
  M.current = list[((idx - 1 + (step or 1)) % #list) + 1]
  return M.current
end

return M
