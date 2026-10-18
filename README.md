# earmark.nvim

Highlight and label spans of text in Neovim, and keep those annotations attached to the
text, even while the text keeps changing.

![3ghiw marks a word with label 3; 12gh$ marks to the end of the line](docs/demos/annotate-count.gif)
![Overlapping annotations: the hover lists them innermost first](docs/demos/hover-overlap.gif)

Every feature, with clips and the keys to try: [docs/demos/index.html](docs/demos/index.html).

- **Labels come from sets.** The default sets are five generated palettes with keys 1–99,
  and you can define your own.
- **A count picks the label:** `3ghiw` marks a word with label 3.
- **No count opens a small prompt** next to the text: type a key, a name or part of one,
  see the colour live on the text, press Enter. Tab names the label as you go.
- **Annotations survive what usually breaks highlights:** live edits, formatters
  rewriting the buffer, `:e!`, edits made outside Neovim, renamed files, and undo.
  - Changing its first or last words (`cw`, `ciw`, `s`, `C` …) keeps the new words in it.
  - When the annotated text is rewritten, the annotation is marked **stale**.
  - When the text is deleted, it is **detached**, never dropped. It comes back if the text
    returns (undo, paste).
- **Plain JSON storage** inside your project (`<root>/.earmark/`), so annotations travel
  with the repo or notebook.

Requires Neovim 0.11+. Full reference: `:help earmark`. Something off? `:checkhealth earmark`.

## Install (lazy.nvim)

```lua
{ 'Crackerfracks/earmark.nvim', opts = {} }
```

From a local checkout (how Stephen's config should load it while it's private):

```lua
{
  dir = '~/Projects/earmark.nvim',
  name = 'earmark.nvim',
  lazy = false, -- it must see the buffers Neovim starts with, and own `gh` from the start
  opts = {
    -- default_label = 'vivid/3',
    -- prompt = { ask_name = 'always' },
  },
}
```

## Quickstart (60 seconds)

1. Put the cursor on a word and type `3ghiw`. The word gets label 3 of the current set.
2. Type `ghip` without a count: a prompt opens beside the paragraph. Type `12`, watch the
   colour change on the text, press `<CR>`.
3. Press `<leader>mm` on an annotation and write a note with a `#tag` in it. `q` saves.
4. Rest the cursor on it: the hover shows the label, its name, the tag and the note.
5. `<leader>mp` lists every annotation in the file; `<leader>md` lists the ones whose text
   changed or disappeared.

`make demo` writes a small annotated project to `/tmp/earmark-demo` and prints the command
that opens it with this checkout, if you want to look before touching your config.

## Use

