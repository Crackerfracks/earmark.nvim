# earmark.nvim

Highlight and label spans of text in Neovim, and keep those annotations attached to the
text, even while the text keeps changing.

- **Labels come from sets.** The default sets are five generated palettes with keys 1–99,
  and you can define your own.
- **A count picks the label:** `3ghiw` marks a word with label 3.
- **Annotations survive what usually breaks highlights:** live edits, formatters
  rewriting the buffer, `:e!`, edits made outside Neovim, renamed files, and undo.
  - When the annotated text is rewritten, the annotation is marked **stale**.
  - When the text is deleted, it is **detached**, never dropped. It comes back if the text
    returns (undo, paste).
- **Plain JSON storage** inside your project (`<root>/.earmark/`), so annotations travel
  with the repo or notebook.

Status: early. Notes, the label prompt, project label-set files and pickers are next.
See the plan in `~/Documents/Everything Neovim-related/NumHi Context Corner/2026-10 Rebuild Plan.md`.

Requires Neovim 0.11+ (uses `getregionpos`, `vim.fs.root`, `vim.fs.relpath`).

## Install (lazy.nvim)

```lua
{ 'you/earmark.nvim', opts = {} }
```

## Use

| Keys | Action |
|---|---|
| `{count}gh{motion}` | annotate the motion with label `{count}` of the current set (`3ghiw`, `12gh$`, `ghap`) |
| `{count}ghh` | annotate the line |
| `{Visual}{count}gh` | annotate the selection (block selections: one annotation per line) |
| `gh` without a count | reuse the last label |
| `.` | repeat with the same label |
| `<leader>mx` | erase annotation under cursor (Visual: all in selection) |
| `<leader>mX` | erase every annotation in the buffer (restorable) |
| `<leader>mu` | restore the most recently erased |
| `<leader>mn` / `<leader>mN` | next / previous annotation |
| `<leader>ms` | switch to the next label set |
| `<leader>mi` | show label, status and original text under cursor |

Annotating exactly the same span again changes its label. Overlapping annotations stack,
with smaller spans drawn on top.

`:Earmark {info|erase|clear|restore|next|prev|cycle_set|set [name]|reload|log}`

`:Earmark log` shows recent warnings and errors (also written to `<storage_dir>/earmark.log`).

## Configure

Defaults:

```lua
require('earmark').setup({
  -- Strings are generated numbered palettes; named tables are your own sets.
  sets = { 'vivid', 'pastel', 'earth', 'metal', 'cyber' },
  current = nil, -- set a count resolves against (default: first)
  root_markers = { '.earmark', '.zk', '.git' },
  storage_dir = vim.fn.stdpath('data') .. '/earmark', -- files outside any root, scratch buffers
  stale_threshold = 0.6, -- similarity to the original text below which an annotation is stale
  context = 32, -- bytes of surrounding text remembered on each side
  keys = { -- false disables all defaults; any entry can be false too
    operator = 'gh', line = 'ghh',
    erase = '<leader>mx', clear = '<leader>mX', restore = '<leader>mu',
    next = '<leader>mn', prev = '<leader>mN',
    cycle_set = '<leader>ms', info = '<leader>mi',
  },
})
```

Your own sets:

```lua
sets = {
  'vivid',
  feedback = { labels = {
    { key = 'c', name = 'contradiction', color = '#e06c75' },
    { key = 'v', name = 'vague' },          -- colour picked automatically
    'cut this',                              -- key defaults to its position: 3
  } },
  mine = { generate = 'numbered', palette = { L = 0.7, C = 0.15, h0 = 200, zig = 0.04 } },
},
```

A count resolves to the label whose key is that number, else to the label at that position.

`<Plug>` mappings: `(earmark-operator)`, `(earmark-line)`, `(earmark-erase)`,
`(earmark-restore)`, `(earmark-next)`, `(earmark-prev)`, `(earmark-cycle-set)`, `(earmark-info)`.

## Storage

- **File inside a project:** `<root>/.earmark/docs/<relative path>.json`, where `<root>` is
  the nearest directory containing one of `root_markers`.
- **Other files:** `<storage_dir>/files/<absolute path>.json`.
- **Scratch, unnamed and plugin buffers:** `<storage_dir>/scratch/<id>.json`.

Each record (schema v2) holds the annotations, their notes and tags, the names you gave
labels in that document, and a fingerprint of the text they were recorded against. That
text itself is kept beside it as a snapshot (`<base>/snap/…`). On load, the snapshot is
diffed against the current text to re-anchor each annotation. Inside a project, `snap/` is
listed in an auto-written `.earmark/.gitignore`, so committed records stay small; a fresh
clone without snapshots re-anchors by quote and surrounding text instead.

Writes are atomic. A record that can't be parsed is left untouched, and saving for that
buffer is disabled with a warning. v1 records (snapshot inline) are read as is and rewritten
as v2 on the next save.

## API

```lua
local em = require('earmark')
em.annotate(buf, { row, col }, { row, col }, { set = 'vivid', label = '3' }) -- 0-based, end-exclusive
em.list(buf)  -- { { annotation = {...}, s = {r, c}, e = {r, c} }, ... }  (s/e nil when detached)
em.at(buf, pos)
```

Events: `User EarmarkChanged` for every change, plus a specific `User Earmark<Action>`
(`EarmarkAdd`, `EarmarkUpdate`, `EarmarkErase`, `EarmarkRestore`, `EarmarkRepair`,
`EarmarkNote`, `EarmarkLoad`), all with `data = { buf, action, ids }`.

## Develop

`make test` runs the mini.test suite headless. It uses your lazy.nvim copy of mini.nvim if
present, otherwise clones it into `deps/`.
