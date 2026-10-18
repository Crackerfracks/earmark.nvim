-- Shared setup for tests: a child Neovim with earmark set up in a temp project.
local H = {}

H.eq = MiniTest.expect.equality

--- New child + test set whose cases each start from a fresh child with earmark set up.
--- `setup_opts` is a Lua expression string merged into the setup() options.
function H.new_set(child, setup_opts, extra)
  return MiniTest.new_set(vim.tbl_extend('force', {
    hooks = {
      pre_case = function()
        child.restart({ '-u', 'scripts/minimal_init.lua' })
        child.o.lines, child.o.columns = 30, 100
        child.lua(([[
          _G.tmp = vim.fn.tempname()
          _G.root = _G.tmp .. '/proj'
          vim.fn.mkdir(_G.root .. '/.earmark', 'p')
          vim.g.mapleader = ' '
          vim.g.maplocalleader = ','
          local opts = vim.tbl_deep_extend('force', { storage_dir = _G.tmp .. '/data', debounce_ms = 10 }, %s)
          require('earmark').setup(opts)
          _G.texts = function()
            local out = {}
            for _, x in ipairs(require('earmark').list(0)) do
              local a = x.annotation
              local text = x.s and table.concat(vim.api.nvim_buf_get_text(0, x.s[1], x.s[2], x.e[1], x.e[2], {}), '\n') or nil
              out[#out + 1] = { text = text, label = a.values[1].label, status = a.status }
            end
            return out
          end
          _G.open = function(rel, lines)
            local path = _G.root .. '/' .. rel
            if lines then vim.fn.mkdir(vim.fs.dirname(path), 'p'); vim.fn.writefile(lines, path) end
            vim.cmd('edit ' .. vim.fn.fnameescape(path))
            return path
          end
          _G.floats = function()
            local out = {}
            for _, w in ipairs(vim.api.nvim_list_wins()) do
              local c = vim.api.nvim_win_get_config(w)
              if c.relative ~= '' then
                local b = vim.api.nvim_win_get_buf(w)
                out[#out + 1] = { win = w, buf = b, config = c, lines = vim.api.nvim_buf_get_lines(b, 0, -1, false),
                  name = vim.api.nvim_buf_get_name(b) }
              end
            end
            return out
          end
        ]]):format(setup_opts or '{}'))
      end,
      post_once = child.stop,
    },
  }, extra or {}))
end

H.LINES = { 'The quick brown fox jumps over the lazy dog.', 'A second line with some words.', 'Third line: the end.' }

function H.helpers(child)
  local h = {}
  function h.open(lines, rel)
    return child.lua_get('_G.open(...)', { rel or 'notes/doc.md', lines or H.LINES })
  end
  function h.texts()
    return child.lua_get('_G.texts()')
  end
  function h.cursor(row, col)
    child.api.nvim_win_set_cursor(0, { row, col })
  end
  function h.settle(ms)
    child.lua(('vim.wait(%d, function() return false end)'):format(ms or 80))
  end
  function h.floats()
    return child.lua_get('_G.floats()')
  end
  function h.ids()
    return child.lua_get('vim.tbl_map(function(x) return x.annotation.id end, require("earmark").list(0))')
  end
  return h
end

return H
