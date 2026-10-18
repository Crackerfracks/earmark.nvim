-- Draws the label sets on six editor backgrounds into an HTML page (OUT=path), for
-- docs/demos/color-adapt.png:  OUT=/tmp/s.html nvim --headless -u NONE --cmd "set rtp+=." -c "luafile docs/demos/scripts/color_adapt.lua" -c qa
local color = require('earmark.color')
require('earmark.config').setup({})
local bgs = { { 'Tokyo Night (reference)', '#1a1b26' }, { 'Black', '#000000' }, { 'Gruvbox dark', '#282828' }, { 'Solarized light', '#fdf6e3' }, { 'White', '#ffffff' }, { 'GitHub light', '#f6f8fa' } }
local out = { '<html><body style="font:14px sans-serif;margin:0">' }
for _, b in ipairs(bgs) do
  color.set_background(b[2])
  local fg = color.contrast_fg(b[2]) == '#111111' and '#333' or '#ccc'
  out[#out+1] = ('<div style="background:%s;color:%s;padding:8px 12px"><b>%s</b><br>'):format(b[2], fg, b[1])
  for _, set in ipairs({ 'vivid', 'pastel', 'earth', 'metal', 'cyber' }) do
    out[#out+1] = ('<div style="margin:3px 0"><span style="display:inline-block;width:50px">%s</span>'):format(set)
    for _, n in ipairs({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 21, 41, 61, 81 }) do
      local hex = color.adapt(color.numbered(set, n))
      out[#out+1] = ('<span style="background:%s;color:%s;padding:1px 4px;margin-right:3px;font-family:monospace">word %d</span>'):format(hex, color.contrast_fg(hex), n)
    end
    out[#out+1] = '</div>'
  end
  out[#out+1] = '</div>'
end
out[#out+1] = '</body></html>'
vim.fn.writefile({ table.concat(out, '\n') }, vim.env.OUT)
