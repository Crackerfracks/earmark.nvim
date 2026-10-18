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
    clear = '<leader>mX', -- erase everything in the buffer (restorable)
    restore = '<leader>mu', -- restore the most recently erased
    next = '<leader>mn',
    prev = '<leader>mN',
    cycle_set = '<leader>ms',
    peek = '<leader>mi', -- show the hover now and enter it (scroll, q closes)
    note = '<leader>mm', -- open/close the note of the annotation under the cursor
    toggle_hover = '<leader>mh',
    relabel = '<leader>ml', -- change the label of the annotation under the cursor
    add_value = '<leader>ma', -- add another label to it
    rename = '<leader>mr', -- name its label for this file (empty input clears)
  },
  -- The label prompt (`gh` without a count).
  prompt = {
    width = 44,
    max_rows = 8, -- candidate rows shown under the input
    -- Ask for a name after choosing a label: 'first_use' (a numbered label with no name in
    -- this file, the project or your history), 'always', or 'never'.
    ask_name = 'first_use',
  },
  ui = {
    border = 'rounded', -- any 'winborder' value
  },
  -- The note editor (`<leader>mm`).
  note = {
    layout = 'float', -- 'float' | 'split' (,s / ,f switch while editing)
    width = 0.6, -- at most this fraction of the window width ...
    max_width = 100, -- ... and this many columns
    height = { min = 5, max = 0.5 },
    winblend = 0,
  },
  -- The hover shown when the cursor rests on an annotation.
  hover = {
    auto = true, -- `<leader>mh` toggles
    delay = 120, -- ms after the cursor stops
    -- 'named_or_note': only for annotations with a name, note, tags, extra labels or a
    -- stale/ambiguous status; 'always': for every annotation
    show_when = 'named_or_note',
    max_width = 0.5, -- fractions of the window
    max_height = 0.5,
  },
  overlap = {
    -- 'blend': where annotations overlap, draw the mix of their colours underlined in the
    -- outer one's colour. 'top': the smallest span simply covers the others.
    style = 'blend',
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
