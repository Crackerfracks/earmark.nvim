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

return M
