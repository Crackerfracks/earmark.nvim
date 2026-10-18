-- `:checkhealth earmark`
local M = {}

local health = vim.health

local function writable(dir)
  if vim.fn.isdirectory(dir) == 0 and vim.fn.mkdir(dir, 'p') == 0 then return false end
  local probe = dir .. '/.earmark-health-' .. vim.uv.os_getpid()
  local f = io.open(probe, 'w')
  if not f then return false end
  f:close()
  os.remove(probe)
  return true
end

--- Records under `dir` that can't be read; returns the count checked and the failures.
local function bad_records(dir)
  local store = require('earmark.store')
  local n, bad = 0, {}
  for _, path in ipairs(vim.fn.globpath(dir, '**/*.json', false, true)) do
    n = n + 1
    local rec, err = store.read(path)
    if not rec then bad[#bad + 1] = err or path end
  end
  return n, bad
end

function M.check()
  local config = require('earmark.config')
  local o = config.options

  health.start('earmark: Neovim')
  if require('earmark.compat').supported() then
    health.ok('Neovim ' .. tostring(vim.version()))
  else
    health.error('Neovim 0.11 or newer is required (this is ' .. tostring(vim.version()) .. ')')
  end
  if vim.fn.exists(':Earmark') == 2 then
    health.ok('setup() has run')
  else
    health.warn('setup() has not run: call require("earmark").setup() (lazy.nvim: opts = {})')
  end

  health.start('earmark: storage')
  if writable(o.storage_dir) then
    health.ok('storage_dir is writable: ' .. o.storage_dir)
  else
    health.error('storage_dir is not writable: ' .. o.storage_dir)
  end
  -- the project of the working directory and of every buffer earmark tracks
  local roots, seen = {}, {}
  local function add_root(r, why)
    if r and not seen[r] then
      seen[r] = true
      roots[#roots + 1] = { r, why }
    end
  end
  local cwd = vim.uv.cwd()
  add_root(vim.fs.root(cwd, o.root_markers), 'working directory')
  local store = require('earmark.store')
  for buf in pairs(require('earmark.buffer').state) do
    local doc = vim.api.nvim_buf_is_valid(buf) and store.doc(buf)
    if doc and doc.root then add_root(doc.root, vim.fn.fnamemodify(doc.path, ':~:.')) end
  end
  if #roots == 0 then
    health.info(('no project root for %s (none of %s found); records go to storage_dir'):format(
      cwd, table.concat(o.root_markers, ', ')))
  end
  for _, r in ipairs(roots) do
    local root = r[1]
    health.ok(('project root %s (for %s); annotations in .earmark/'):format(vim.fn.fnamemodify(root, ':~'), r[2]))
    local n, bad = bad_records(root .. '/.earmark/docs')
    if #bad == 0 then
      health.ok(('%d record(s) there read fine'):format(n))
    else
      for _, err in ipairs(bad) do
        health.error(err, 'Fix or move the file; earmark will not save over it.')
      end
    end
  end

  health.start('earmark: label sets')
  local sets = require('earmark.sets')
  if #sets.order > 0 then
    health.ok(('%d set(s): %s'):format(#sets.order, table.concat(sets.order, ', ')))
  else
    health.warn('no label sets loaded')
  end
  for path, err in pairs(sets.errors) do
    health.error(('%s: %s'):format(path, err))
  end

  health.start('earmark: optional plugins')
  local optional = {
    { 'snacks', 'snacks.nvim', 'picker' },
    { 'telescope', 'telescope.nvim', 'picker' },
    { 'flash', 'flash.nvim', '<leader>mj jump labels' },
    { 'which-key', 'which-key.nvim', '<leader>m group name' },
  }
  for _, p in ipairs(optional) do
    if pcall(require, p[1]) then
      health.ok(('%s found (%s)'):format(p[2], p[3]))
    else
      health.info(('%s not found (%s)'):format(p[2], p[3]))
    end
  end
  health.info('picker = ' .. o.picker .. (o.picker == 'auto' and ' (snacks, then telescope, then vim.ui.select)' or ''))
  if vim.g.have_nerd_font == false then
    health.info('vim.g.have_nerd_font = false: plain fallback icons are used')
  end

  health.start('earmark: zk')
  local cmd = o.zk.cmd or 'zk'
  if vim.fn.executable(cmd) == 1 then
    local ok, res = pcall(function()
      return vim.system({ cmd, '--version' }, { text = true }):wait(3000)
    end)
    local version = ok and res.code == 0 and vim.trim(res.stdout or '') or 'version unknown'
    health.ok(('%s found (%s)'):format(cmd, version))
  else
    health.info('zk not found (Arch: sudo pacman -S zk); <leader>mz needs it to make notes')
  end
  -- the file you ran :checkhealth from, else the working directory
  local alt = vim.fn.bufnr('#')
  local file = alt > 0 and vim.bo[alt].buftype == '' and vim.api.nvim_buf_get_name(alt) or ''
  local where = file ~= '' and file or vim.uv.cwd()
  local nb, err = require('earmark.zk').notebook(where)
  local label = vim.fn.fnamemodify(where, ':~:.')
  if nb then
    health.ok(('notebook for %s: %s'):format(label, vim.fn.fnamemodify(nb, ':~')))
  else
    health.info(('%s: %s'):format(label, err))
  end
end

return M
