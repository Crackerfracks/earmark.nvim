local M = {}

M.defaults = {
  -- Label sets. Strings are numbered palettes (keys 1-99): 'vivid', 'pastel', 'earth',
  -- 'metal', 'cyber'. Named entries are custom sets:
  --   feedback = { labels = { { key = 'c', name = 'contradiction', color = '#e06c75' }, ... } }
  --   mine     = { generate = 'numbered', palette = { L = 0.7, C = 0.15, h0 = 200, zig = 0.04 } }
  sets = { 'vivid', 'pastel', 'earth', 'metal', 'cyber' },
  -- Set used when a count picks a label. Defaults to the first set.
  current = nil,
  -- Where annotations are stored: `<root>/.earmark/` for the nearest root found by these
  -- markers, else `storage_dir`.
  root_markers = { '.earmark', '.zk', '.git' },
  storage_dir = vim.fn.stdpath('data') .. '/earmark',
  -- An annotation whose text drifted below this similarity to what was originally
  -- annotated is marked "stale".
  stale_threshold = 0.6,
  -- Bytes of surrounding text remembered on each side, used to re-find moved text.
  context = 32,
  -- Default keymaps. Set the whole table, or any entry, to false to disable.
  keys = {
    operator = 'gh', -- gh{motion}, {Visual}gh; a count picks the label: 3ghiw
    line = 'ghh',
    erase = '<leader>mx', -- under cursor (Normal) / in selection (Visual)
    restore = '<leader>mu', -- restore the most recently erased
    next = '<leader>mn',
    prev = '<leader>mN',
    cycle_set = '<leader>ms',
    info = '<leader>mi',
  },
  -- Buffers with these 'buftype's are never annotated.
  ignore_buftypes = { 'terminal', 'prompt', 'quickfix' },
  debounce_ms = 200,
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  opts = opts or {}
  local o = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts)
  -- lists are replaced, not merged
  if opts.sets then o.sets = opts.sets end
  if opts.root_markers then o.root_markers = opts.root_markers end
  if opts.keys == false then o.keys = false end
  M.options = o
  return o
end

return M
