local M = {}

M.defaults = {
  -- Label sets. Strings are numbered palettes (keys 1-99): 'vivid', 'pastel', 'earth',
  -- 'metal', 'cyber'. Named entries are custom sets:
  --   feedback = { labels = { { key = 'c', name = 'contradiction', color = '#e06c75' }, ... } }
  --   mine     = { generate = 'numbered', palette = { L = 0.7, C = 0.15, h0 = 200, zig = 0.04 } }
  sets = { 'vivid', 'pastel', 'earth', 'metal', 'cyber' },
  -- Directory of your own set files (one set per *.lua / *.json file), false to skip.
  -- Default: ~/.config/earmark/sets. Projects add <root>/.earmark/sets.
  sets_dir = nil,
  -- Label the prompt offers first before you've used any, e.g. 'vivid/3' or 'review/q1'.
  default_label = nil,
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
    pick_set = '<leader>mS',
    peek = '<leader>mi', -- show the hover now and enter it (scroll, q closes)
    note = '<leader>mm', -- open/close the note of the annotation under the cursor
    toggle_hover = '<leader>mh',
    toggle_indicators = '<leader>mv',
    tags = '<leader>mt', -- add/remove tags of the annotation under the cursor
    next_same = '<leader>m]', -- next/previous with the label under the cursor
    prev_same = '<leader>m[',
    jump = '<leader>mj', -- jump labels on annotations (flash.nvim; else the picker)
    pick = '<leader>mp', -- annotations in this file
    pick_all = '<leader>mP', -- annotations in the project
    review = '<leader>md', -- stale, ambiguous and detached annotations
    diff = '<leader>mD', -- original vs current text of the annotation under the cursor
    export = '<leader>me', -- Markdown export of this file's annotations
    occurrences = '<leader>mo', -- annotate every other occurrence of the text under the cursor
    regrow = '<leader>mg', -- <leader>mg{motion}: move the annotation under the cursor onto the motion
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
  -- Indicators at the end of the line an annotation ends on: a pencil per note, its #tags
  -- and [identifiers], in the label's colour. Lines too long for them get them on a
  -- virtual line below.
  indicators = {
    mode = 'eol', -- 'eol' | 'none' (`<leader>mv` toggles)
    max_pencils = 3, -- then "+N"
    identifiers = true, -- show @ident tags as [ident]
    show_empty = false, -- a dot for annotations without a note
  },
  overlap = {
    -- 'blend': where annotations overlap, draw the mix of their colours underlined in the
    -- outer one's colour. 'top': the smallest span simply covers the others.
    style = 'blend',
  },
  export = {
    group_by = 'label', -- 'label' | 'position' | 'tag' | 'time'
    include_detached = true,
    format = nil, -- function(list, ctx) -> lines, replaces the body
  },
  statusline = {
    digits = true, -- numbered sets: show 1234567890 in the set's colours
  },
  -- 'auto' (snacks, then telescope, then vim.ui.select), 'snacks', 'telescope' or 'select'
  picker = 'auto',
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
