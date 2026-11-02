# earmark.nvim

Highlight spans of text in Neovim with coloured labels, add notes and tags to them, and
keep them attached to the right text while the file changes.

![3ghiw gives a word label 3; 12gh$ marks to the end of the line with label 12](docs/demos/annotate-count.gif)

- **Labels come from sets.** Five generated palettes with keys 1 to 99, a `feedback` set
  for reviewing someone's work, and any sets you define.
- **A count picks the label:** `3ghiw` marks a word with label 3. Without a count, a
  prompt opens next to the text; type a key or part of a label's name and the text shows
  the colour as you type.
- **Annotations follow the text.** Typing, deleting, undo, formatters that rewrite the
  buffer, `:e!` and edits made outside Neovim all move them with their text. If the text is
  rewritten the annotation is marked **stale**; if it is deleted it is **detached** and comes
  back when the text does. Nothing is dropped silently.
- **Notes, tags and a hover.** Each annotation can have a Markdown note with `#tags`. Rest
  the cursor on it to see its labels, name, tags and note.
- **Plain JSON storage** in your project (`<root>/.earmark/`), so annotations can be
  committed with the files they describe.
- **zk notes:** turn an annotation into a note in a [zk](https://github.com/zk-org/zk)
  notebook, with a link back to the line.

![gh without a count opens the prompt; the text takes the colour while you type](docs/demos/prompt.gif)

![Typing, deleting and undo: the annotations move with their text](docs/demos/live-edits.gif)

Requires Neovim 0.11 or newer. Full reference: `:help earmark`. If something doesn't work,
run `:checkhealth earmark`.

## Install (lazy.nvim)

```lua
{ 'Crackerfracks/earmark.nvim', opts = {} }
```

From a local checkout:

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

## Quickstart

1. Put the cursor on a word and type `3ghiw`. The word gets label 3 of the current set.
2. Type `ghip` without a count: a prompt opens beside the paragraph. Type `12`, watch the
   colour change on the text, press `<CR>`.
3. Press `<leader>mm` on an annotation and write a note with a `#tag` in it. `q` saves.
4. Rest the cursor on it: the hover shows the label, its name, the tag and the note.
5. `<leader>mp` lists every annotation in the file; `<leader>md` lists the ones whose text
   changed or disappeared.

To try it without changing your config, run `make demo` in a checkout. It writes a small
annotated project to `/tmp/earmark-demo` and prints the command that opens it.

## Use

`<leader>m?` opens a list of every key below, grouped the same way and showing your own
mappings; `<CR>` on a row runs it. With [which-key](https://github.com/folke/which-key.nvim)
installed, each key also gets a short description and an icon for its group.

**Annotate**

| Keys | Action |
|---|---|
| `{count}gh{motion}` | annotate with label `{count}` of the current set (`3ghiw`, `12gh$`) |
| `gh{motion}` | annotate, choosing the label in a prompt (see below) |
| `{count}ghh` | annotate the line |
| `{Visual}{count}gh` | annotate the selection (a block selection is one annotation: one label, one note) |
| `.` | repeat with the same label, no prompt |
| `<leader>mo` | give every other occurrence of the annotated text the same labels |

<details>
<summary>Clips: annotating</summary>

`7G` then `4ghh`: a whole line

![`7G` then `4ghh`: a whole line](docs/demos/annotate-line.gif)

A Visual selection, then `5gh`

![A Visual selection, then `5gh`](docs/demos/annotate-visual.gif)

A Visual block highlights each line's part and works as one annotation

![A Visual block highlights each line's part and works as one annotation](docs/demos/annotate-block.gif)

`.` repeats with the same label

![`.` repeats with the same label](docs/demos/repeat.gif)

After `3gh`, a hint shows which label the count picked

![After `3gh`, a hint shows which label the count picked](docs/demos/count-hint.gif)

Labels 11 to 99 are shades of 1 to 10

![Labels 11 to 99 are shades of 1 to 10](docs/demos/label-shades.gif)

A second label on the same word: `a` adds it, `r` replaces

![A second label on the same word: `a` adds it, `r` replaces](docs/demos/same-span.gif)

`<leader>mo` gives every other copy of the text the same labels

![`<leader>mo` gives every other copy of the text the same labels](docs/demos/occurrences.gif)

</details>

**Change the annotation under the cursor**

| Keys | Action |
|---|---|
| `<leader>ml` | change its label (`{count}` picks among overlapping ones) |
| `<leader>ma` | add another label |
| `<leader>mr` | name (or rename) its label for this file; an empty name clears it |
| `<leader>mg{motion}` / `{Visual}<leader>mg` | move it onto the motion / selection (note and labels stay) |
| `<leader>mx` | erase it (Visual: every annotation in the selection) |
| `<leader>mX` | erase every annotation in the buffer (restorable) |
| `<leader>mu` | restore the most recently erased |

<details>
<summary>Clips: changing annotations</summary>

`<leader>ml` changes the label

![`<leader>ml` changes the label](docs/demos/relabel.gif)

`<leader>ma` adds another label

![`<leader>ma` adds another label](docs/demos/add-label.gif)

`<leader>mr` names the label in this file

![`<leader>mr` names the label in this file](docs/demos/rename.gif)

`<leader>mg` moves the annotation onto another motion

![`<leader>mg` moves the annotation onto another motion](docs/demos/regrow.gif)

`<leader>mx` erases one, `<leader>mu` brings it back

![`<leader>mx` erases one, `<leader>mu` brings it back](docs/demos/erase-restore.gif)

Visual `<leader>mx` erases every annotation in the selection

![Visual `<leader>mx` erases every annotation in the selection](docs/demos/erase-visual.gif)

`<leader>mX` erases everything in the file

![`<leader>mX` erases everything in the file](docs/demos/clear-all.gif)

</details>

**Notes and tags**

| Keys | Action |
|---|---|
| `<leader>mm` | open / close its note (`{count}` picks among overlaps) |
| `<leader>mt` | add / remove tags (lists every tag you've used) |
| `<leader>mi` | show the details float now and move into it (scroll; `q` closes) |
| `<leader>mh` | details when the cursor stops: on / off |
| `<leader>mv` | `#tags` at the ends of lines: on / off (off at startup) |

<details>
<summary>Clips: notes, tags and the hover</summary>

`<leader>mm` writes a note; `q` saves

![`<leader>mm` writes a note; `q` saves](docs/demos/note.gif)

`,s` moves the note to a split, `,f` back to a float

![`,s` moves the note to a split, `,f` back to a float](docs/demos/note-split.gif)

Resting the cursor on an annotation shows its details

![Resting the cursor on an annotation shows its details](docs/demos/hover.gif)

Overlapping annotations are listed innermost first

![Overlapping annotations are listed innermost first](docs/demos/hover-overlap.gif)

`<leader>mh` turns the hover off and on

![`<leader>mh` turns the hover off and on](docs/demos/hover-toggle.gif)

`<leader>mi` shows the details now and moves into them

![`<leader>mi` shows the details now and moves into them](docs/demos/peek.gif)

`<leader>mt` adds and removes tags

![`<leader>mt` adds and removes tags](docs/demos/tags.gif)

Pencils for notes; `<leader>mv` shows tags at line ends

![Pencils for notes; `<leader>mv` shows tags at line ends](docs/demos/indicators.gif)

</details>

**Move**

| Keys | Action |
|---|---|
| `<leader>mn` / `<leader>mN` | next / previous annotation (wraps; `{count}` skips) |
| `<leader>m]` / `<leader>m[` | next / previous with the label under the cursor |
| `<leader>mj` | jump labels on every visible annotation ([flash.nvim](https://github.com/folke/flash.nvim); without it, the picker) |

<details>
<summary>Clips: moving between annotations</summary>

`<leader>mn` and `<leader>mN`

![`<leader>mn` and `<leader>mN`](docs/demos/next-prev.gif)

`<leader>m]` and `<leader>m[` stop only at the same label

![`<leader>m]` and `<leader>m[` stop only at the same label](docs/demos/next-same.gif)

`<leader>mj` with flash.nvim

![`<leader>mj` with flash.nvim](docs/demos/jump.gif)

</details>

**Find and review**

| Keys | Action |
|---|---|
| `<leader>mp` / `<leader>mP` | pick an annotation in this file / in the whole project |
| `<leader>mq` | this file's annotations into the quickfix list |
| `<leader>md` | review the annotations whose text changed or disappeared |
| `{Visual}<leader>mR` | attach the annotation chosen in the review list to the selection |
| `<leader>mD` | compare an annotation's original text with what it says now |

<details>
<summary>Clips: finding and reviewing</summary>

`<leader>mp` lists the annotations in this file

![`<leader>mp` lists the annotations in this file](docs/demos/pick.gif)

`<leader>mP` lists them in the whole project

![`<leader>mP` lists them in the whole project](docs/demos/pick-all.gif)

`:Earmark pick_all` with a query

![`:Earmark pick_all` with a query](docs/demos/pick-query.gif)

`<leader>mq` puts this file's annotations in the quickfix list

![`<leader>mq` puts this file's annotations in the quickfix list](docs/demos/qf.gif)

`<leader>md` lists annotations whose text changed or is gone

![`<leader>md` lists annotations whose text changed or is gone](docs/demos/review.gif)

`<leader>mD` shows the original text next to the current text

![`<leader>mD` shows the original text next to the current text](docs/demos/diff.gif)

Visual `<leader>mR` attaches a detached annotation to the selection

![Visual `<leader>mR` attaches a detached annotation to the selection](docs/demos/reanchor.gif)

</details>

**Label sets**

| Keys | Action |
|---|---|
| `<leader>ms` | switch to the next label set (a popup shows its colours) |
| `<leader>mS` | choose the label set from a list |
| `<leader>mc` | the palette: every label of the set as a colour patch with your name for it, its colour's name, hex and uses; `<CR>` makes it the label `gh` offers first, digits jump to a key, `r` names it, `<Tab>` switches sets |

<details>
<summary>Clips: label sets and colours</summary>

The default labels

![The default labels](docs/demos/default-labels.gif)

`<leader>ms` switches to the next set

![`<leader>ms` switches to the next set](docs/demos/cycle-set.gif)

`<leader>mS` chooses a set from a list

![`<leader>mS` chooses a set from a list](docs/demos/pick-set.gif)

`<leader>mc` shows the set's colours with their names

![`<leader>mc` shows the set's colours with their names](docs/demos/palette.gif)

The same labels on a light colour scheme

![The same labels on a light colour scheme](docs/demos/light-theme.gif)

`:Earmark color` recolours a label in this file

![`:Earmark color` recolours a label in this file](docs/demos/color.gif)

</details>

**Export and zk**

| Keys | Action |
|---|---|
| `<leader>me` | export this file's annotations to Markdown (asks where; opens it in a split) |
| `<leader>mz` | make a [zk](https://github.com/zk-org/zk) note from the annotation, or open the note it has; in a note, list the annotations linked to it (see [zk](#zk)) |
| `<leader>m?` | the key list |

<details>
<summary>Clips: export and zk</summary>

`<leader>me` writes the annotations to a Markdown file

![`<leader>me` writes the annotations to a Markdown file](docs/demos/export.gif)

`<leader>mz` makes a zk note from an annotation

![`<leader>mz` makes a zk note from an annotation](docs/demos/zk.gif)

</details>

### The label prompt

`gh` without a count opens a one-line prompt beside the span. The span shows the selected
colour while you type, and the list under the input narrows as you go:

- digits match keys first, then the shades of that family (`3` → 3, 13, 23 …);
- anything else matches keys, then label names (fuzzy);
- empty input offers the last label, then the labels already used in this file.

Each row shows the label's colour, its key, your name for it and the colour's name
("Tangerine"). With a count (`3gh`) there's no prompt; a small hint under the cursor shows
which label the count picked while you type the motion (`prompt.count_hint`).

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

<details>
<summary>Clips: the prompt</summary>

The first use of a label asks for a name

![The first use of a label asks for a name](docs/demos/prompt-name.gif)

Empty input offers the last label first

![Empty input offers the last label first](docs/demos/prompt-last.gif)

Typing part of a name

![Typing part of a name](docs/demos/prompt-names.gif)

A digit matches the key, then its shades

![A digit matches the key, then its shades](docs/demos/prompt-shades.gif)

`<C-s>` tries the next label set

![`<C-s>` tries the next label set](docs/demos/prompt-sets.gif)

`<Tab>` names the label; `<S-Tab>` goes back

![`<Tab>` names the label; `<S-Tab>` goes back](docs/demos/prompt-tab.gif)

`<Esc>` switches to Normal mode; `<Esc>` again cancels

![`<Esc>` switches to Normal mode; `<Esc>` again cancels](docs/demos/prompt-normal.gif)

</details>

Annotating exactly the same span again with another label asks first: <kbd>a</kbd> (or
<kbd>Enter</kbd>) adds the label to it, so both show as an overlap and share one note;
<kbd>s</kbd> makes a separate annotation on the same text, with its own note and tags;
<kbd>r</kbd> replaces its label (as `<leader>ml` does); <kbd>Esc</kbd> cancels. `.` repeats your answer without asking.
`prompt.confirm_stack = false` always adds, without asking. With a label it already has,
nothing changes.

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

`:Earmark color #rrggbb` (or `reset`) recolours the label under the cursor in this file
only.

### Notes and the hover

`<leader>mm` opens the annotation's note, a Markdown buffer in a float right under the
span (an empty note starts in Insert mode). `q`, `:w`, `<C-s>`, leaving the float or
closing it any other way saves it; `,s` moves it to a split at the bottom and `,f` back
(`,` being your `maplocalleader`; the float's footer shows yours). The float starts wide,
grows with the text up to `note.width`/`note.max_width` and then wraps and grows taller;
<kbd>Alt</kbd>+arrow keys move it (in Normal and Insert mode) when it covers something. Clearing all the text removes the note. Write `#tags`
and `@identifiers` anywhere in a note; earmark picks them up. The note stays open while a
float you opened from it has focus (an emoji or file picker, say), so what you pick goes
into the note. When separate annotations cover the same text, `<leader>mm` asks which
note; `2<leader>mm` opens the second without asking.

When the cursor rests on an annotation that has a name, a note, tags, extra labels or a
stale/ambiguous status, a small float shows all of that without taking focus. It stays
while you move inside the annotation and goes away when you leave it, type, scroll or start
an operator. Overlapping annotations are listed innermost first (①, ②, …). Set
`hover.show_when = 'always'` to see it on every annotation.

You can move the cursor into the hover with a flash.nvim jump, a mouse click or `<C-w>w`.
Landing on a line of a note opens that note for editing with the cursor at the same spot;
landing anywhere else keeps the hover focused, and `<CR>` there opens the note of the
annotation under the cursor.

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
`has:note`, `has:tags`, `has:zk`; anything else matches the text, name or note.

`<leader>md` lists annotations that are **stale** (their text was rewritten),
**ambiguous** (the text appears more than once) or **detached** (the text is gone). For each
one you can jump to it, compare the original with the current text, accept the current text,
move it to one of the places its text could be now (exact or close matches, scored), attach
it to a selection (`{Visual}<leader>mR`), or erase it.

`:Earmark scratch` reopens a scratch buffer you annotated earlier, with its text and
annotations.

<details>
<summary>Clip: scratch buffers</summary>

`:Earmark scratch` reopens an annotated scratch buffer

![`:Earmark scratch` reopens an annotated scratch buffer](docs/demos/scratch.gif)

</details>

### Export

`<leader>me` writes a Markdown file with every annotation, grouped by label (with your
names for them), each with its text, line numbers, tags and note, plus a **Detached** section
for annotations whose text is gone. Inside a project it suggests
`<root>/.earmark/export/<project>-<path-of-file>.md` (`export/` is gitignored).
`export.location = 'beside'` writes it next to the annotated file instead, as
`<name>.earmark.md`; `{ 'project', 'beside' }` writes both (you're asked about the first),
and a function `(buf, ctx) -> path` picks any place. Set
`export.group_by` to `'position'`, `'tag'` or `'time'`, or `export.format` to a function
`(list, ctx) -> lines` to write your own body. An annotation with a zk note gets a
`→ [title](path)` line, with the path relative to the export file.

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
- Where annotations of **the same label** are nested (`this is` with `is` marked again), each
  inner level is a deeper shade of the same colour.
- An annotation's **second label** is an undercurl in that label's colour. With more labels
  the undercurl is cut into equal runs, one per extra label, so nothing is added to the line
  (`overlap.extra = 'squares'` instead puts a small square `■` per label after the span).
- **Stale** annotations (text rewritten) are drawn with much less colour and
  underdashed; **ambiguous** ones are underdotted.

Set `overlap = { style = 'top' }` to turn the mixing off: the smallest span is drawn on
top.

<details>
<summary>Picture: overlaps</summary>

![Different labels mixed, the same label nested, extra labels as an undercurl cut into runs, a stale annotation](docs/demos/overlap-looks.png)

</details>

### Commands

`:Earmark {info|peek|note|tags|toggle_hover|toggle_indicators|erase|clear|restore|next|prev|next_same|prev_same|jump|pick|pick_all|review|diff|reanchor|qf|scratch|check|export|occurrences|zk [new|link|pick|sources]|palette [set]|color|cycle_set|pick_set|relabel|add_value|rename|set [name]|reload|log|help}`

`:Earmark info` (the default) prints the details of the annotations under the cursor.

`:Earmark log` shows recent warnings and errors (also written to `<storage_dir>/earmark.log`).

## Configure

Defaults:

```lua
require('earmark').setup({
  -- Strings are generated numbered palettes; named tables are your own sets.
  sets = { 'vivid', 'pastel', 'earth', 'metal', 'cyber', 'feedback' },
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
    palette = '<leader>mc', help = '<leader>m?',
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
  export = { group_by = 'label', include_detached = true, format = nil, location = 'project' }, -- or 'beside', a function, or a list
  zk = {
    cmd = 'zk',
    notebook = nil, -- default: the nearest .zk above the file, then $ZK_NOTEBOOK_DIR
    dir = nil, -- notebook subfolder for new notes, or function(ctx) -> subfolder
    template = nil, -- your own zk template (gets the body and --extra fields)
    open = true, -- open a new note in a split
  },
  note = {
    layout = 'float', -- 'float' | 'split'
    width = 0.75, max_width = 120, -- fraction of the window, and a column cap
    gutter = true, -- a blank column at the float's left edge
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
  overlap = { style = 'blend', extra = 'split' }, -- 'blend' | 'top'; 'split' | 'squares'
})
```

Your own sets:

```lua
sets = {
  'vivid',
  'feedback', -- the set that ships with earmark (see below)
  critique = { labels = {
    { key = 'c', name = 'contradiction', color = '#e06c75' },
    { key = 'v', name = 'vague' },          -- colour picked automatically
    'cut this',                              -- key defaults to its position: 3
  } },
  mine = { generate = 'numbered', palette = { L = 0.7, C = 0.15, h0 = 200, zig = 0.04 } },
},
```

A count resolves to the label whose key is that number, else to the label at that position.

<details>
<summary>Clip: your own set</summary>

A set defined in `setup()`

![A set defined in `setup()`](docs/demos/custom-set.gif)

</details>

### Label set files

Sets can also live in files, one set per file, named after the file:

- your own: `~/.config/earmark/sets/*.lua` or `*.json` (`sets_dir` changes or disables this);
- a project's: `<root>/.earmark/sets/*.lua` or `*.json`, loaded when you open a file in that
  project. A project's set replaces a set of the same name.

Files are re-read when you save them in Neovim or come back to Neovim after editing them
elsewhere. Project Lua files run only after you trust them (`:trust`, Neovim's
`vim.secure`); JSON files never run code. `:Earmark log` lists files that failed to load,
and problems in the ones that did (a colour that isn't `#rrggbb` or `#rgb` gets a palette
colour instead); a broken set never stops the others loading. A label repeated with the
same key replaces the earlier one.

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

<details>
<summary>Clip: a set file with questions</summary>

A label that asks a question, then a line of text

![A label that asks a question, then a line of text](docs/demos/set-files.gif)

</details>

A label can carry `tags = { 'option-a' }`: annotating with it adds those tags. A set can
carry `tags = { 'todo', 'nit' }`: `<leader>mt` lists them first.

### Feedback, and sets for one file

The `feedback` set is for reviewing something someone else wrote (a plan, a draft, a demo,
code). Its keys are 1 to 9, so a count picks the label: `2ghip` marks a paragraph "Change".

| Key | Label | Meaning |
|---|---|---|
| 1 | Keep | good as it is |
| 2 | Change | change this; the note says how |
| 3 | Wrong | incorrect, or a bug |
| 4 | Question | a question about this |
| 5 | Unclear | confusing or hard to follow |
| 6 | Cut | remove this |
| 7 | Idea | an idea or something to add |
| 8 | Prefer | choose this option |
| 9 | Later | not now |

Export the file (`<leader>me`) to hand the feedback over as a Markdown list, grouped by
label, with the notes.

A set can also belong to one file or a few. Put `<name>.earmark-set.json` in the same
folder as the file, or in a folder above it inside the project:

```json
{
  "extends": "feedback",
  "labels": [
    { "key": "a", "name": "Option A: one big picker", "tags": ["option-a"] },
    { "key": "b", "name": "Option B: two small pickers", "tags": ["option-b"] }
  ],
  "tags": ["pick"],
  "expires": "2026-12-01"
}
```

- `plan.earmark-set.json` applies to `plan.md`, `plan.html` and so on (any `plan.*`). Give
  `"files": ["drafts/*.md"]` to choose other files; the globs are relative to the set file's
  folder (`**/*.md`, `../drafts/*.md` and absolute paths work too; `[]` is no file).
- Opening one of those files switches to its set; leaving it switches back to the set you
  used before. `"auto": false` only lists it first instead.
- The set is listed (`<leader>mS`, `<leader>ms`, Ctrl-s in the prompt) only in its files, so
  sets made for one review don't fill up the list everywhere else.
- `"extends": "feedback"` starts from the feedback labels; a label with the same key
  replaces one of them.
- After the `"expires"` day (`YYYY-MM-DD`) the set is no longer offered. Annotations made
  with it keep their colours.
- A set for some files never replaces a general set of the same name.

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
`(earmark-rename)`, `(earmark-palette)`, `(earmark-help)`.

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

<details>
<summary>Clips: edits made outside Neovim</summary>

Another program rewrites the file; the annotations follow their text

![Another program rewrites the file; the annotations follow their text](docs/demos/external-edit.gif)

An outside edit inside an annotated line

![An outside edit inside an annotated line](docs/demos/external-edit-inline.gif)

</details>

Writes are atomic. A record that can't be parsed is left untouched, and saving for that
buffer is disabled with a warning. v1 records (snapshot inline) are read as is and rewritten
as v2 on the next save. Records are not merged: when two Neovim instances annotate the same
file, the last to save wins (`:Earmark reload` reads what the other one saved). When the
root changes (a root marker is added or removed), a file's record moves to its new place the
next time the file is opened.

## API

Positions are 0-based `{ row, col }` (byte columns), spans end-exclusive; `buf` 0 is the
current buffer. A value is `{ set = 'vivid', label = '3', choice = 'b'?, text = '…'? }`.
Annotations and tables you get back are copies: changing them changes nothing. A Visual
block is one annotation per row, each with `group` set to the first row's id; that first
row holds the note and tags, `set_note`/`set_tags` on any row go to it, and `set_values`
and `erase` on any row act on the whole block.

```lua
local em = require('earmark')
local a = em.annotate(buf, { 0, 4 }, { 0, 9 }, { set = 'vivid', label = '3' })  -- nil if the span is empty
-- on exactly the span of an annotation the label joins it; { separate = true } makes a new one
em.annotate(buf, { 0, 4 }, { 0, 9 }, { set = 'vivid', label = '5' }, { separate = true })
em.list(buf)                -- { { annotation = a, s = {r,c}, e = {r,c} }, ... } sorted; s/e nil when detached
em.at(buf, pos)             -- same shape, at pos (default cursor), innermost first
em.get(buf, a.id)           -- nil if it isn't there
em.set_note(buf, a.id, 'text #tag')   -- nil or '' clears
em.set_tags(buf, a.id, { 'todo' })
em.set_values(buf, a.id, { { set = 'vivid', label = '3' }, { set = 'review', label = 'q1', choice = 'b' } })
em.erase(buf, { a.id })     -- to the trash
em.restore(buf)             -- the last erased batch
em.rename_label(buf, { set = 'vivid', label = '3' }, 'Vague')
em.names(buf)               -- { ['vivid/3'] = 'Vague' }
em.display_name(buf, value) -- 'Vague': this file's name for the label, else its own name (or key)
em.label(value)             -- { set, key, name, color, desc, tags }, or nil if there's no such label
em.export(buf, { group_by = 'tag' })  -- Markdown lines
em.pick({ scope = 'project', query = '#todo' })
em.hover.show() ; em.hover.hide()
em.statusline({ hl = 'MiniStatuslineFileinfo' })  -- hl: the section it sits in
em.on('Note', function(data) print(data.buf, data.action, vim.inspect(data.ids)) end)
em.zk.promote(buf, a.id, { open = false }, function(err, path) end)  -- see zk below
em.zk.notebook(buf)         -- the notebook's path, or nil and the reason
em.zk.path(a, buf)          -- absolute path of the annotation's note, or nil
```

Events: `User EarmarkChanged` for every change, plus a specific `User Earmark<Action>`
(`EarmarkAdd`, `EarmarkUpdate`, `EarmarkErase`, `EarmarkRestore`, `EarmarkRepair`,
`EarmarkNote`, `EarmarkLoad`, `EarmarkZk`), all with `data = { buf, action, ids }`. `em.on(name, fn)` is
shorthand for those autocmds. `ids` is nil for `EarmarkLoad`, `EarmarkRepair` (an edit
detached, re-attached or changed the status of annotations) and a label's name or colour
changing. Setting what is already there fires nothing. Anything not listed here is
internal and may change.

### zk

earmark can turn an annotation into a note in a [zk](https://github.com/zk-org/zk) notebook.
It runs the `zk` program itself, so all you need is zk (Arch: `sudo pacman -S zk`) and a
notebook (`zk init`). zk-nvim is not required.

- **`<leader>mz`** on an annotation makes a note with the annotated text as a quote, the
  annotation's note, and a `[source](…#L12)` link back to the line. The note is titled
  after the first line of the annotation's note, else the start of the quoted text, and
  opens in a split (`zk.open = false` to stay). The annotation keeps its own note and
  remembers the zk note; the hover shows `↗ zk <file name>`.
- **Press it again** and the note opens (or the cursor goes to the window already showing
  it), so you never get a second note by accident. If the note's file is gone, earmark
  asks whether to make a new one or unlink it. `:Earmark zk new` makes a new note anyway.
- **Same text, same label:** after promoting, earmark offers to link the other annotations
  in the file with the same text and label (made by `<leader>mo`, say) to the same note.
- **`:Earmark zk link`** attaches a note that already exists, picked from `zk list`.
- **`:Earmark zk pick`** lists the project's annotations that have a note; `<CR>` opens the
  note. The query word `has:zk` does the same in any picker or `:Earmark qf`.
- **In a note**, `<leader>mz` with nothing under the cursor (or `:Earmark zk sources`) lists
  the annotations linked to it. zk's own backlinks find the source files too, through the
  `[source]` link.

The note starts with frontmatter that earmark writes, so zk indexes its title and tags:

```yaml
---
title: "Why does the fox run?"
tags: ["npc", "todo"]        # the label's name, then the annotation's tags
earmark:
  id: "…"
  set: "vivid"
  key: "3"
  label: "NPC"
  source: "notes/chapter-1.md"   # inside the notebook; absolute when outside it
  line: 12                        # left out when the annotation is detached
---
```

The `[source]` link is relative to the note's folder, so it works wherever the note goes
in the notebook. A file outside the notebook gets an absolute link. The annotation stores
the note's path relative to the notebook, so the project can move or be cloned elsewhere.

Which notebook: `zk.notebook` if you set it, else the nearest folder with a `.zk` above the
file, else `$ZK_NOTEBOOK_DIR`. Options:

- `zk.dir`: the notebook subfolder for new notes. It can be a function that gets
  `{ buf, annotation, value, label, notebook, source }` and returns a folder, e.g. one
  folder per label: `dir = function(ctx) return 'people/' .. ctx.label:lower() end`. A
  folder outside the notebook is refused.
- With a zk `filename = "{{slug title}}"`, two notes with the same title would share a file:
  zk hands back the existing note, and earmark says so instead of linking to it.
- `zk.template`: one of your own zk templates instead of earmark's. It gets the body only
  (quote, note, source link) and `--extra id=…,set=…,key=…,line=…`; earmark writes no
  frontmatter then, so your template decides it.
- `zk.cmd`: the zk program, if it isn't `zk` on your `PATH`.

**The notebook as the project.** `.zk` is one of `root_markers`, so a notebook is also an
earmark project: annotations on notes go in `<notebook>/.earmark/`, which zk ignores. A
`.earmark` folder nearer to the file wins over the notebook (`.earmark` comes first in
`root_markers`), so don't create one inside the notebook unless you mean to start a
separate project there.

`:checkhealth earmark` shows whether zk is installed, its version, and the notebook for
the current file.

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
present, otherwise clones it into `deps/`. `make deps` also fetches flash.nvim and which-key.nvim
so their tests run instead of being skipped. `make demo` builds the demo project described above. The
docs test checks that every default key and subcommand is in this README and in
`doc/earmark.txt`, and that the help file's tags are valid.

## License

MIT. See [LICENSE](LICENSE).