| Keys | Action |
|---|---|
| `{count}gh{motion}` | annotate the motion with label `{count}` of the current set (`3ghiw`, `12gh$`, `ghap`) |
| `{count}ghh` | annotate the line |
| `{Visual}{count}gh` | annotate the selection (block selections: one annotation per line) |
| `gh{motion}` without a count | open the label prompt (see below) |
| `.` | repeat with the same label, no prompt |
| `<leader>ml` | change the label of the annotation under cursor (`{count}` picks among overlaps) |
| `<leader>ma` | add another label to the annotation under cursor |
| `<leader>mr` | name (or rename) the label of the annotation under cursor |
| `<leader>mx` | erase annotation under cursor (Visual: all in selection) |
| `<leader>mX` | erase every annotation in the buffer (restorable) |
| `<leader>mu` | restore the most recently erased |
| `<leader>mn` / `<leader>mN` | next / previous annotation (wraps; `{count}` skips) |
| `<leader>m]` / `<leader>m[` | next / previous with the same label as the one under cursor |
| `<leader>mj` | jump labels on every visible annotation ([flash.nvim](https://github.com/folke/flash.nvim); without it, the picker) |
| `<leader>mp` / `<leader>mP` | pick an annotation in this file / in the whole project |
| `<leader>md` | review the annotations whose text changed or disappeared |
| `{Visual}<leader>mR` | attach the annotation chosen in the review list to the selection |
| `<leader>mq` | this file's annotations into the quickfix list |
| `<leader>mD` | compare an annotation's original text with what it says now |
| `<leader>me` | export this file's annotations to Markdown (asks where; opens it in a split) |
| `<leader>mo` | give every other occurrence of the annotated text the same labels |
| `<leader>mz` | promote the annotation under cursor to a zk note ([zk-nvim](https://github.com/zk-org/zk-nvim)) |
| `<leader>mg{motion}` / `{Visual}<leader>mg` | move the annotation under cursor onto the motion / selection (note and labels stay) |
| `<leader>mc` | the palette: every label of the set as a big colour patch with your name for it, its colour's name, hex and uses; `<CR>` makes it the label `gh` offers first, digits jump to a key, `r` names it, `<Tab>` switches sets |
| `<leader>ms` | switch to the next label set (a popup shows its colours) |
| `<leader>mS` | choose the label set from a list |
| `<leader>mm` | open / close the note of the annotation under cursor (`{count}` picks among overlaps) |
| `<leader>mi` | show the details float now and enter it (scroll; `q` closes) |
| `<leader>mh` | automatic hover on / off |
| `<leader>mt` | add / remove tags of the annotation under cursor (list of every tag you've used) |
| `<leader>mv` | show / hide `#tags` at the ends of lines (hidden at startup) |

### The label prompt

`gh` without a count opens a one-line prompt beside the span. The span shows the selected
colour while you type, and the list under the input narrows as you go:

- digits match keys first, then the shades of that family (`3` → 3, 13, 23 …);
- anything else matches keys, then label names (fuzzy);
- empty input offers the last label, then the labels already used in this file.

Each row shows the label's colour, its key, your name for it and the colour's name
("Tangerine"). With a count (`3gh`) there's no prompt; a small hint under the cursor shows
which label the count picked while you type the motion (`prompt.count_hint`).

### Colour names

Every colour gets a human name: the nearest of about 700 names from the
[xkcd colour survey](https://xkcd.com/color/rgb/) (public domain), measured in OKLab, a
perceptual colour space. Labels of one set get distinct names, so two shades of one
family never both read "Coral". The names show in the prompt, the palette, the hover and,
for a label you haven't named, the statusline. `color_names = false` hides them; a
function `color_names = function(hex) return name end` supplies your own (return nil to
fall back), and a set's label can carry `color_name = '…'`.

### Light and dark colour schemes

The label colours are designed on a dark background. On any other background earmark
shifts each colour's lightness (keeping its hue) so it stands out from the page as much as
it does on dark: on a light theme a highlight sits a little darker than the page instead
of brighter, so it keeps the same weight. It follows `:colorscheme` and `'background'`
changes as they happen. The label itself doesn't change (its number, name, colour name and
hex stay the same); only how it's drawn does. `color_adapt = false` draws the exact colours.

| In the prompt | |
|---|---|
| `<CR>` | apply the selected label |
| `<Tab>` | like `<CR>`, then name the label (the name stage); `<Tab>`/`<CR>` there accepts the name |
| `<S-Tab>` | back to the label stage |
| `<C-n>` `<C-p>` / `<Down>` `<Up>` (Normal: `j` `k`) | move through candidates |
| `<C-s>` | try the next label set |
| `<Esc>` | Normal mode (edit the query with the usual motions); `<Esc>`/`q` again cancels. In the name stage after choosing a label, `<Esc>` applies the label without naming it |

Names are per file, and the project remembers them: once you name label 3 "vague" in one
file, the first label 3 you use in any other file of that project is called "vague" there
too (`<root>/.earmark/names.json`, the directory default). Rename or clear it in that file
with `<leader>mr`. The name stage is pre-filled from what you called the label before: in
this file, then elsewhere in the project, then anywhere (`<storage_dir>/names.json`). An
empty name clears it for this file. With `prompt.ask_name = 'first_use'` (default) you are
asked to name a numbered label the first time you use it in a project; `'always'` and
`'never'` do what they say.

Annotating exactly the same span again with another label asks first: <kbd>a</kbd> (or
<kbd>Enter</kbd>) adds the label to it, so both show as an overlap; <kbd>r</kbd> replaces its
label (as `<leader>ml` does); <kbd>Esc</kbd> cancels. `.` repeats your answer without asking.
`prompt.confirm_stack = false` always adds, without asking. With a label it already has,
nothing changes.

### Notes and the hover

`<leader>mm` opens the annotation's note, a Markdown buffer in a float right under the
span (an empty note starts in Insert mode). `q`, `:w`, `<C-s>`, leaving the float or
closing it any other way saves it; `,s` moves it to a split at the bottom and `,f` back
(`,` being your `maplocalleader`). Clearing all the text removes the note. Write `#tags`
and `@identifiers` anywhere in a note; earmark picks them up.

When the cursor rests on an annotation that has a name, a note, tags, extra labels or a
stale/ambiguous status, a small float shows all of that without taking focus. It stays
while you move inside the annotation and goes away when you leave it, type, scroll or start
an operator. Overlapping annotations are listed innermost first (①, ②, …). Set
`hover.show_when = 'always'` to see it on every annotation.

### Finding annotations

`<leader>mp` and `<leader>mP` open your picker ([snacks.nvim](https://github.com/folke/snacks.nvim),
then [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim), else `vim.ui.select`;
set `picker` to force one). Each entry shows the label name, the text, tags and the first
line of the note, so typing `#todo` or part of a note narrows it. The commands take a query
up front:

```vim
:Earmark pick #todo status:stale
:Earmark pick_all label:3 has:note budget
:Earmark qf all #source          " into the quickfix list instead
```

Query words: `#tag`, `@ident`, `label:<key or name>`, `set:<name>`, `status:ok|stale|ambiguous|detached`,
`has:note`, `has:tags`; anything else matches the text, name or note.

`<leader>md` lists annotations that are **stale** (their text was rewritten),
**ambiguous** (the text appears more than once) or **detached** (the text is gone). For each
one you can jump to it, compare the original with the current text, accept the current text,
move it to one of the places its text could be now (exact or close matches, scored), attach
it to a selection (`{Visual}<leader>mR`), or erase it.

`:Earmark scratch` reopens a scratch buffer you annotated earlier, with its text and
annotations.

### Export

`<leader>me` writes a Markdown file with every annotation, grouped by label (with your
names for them), each with its text, line numbers, tags and note, plus a **Detached** section
for annotations whose text is gone. Inside a project it suggests
`<root>/.earmark/export/<project>-<path-of-file>.md` (`export/` is gitignored). Set
`export.group_by` to `'position'`, `'tag'` or `'time'`, or `export.format` to a function
`(list, ctx) -> lines` to write your own body. `:Earmark color #rrggbb` (or `reset`)
recolours the label under the cursor in this file only.

### Indicators

At the end of the line an annotation ends on, earmark shows a `✎` for each note (`✎✎✎ +2`
past three), in the label's colour. `<leader>mv` adds its `#tags` and its `@identifiers` as
`[A]` (hidden when Neovim starts; `indicators.tags = true` shows them from the start). When
the line is too long for them, they go on a virtual line below it instead. Nothing goes in
the sign column, and toggling changes only the view: nothing is re-read or saved.
`indicators.show_empty = true` adds a dot for annotations without a note;
`indicators.mode = 'none'` shows nothing at all.

### What overlaps look like

- Where annotations of **different labels** overlap, the overlap is drawn in the mix of their
  colours and underlined in the outer annotation's colour, so you see where each one starts
  and ends.
- Where annotations of **the same label** are nested (`this is` with `is` marked again), the
  inner part keeps the colour and gets an underline in the text colour; three levels deep
  it's a double underline.
- An annotation's **second label** is an undercurl in that label's colour; labels **3 and
  up** show as small squares `■` right after the span (`#` when `vim.g.have_nerd_font` is
  `false`).
- **Stale** annotations (text rewritten) are underdashed; **ambiguous** ones underdotted.

Set `overlap = { style = 'top' }` to turn the mixing off: the smallest span is drawn on
top.

`:Earmark {info|peek|note|tags|toggle_hover|toggle_indicators|erase|clear|restore|next|prev|next_same|prev_same|jump|pick|pick_all|review|diff|reanchor|qf|scratch|check|export|occurrences|zk|palette [set]|color|cycle_set|pick_set|relabel|add_value|rename|set [name]|reload|log}`

`:Earmark info` (the default) prints the details of the annotations under the cursor.

`:Earmark log` shows recent warnings and errors (also written to `<storage_dir>/earmark.log`).

## Configure

Defaults:

```lua
require('earmark').setup({
  -- Strings are generated numbered palettes; named tables are your own sets.
  sets = { 'vivid', 'pastel', 'earth', 'metal', 'cyber' },
  sets_dir = nil, -- your set files; default ~/.config/earmark/sets, false to skip
  default_label = nil, -- offered first before you've used any label, e.g. 'vivid/3'
  current = nil, -- set a count resolves against (default: first)
  root_markers = { '.earmark', '.zk', '.git' },
  storage_dir = vim.fn.stdpath('data') .. '/earmark', -- files outside any root, scratch buffers
  stale_threshold = 0.6, -- similarity to the original text below which an annotation is stale
  context = 32, -- bytes of surrounding text remembered on each side
  keys = { -- false disables all defaults; any entry can be false too
    operator = 'gh', line = 'ghh',
    erase = '<leader>mx', clear = '<leader>mX', restore = '<leader>mu',
    next = '<leader>mn', prev = '<leader>mN',
    cycle_set = '<leader>ms', pick_set = '<leader>mS', peek = '<leader>mi',
    note = '<leader>mm', toggle_hover = '<leader>mh',
    tags = '<leader>mt', toggle_indicators = '<leader>mv',
    next_same = '<leader>m]', prev_same = '<leader>m[', jump = '<leader>mj',
    pick = '<leader>mp', pick_all = '<leader>mP', review = '<leader>md', diff = '<leader>mD',
    reanchor = '<leader>mR', qf = '<leader>mq',
    export = '<leader>me', occurrences = '<leader>mo', regrow = '<leader>mg', zk = '<leader>mz',
    relabel = '<leader>ml', add_value = '<leader>ma', rename = '<leader>mr',
    palette = '<leader>mc',
  },
  prompt = {
    width = 44, -- inner width of the prompt float
    max_rows = 8, -- candidate rows shown
    ask_name = 'first_use', -- 'first_use' | 'always' | 'never'
    count_hint = true, -- after 3gh, show which label the count picked
    confirm_stack = true, -- ask before labelling a span that's already labelled
  },
  ui = { border = 'rounded' },
  picker = 'auto', -- 'auto' | 'snacks' | 'telescope' | 'select'
  statusline = { digits = true, color_name = true },
  color_names = true, -- false, or function(hex) -> name|nil
  color_adapt = true, -- shift colours to suit a light (or any other) colour scheme
  export = { group_by = 'label', include_detached = true, format = nil },
  zk = { dir = nil, open = true },
  note = {
    layout = 'float', -- 'float' | 'split'
    width = 0.6, max_width = 100, -- fraction of the window, and a column cap
    height = { min = 5, max = 0.5 },
    winblend = 0,
  },
  hover = {
    auto = true, -- show when the cursor rests on an annotation (<leader>mh toggles)
    delay = 120, -- ms
    show_when = 'named_or_note', -- or 'always'
    max_width = 0.5, max_height = 0.5,
  },
  indicators = {
    mode = 'eol', -- 'eol' | 'none'
    tags = false, -- #tags and [identifiers] too (<leader>mv toggles)
    max_pencils = 3, -- then "+N"
    identifiers = true, -- show @ident tags as [ident]
    show_empty = false,
  },
  overlap = { style = 'blend' }, -- 'blend' | 'top'
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

### Label set files

Sets can also live in files, one set per file, named after the file:

- your own: `~/.config/earmark/sets/*.lua` or `*.json` (`sets_dir` changes or disables this);
- a project's: `<root>/.earmark/sets/*.lua` or `*.json`, loaded when you open a file in that
  project. A project's set replaces a set of the same name.

Files are re-read when you save them in Neovim or come back to Neovim after editing them
elsewhere. Project Lua files run only after you trust them (`:trust`, Neovim's
`vim.secure`); JSON files never run code. `:Earmark log` lists files that failed to load.

Labels can ask for more than a colour, which suits rubrics and surveys:

```lua
-- <root>/.earmark/sets/review.lua
return {
  labels = {
    { key = 'q1', name = 'Accuracy', color = '#e06c75',
      -- asked after the label; a choice may have its own colour
      choices = { { key = 'a', name = 'Correct' }, { key = 'b', name = 'Minor issue', color = '#e5c07b' }, 'Major issue' },
      -- a line of text, only for these choices
      text = { when = { 'b', 'c' }, prompt = 'What is wrong?' } },
    -- only offered once the annotation has q1 = b or c (others show why they're unavailable)
    { key = 'q1.1', name = 'Severity reason', requires = { q1 = { 'b', 'c' } } },
    { key = 'q2', name = 'Tone' },
  },
}
```

A value then reads `Accuracy · b Minor issue`, and the hover shows its text. `choices` can
also be a map: `{ a = 'Correct', b = 'Minor issue' }`.

### Statusline

`require('earmark').statusline()` returns a statusline string (empty in buffers earmark
doesn't track): a swatch and the label the next `gh` uses, the number of annotations and
notes, `⚠` with detached/ambiguous ones, and for numbered sets the digits `1234567890` in
their colours.

Pass the highlight group of the section it sits in as `hl`: its colours then sit on that
section's background, and the section's colours come back after them (without it, they
reset to `StatusLine`).

```lua
-- mini.statusline, inside your content.active function
local earmark = require('earmark').statusline({ hl = 'MiniStatuslineFileinfo' })
return MiniStatusline.combine_groups({
  { hl = mode_hl, strings = { mode } },
  { hl = 'MiniStatuslineFilename', strings = { filename } },
  '%=',
  { hl = 'MiniStatuslineFileinfo', strings = { earmark, fileinfo } },
})

-- lualine: the group of the section it's in (`:Inspect` over the section shows it)
sections = { lualine_x = { function() return require('earmark').statusline({ hl = 'lualine_x_normal' }) end } }
```

`<Plug>` mappings: `(earmark-operator)`, `(earmark-line)`, `(earmark-erase)`,
`(earmark-clear)`, `(earmark-restore)`, `(earmark-next)`, `(earmark-prev)`,
`(earmark-cycle-set)`, `(earmark-pick-set)`, `(earmark-peek)`, `(earmark-note)`, `(earmark-toggle-hover)`,
`(earmark-tags)`, `(earmark-toggle-indicators)`, `(earmark-next-same)`, `(earmark-prev-same)`,
`(earmark-jump)`, `(earmark-pick)`, `(earmark-pick-all)`, `(earmark-review)`, `(earmark-reanchor)`, `(earmark-qf)`, `(earmark-diff)`,
`(earmark-export)`, `(earmark-occurrences)`, `(earmark-regrow)`, `(earmark-zk)`, `(earmark-relabel)`, `(earmark-add-value)`,
`(earmark-rename)`, `(earmark-palette)`.

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

Tags you use are counted in `<storage_dir>/tags.json`, which feeds the `<leader>mt` list.

How an annotation finds its text again, in order: the diff of the saved snapshot against
the current text; the exact text with the most similar surroundings (each annotation
remembers enough surrounding text to be unique when it is made); and, when the text itself
was edited and moved, the closest fuzzy match (whitespace ignored). When two places fit
equally well, the annotation is marked **ambiguous** instead of guessing, and `<leader>md`
offers the candidates. `:Earmark check` prints how each annotation was placed; run
headless, it exits with status 1 if any is detached:

```sh
nvim --headless notes/draft.md -c 'Earmark check' -c q
```

Writes are atomic. A record that can't be parsed is left untouched, and saving for that
buffer is disabled with a warning. v1 records (snapshot inline) are read as is and rewritten
as v2 on the next save.

## API

Positions are 0-based `{ row, col }` (byte columns), spans end-exclusive; `buf` 0 is the
current buffer. A value is `{ set = 'vivid', label = '3', choice = 'b'?, text = '…'? }`.

```lua
local em = require('earmark')
local a = em.annotate(buf, { 0, 4 }, { 0, 9 }, { set = 'vivid', label = '3' })
em.list(buf)                -- { { annotation = a, s = {r,c}, e = {r,c} }, ... } sorted; s/e nil when detached
em.at(buf, pos)             -- same shape, at pos (default cursor), innermost first
em.get(buf, a.id)
em.set_note(buf, a.id, 'text #tag')   -- nil or '' clears
em.set_tags(buf, a.id, { 'todo' })
em.set_values(buf, a.id, { { set = 'vivid', label = '3' }, { set = 'review', label = 'q1', choice = 'b' } })
em.erase(buf, { a.id })     -- to the trash
em.restore(buf)             -- the last erased batch
em.rename_label(buf, { set = 'vivid', label = '3' }, 'Vague')
em.names(buf)               -- { ['vivid/3'] = 'Vague' }
em.export(buf, { group_by = 'tag' })  -- Markdown lines
em.pick({ scope = 'project', query = '#todo' })
em.hover.show() ; em.hover.hide()
em.statusline({ hl = 'MiniStatuslineFileinfo' })  -- hl: the section it sits in
em.on('Note', function(data) print(data.buf, data.action, vim.inspect(data.ids)) end)
```

Events: `User EarmarkChanged` for every change, plus a specific `User Earmark<Action>`
(`EarmarkAdd`, `EarmarkUpdate`, `EarmarkErase`, `EarmarkRestore`, `EarmarkRepair`,
`EarmarkNote`, `EarmarkLoad`), all with `data = { buf, action, ids }`. `em.on(name, fn)` is
shorthand for those autocmds. Anything not listed here is internal and may change.

### zk

With [zk-nvim](https://github.com/zk-org/zk-nvim) installed, `<leader>mz` turns the annotation
under the cursor into a zk note: the annotated text as a quote, the annotation's note, and a
link back to the line. The note is titled after the note's first line (else the label name),
created in the project's notebook (`zk.dir` picks a subdirectory) and opened in a split
(`zk.open = false` to stay). The annotation keeps its note; the hover shows `↗ zk`.

## FAQ

**Doesn't `gh` start Select mode?** In stock Neovim, yes. earmark takes it over because Select
mode is rarely used and `gh` reads as "highlight". Set `keys.operator` (and `keys.line`) to
something else if you use Select mode.

**Why does `ghh` sometimes wait before marking the line?** `gh` is an operator, so after
`ghh` Neovim can't yet tell whether `h` was the motion or the start of a longer mapping and
waits `'timeoutlen'`. Type it quickly, or map `line` to another key.

**Will a formatter or `git checkout` lose my annotations?** No. Each record keeps a snapshot of
the text it was made against and re-finds every annotation from it (then by quote and
context, then fuzzily). Anything it can't place with confidence is marked stale, ambiguous or
detached and shows up in `<leader>md`; nothing is dropped. `:Earmark check` shows where each
one landed.

**Should I commit `.earmark/`?** That's the idea: records and label names are small JSON and
diff well. The text snapshots (`.earmark/snap/`) and exports are gitignored automatically.

**Neovim 0.12?** Supported. earmark uses `vim.text.diff` where it exists and avoids APIs
deprecated in 0.12.

**Numbers for labels are hard to remember.** Name them: `<Tab>` in the prompt, or
`<leader>mr`. Names are per file and remembered for the project, and the prompt matches
names as you type.

## Develop

`make test` runs the mini.test suite headless. It uses your lazy.nvim copy of mini.nvim if
present, otherwise clones it into `deps/`. `make deps` also fetches flash.nvim so the jump
test runs instead of being skipped. `make demo` builds the demo project described above. The
docs test checks that every default key and subcommand is in this README and in
`doc/earmark.txt`, and that the help file's tags are valid.

## Status (2026-10-19)

The 2026-10 rebuild plan is done: milestones M0 to M10 landed as stacked draft PRs (#1 to
#11), and #12 fixes what an audit against the old Numhi conversations found (names carrying
across a project's files, a second label on the same word showing as an overlap, `<Esc>`
while naming, flash remote operations from the prompt or a note, the statusline inside other
sections, linewise erase, tags hidden at startup). 173 tests pass on Neovim 0.11 and 0.12.
The plan is in `docs/PLAN.md`.

Defaults that were decided overnight and are worth a second look:

1. Naming: the prompt asks for a name the first time a label is used in a project
   (`prompt.ask_name = 'first_use'`), and that name then applies in the project's other
   files; `'always'` makes it ask every time.
2. Identifier tags are written `@A` in notes and shown as `[A]` at the end of the line (`@A`
   in the hover, where Markdown would hide brackets).
3. Overlaps: mixed colours with the outer colour as underline; a second label is an
   undercurl, labels 3 and up are small squares after the span (not a gradient or
   interleave).
4. The hover header is the label colour as text (`▍ name`), not a filled bar.
5. `<leader>mv` shows or hides tags and identifiers at the ends of lines (hidden at
   startup); pencils always show.
6. Colours adapt to the colour scheme's background (`color_adapt`): decided 2026-10-18.
7. `gh` without a count always opens the prompt; `<CR>` on empty input reuses the last label.
8. Text snapshots are gitignored, so a fresh clone re-anchors by quote and context only.
9. What the statusline shows: the next label, counts, the warning count and the digit row.
10. Storage is JSON only; SQLite and encryption are dropped.
11. Exports go to `<root>/.earmark/export/<project>-<path>.md` by default.
12. `.earmark/names.json` (label names for the project) is committed, not ignored.
13. Another label on exactly the same span is added to the annotation (an overlap) rather
    than replacing its label; `<leader>ml` replaces. Confirmed 2026-10-18, with a question
    first (a add / r replace / Esc cancel, `prompt.confirm_stack`).

Smaller behaviours to confirm: an annotation re-placed by a close fuzzy match (one typo) stays
"ok" rather than "stale"; `<leader>mg` accepts the new text as the annotation's text;
`<leader>mo` has no one-step undo (erase the extra annotations with `<leader>mx`); set files are reloaded by checking their
modification time on focus and buffer switches. New on 2026-10-18: `cw`, `ciw`, `s` or `C` on an
annotation's first or last words keeps the new words in it (changing all of it keeps it too,
marked stale) instead of shrinking or detaching it. Also new: colour names come from the xkcd
colour survey (about 700 names after dropping crude and misspelled ones), the palette is on
`<leader>mc`, and a count shows a hint with the label it picked while the motion is typed.
