local H = dofile('tests/helpers.lua')
local child = MiniTest.new_child_neovim()
local eq = H.eq

local T = H.new_set(child)

local function read(path)
  return table.concat(vim.fn.readfile(path), '\n')
end

local function missing(text, words)
  return vim.tbl_filter(function(w)
    return not text:find(w, 1, true)
  end, words)
end

local function default_keys()
  return child.lua_get([[(function()
    local out = {}
    for _, lhs in pairs(require('earmark.config').defaults.keys) do out[#out + 1] = lhs end
    table.sort(out)
    return out
  end)()]])
end

T['every default key is documented'] = function()
  local keys = default_keys()
  eq(missing(read('README.md'), keys), {})
  eq(missing(read('doc/earmark.txt'), keys), {})
end

T['every subcommand is documented'] = function()
  local cmds = child.lua_get('require("earmark.actions").commands()')
  eq(#cmds > 20, true)
  local readme = read('README.md')
  local listed = {}
  for item in readme:match('`:Earmark {([^}]*)}'):gmatch('[^|]+') do
    listed[#listed + 1] = item:match('^%S+')
  end
  eq(missing('\n' .. table.concat(listed, '\n') .. '\n', vim.tbl_map(function(c) return '\n' .. c .. '\n' end, cmds)), {})
  local doc = read('doc/earmark.txt'):match('%*:Earmark%*(.-)\n====')
  eq(missing(doc:gsub('[^%w_]', ' ') .. ' ', vim.tbl_map(function(c) return ' ' .. c .. ' ' end, cmds)), {})
end

T['every <Plug> mapping is in the README'] = function()
  local plugs = child.lua_get([[vim.tbl_map(function(a) return '(earmark-' .. a.name:gsub('_', '-') .. ')' end,
    vim.tbl_filter(function(a) return a.modes end, require('earmark.actions').list))]])
  eq(missing(read('README.md'), plugs), {})
end

T['the help file has valid tags'] = function()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  vim.fn.writefile(vim.fn.readfile('doc/earmark.txt'), dir .. '/earmark.txt')
  local ok, err = pcall(vim.cmd, 'helptags ' .. vim.fn.fnameescape(dir))
  eq(ok or err, true)
  local tags = vim.fn.readfile(dir .. '/tags')
  eq(#tags > 50, true)
  -- every |link| points at a tag in this file or in Neovim's own help
  local own = {}
  for _, l in ipairs(tags) do
    own[l:match('^[^\t]+')] = true
  end
  local bad = {}
  for link in read('doc/earmark.txt'):gmatch('|([^|%s]+)|') do
    if not own[link] and #vim.fn.getcompletion(link, 'help') == 0 then bad[#bad + 1] = link end
  end
  eq(bad, {})
end

T[':checkhealth earmark reports without errors'] = function()
  child.cmd('checkhealth earmark')
  local text = table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  eq(text:find('earmark: storage', 1, true) ~= nil, true)
  eq(text:find('storage_dir is writable', 1, true) ~= nil, true)
  eq(text:find('ERROR', 1, true), nil)
end

return T
