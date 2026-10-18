-- Tags: explicit ones stored on an annotation, plus `#tag` and `@ident` written in its note.
local M = {}

--- Tags and identifiers written in a note: `#tag` (not a Markdown heading) and `@ident`.
--- Text inside fenced code blocks and inline code is ignored.
--- Returns { tags = { 'a', ... }, idents = { 'A', ... } } in order of appearance, unique.
function M.parse(note)
  local out = { tags = {}, idents = {} }
  if not note or note == '' then return out end
  local seen_t, seen_i = {}, {}
  local fenced = false
  for line in (note .. '\n'):gmatch('(.-)\n') do
    if line:match('^%s*```') or line:match('^%s*~~~') then
      fenced = not fenced
    elseif not fenced then
      line = line:gsub('`[^`]*`', '')
      -- "# Heading" is not a tag: a tag is "#" directly followed by a letter
      for pre, tag in (' ' .. line):gmatch('([^%w_&/#])#(%a[%w_/%-%.]*)') do
        tag = tag:gsub('[%.%-/]+$', '')
        if pre and not seen_t[tag] then
          seen_t[tag] = true
          out.tags[#out.tags + 1] = tag
        end
      end
      for pre, id in (' ' .. line):gmatch('([^%w_%.])@(%w[%w_%-]*)') do
        id = id:gsub('%-+$', '')
        if pre and not seen_i[id] then
          seen_i[id] = true
          out.idents[#out.idents + 1] = id
        end
      end
    end
  end
  return out
end

--- All tags of an annotation: explicit ones first, then the note's. Identifiers separately.
--- Returns tags, idents.
function M.of(a)
  local parsed = M.parse(a.note)
  local list, seen = {}, {}
  for _, src in ipairs({ a.tags or {}, parsed.tags }) do
    for _, t in ipairs(src) do
      if not seen[t] then
        seen[t] = true
        list[#list + 1] = t
      end
    end
  end
  return list, parsed.idents
end

--- Tags you have used anywhere: { { name = 'todo', count = 4 }, ... }, most used first.
local function path()
  return require('earmark.config').options.storage_dir .. '/tags.json'
end

function M.known()
  local t = require('earmark.store').read_json(path())
  local out = {}
  for name, n in pairs(type(t.counts) == 'table' and t.counts or {}) do
    out[#out + 1] = { name = name, count = n }
  end
  table.sort(out, function(x, y)
    if x.count ~= y.count then return x.count > y.count end
    return x.name < y.name
  end)
  return out
end

--- Count each of `list` as used once more (newly added to an annotation).
function M.remember(list)
  if not list or #list == 0 then return end
  local store = require('earmark.store')
  local t = store.read_json(path())
  t.counts = type(t.counts) == 'table' and t.counts or {}
  for _, name in ipairs(list) do
    t.counts[name] = (t.counts[name] or 0) + 1
  end
  store.write_json(path(), t)
end

--- Tags in `new` that are not in `old`.
function M.added(old, new)
  local had = {}
  for _, t in ipairs(old or {}) do
    had[t] = true
  end
  return vim.tbl_filter(function(t)
    return not had[t]
  end, new or {})
end

return M
