"""The demo clips, in README order: one idea per clip. Each function drives one recording.

c.step(keys, note)   the note held to be read, the keys one at a time, the result held (>= 3 s)
c.more(keys)         more keys in the same step (into a prompt or picker), result held
c.text(s)            literal text a character at a time (names, notes, picker queries); in a clip
                     with typo=True the first long enough text gets one typo, fixed with Backspace
c.ex(line, note)     type an Ex command visibly and run it
Pacing lives in record.py (Clip.gap, BEFORE/AFTER/END).
c.goto(row, col)     place the cursor (setup only; the page's "Try it" says how to get there)
c.shot(hold)         one more frame
Rows are 1-based, columns 0-based. A space in a key string is <leader> (Space).
Project files: notes/fresh.md (nothing annotated), notes/essay.md (annotated),
notes/changed.md (annotated, then edited outside Neovim).
"""
CLIPS = []


def clip(name, title, **kw):
    def deco(fn):
        kw['title'] = title
        CLIPS.append((name, kw, fn))
        return fn
    return deco


FRESH = 'notes/fresh.md'
ESSAY = 'notes/essay.md'
CHANGED = 'notes/changed.md'


def still(c):
    """Clear the key box and take the frame the still screenshot uses."""
    c.note('', clear=True)
    c.shot(1.0, wait=0.8)
    c.mark_still()


# ------------------------------------------------------------------------ Use ---------------

@clip('annotate-count', 'A count picks the label: 3ghiw marks a word with label 3', file=FRESH, cursor=(3, 16))
def _(c):
    c.step('3ghiw', '3 = label, gh = annotate, iw = this word')
    c.goto(4, 0)
    c.step('12gh$', 'label 12, from here to the end of the line ($)')


@clip('count-hint', 'After a count, a hint shows which label it picked', file=FRESH, cursor=(3, 16))
def _(c):
    c.step('5gh', '5gh: the hint under the cursor shows label 5 and its colour name', hold=3.0)
    c.mark_still()
    c.step('iw', 'then the motion: the hint closes and the word takes label 5', before=0)


@clip('default-labels', 'The default labels: set "vivid", keys 1 to 10', file=FRESH, cursor=(3, 0))
def _(c):
    c.step('1ghiww2ghiww3ghiww4ghiww5ghiw', 'labels 1 to 5, one per word')
    c.step('w6ghiww7ghiww8ghiww9ghiww10ghiw', 'labels 6 to 10 (the statusline digits show the same colours)')
    c.mark_still()


@clip('label-shades', 'Labels 11 to 99 are shades: 1, 11, 21, 31, 41 are one colour family', file=FRESH, cursor=(4, 0))
def _(c):
    c.step('1ghiww11ghiww21ghiww31ghiww41ghiw', 'the tens digit picks the shade, the last digit the colour')
    c.mark_still()


@clip('annotate-line', 'ghh marks the whole line', file=FRESH, cursor=(7, 4))
def _(c):
    c.step('4ghh', '{count}ghh: the line, with label 4')
    c.mark_still()


@clip('annotate-visual', 'Visual mode: select text, then {count}gh', file=FRESH, cursor=(3, 12))
def _(c):
    c.step('v3e', 'select three words')
    c.step('6gh', '6gh: the selection gets label 6', before=0)
    c.mark_still()


@clip('annotate-block', 'Visual block: one annotation per line', file=FRESH, cursor=(7, 0))
def _(c):
    c.step('<C-v>jj3e', 'a block over three lines')
    c.step('2gh', '2gh: three annotations, one per line', before=0)
    c.mark_still()


@clip('prompt', 'gh without a count opens the label prompt', file=FRESH, cursor=(7, 4))
def _(c):
    c.step('ghip', 'gh + ip (this paragraph), no count')
    c.step('12', 'type a key: the text shows its colour live', before=0)
    c.mark_still()
    c.step('<CR>', 'Enter applies it. 12 is new in this project, so it asks for a name', before=0, hold=3.0)
    c.step('<Esc>', 'Esc skips naming: label 12 stays', before=0)


@clip('prompt-name', 'First use of a label: the prompt asks you to name it (default)', file=FRESH, cursor=(7, 4), typo=True)
def _(c):
    c.step('ghip12<CR>', 'apply label 12 to the paragraph')
    c.note('type a name for label 12 in this project')
    c.text('staffing', hold=2.0)
    c.step('<CR>', 'Enter saves the name; the hover shows it', before=0, hold=3.0)
    c.mark_still()


@clip('prompt-last', 'Empty prompt: the last label first, then the labels used in this file', file=ESSAY, cursor=(7, 32))
def _(c):
    c.step('ghiw', 'gh on a word, no count: nothing typed yet', hold=3.0)
    c.mark_still()
    c.step('<CR>', 'Enter on empty input reuses the last label', before=0)


@clip('prompt-names', 'Type part of a name: "vag" finds the label named "Vague"', file=ESSAY, cursor=(7, 32))
def _(c):
    c.step('ghiw', 'open the prompt on "roads"')
    c.step('vag', 'letters match label names (fuzzy)', before=0, hold=3.0)
    c.mark_still()
    c.step('<CR>', 'Enter applies "Vague" (label 5)', before=0)


@clip('prompt-shades', 'Type a digit: its key first, then its shades', file=ESSAY, cursor=(12, 8))
def _(c):
    c.step('ghiw', 'open the prompt on "explain"')
    c.step('3', '3 matches 3, then 13, 23, 33 ...', before=0, hold=3.0)
    c.mark_still()
    c.step('<C-n><C-n>', 'Ctrl-n / Ctrl-p (or Down / Up) move; the text follows', before=0)
    c.step('<CR><Esc>', 'Enter applies 23 (Esc skips naming it)', before=0)


@clip('prompt-sets', 'Ctrl-s in the prompt tries the next label set', file=ESSAY, cursor=(12, 8))
def _(c):
    c.step('ghiw3', 'label 3 of "vivid"')
    c.step('<C-s>', 'Ctrl-s: label 3 of "pastel"', before=0)
    c.step('<C-s>', 'Ctrl-s: label 3 of "earth"', before=0)
    c.mark_still()
    c.step('<CR><Esc>', 'Enter applies it', before=0)


@clip('prompt-tab', 'Tab applies and goes to the name stage; Shift-Tab goes back', file=FRESH, cursor=(4, 47))
def _(c):
    c.step('ghiw5', 'label 5 on "roof"')
    c.step('<Tab>', 'Tab: the name stage', before=0)
    c.mark_still()
    c.step('<S-Tab>', 'Shift-Tab: back to choosing the label', before=0)
    c.step('<Esc><Esc>', 'Esc twice cancels (see next clip)', before=0)


@clip('prompt-normal', 'Esc in the prompt: Normal mode (j/k move); Esc again cancels', file=FRESH, cursor=(4, 47))
def _(c):
    c.step('ghiw5', 'label 5 on "roof"')
    c.step('<Esc>', 'Esc: Normal mode in the prompt', before=0)
    c.step('jj', 'j / k move through the candidates', before=0)
    c.mark_still()
    c.step('<Esc>', 'Esc again (or q) cancels: nothing is applied', before=0)


@clip('repeat', 'Repeat with . (same label, no prompt)', file=FRESH, cursor=(4, 4))
def _(c):
    c.step('7ghiw', 'label 7 on "reading"')
    c.step('ww.', '. on another word')
    c.step('w.', '. again')
    c.mark_still()


@clip('same-span', 'The same word twice: the second label is added, not swapped', file=FRESH, cursor=(5, 13))
def _(c):
    c.step('3ghiw', 'label 3 on "places"')
    c.step('5ghiw', 'label 5 on exactly the same word: earmark asks what you mean', hold=2.5)
    c.step('a', 'a adds 5 as another label (r would replace 3): now it has both', before=0)
    c.mark_still()
    c.step('5ghiw', 'again with 5: it already has 5, nothing changes')
    c.step('l', 'the hover lists both labels', before=0, hold=3.0)


@clip('relabel', '<leader>ml changes the label of the annotation under the cursor', file=ESSAY, cursor=(9, 2))
def _(c):
    c.step(' ml', '"vague promise" has label 5 ("Vague")')
    c.step('2<CR>', 'pick label 2, Enter', before=0)
    c.step('<Esc>', 'Esc applies it without naming 2', before=0)
    c.mark_still()


@clip('add-label', '<leader>ma adds another label to the annotation', file=ESSAY, cursor=(9, 2))
def _(c):
    c.step(' ma', 'add a label to "vague promise"')
    c.step('6<CR><Esc>', 'label 6: the second label shows as an undercurl', before=0)
    c.step('jk', 'the hover lists both', before=0, hold=3.0)
    c.mark_still()


@clip('rename', '<leader>mr names or renames a label', file=ESSAY, cursor=(3, 20))
def _(c):
    c.step(' mr', 'label 3 here is named "Claim"')
    c.step('<C-u>', 'clear it', before=0)
    c.note('type the new name')
    c.text('Disputed', hold=1.5)
    c.step('<CR>', 'Enter: every label-3 annotation in the file uses the new name', before=0)
    c.step('jw', 'the other label-3 annotation, "new library"', before=0, hold=3.0)
    c.mark_still()


@clip('erase-restore', '<leader>mx erases the annotation under the cursor; <leader>mu restores it', file=ESSAY, cursor=(4, 40))
def _(c):
    c.step(' mx', 'erase "new library"')
    c.step(' mu', 'restore the most recently erased')
    c.mark_still()


@clip('erase-visual', 'Visual <leader>mx erases every annotation in the selection', file=ESSAY, cursor=(3, 0))
def _(c):
    c.step('Vjj', 'select three lines')
    c.step(' mx', 'erase what is in them', before=0)
    c.mark_still()
    c.step(' mu', '<leader>mu brings them back')


@clip('clear-all', '<leader>mX erases every annotation in the buffer (restorable)', file=ESSAY, cursor=(1, 0))
def _(c):
    c.step(' mX', 'erase everything')
    c.mark_still()
    c.step(' mu', '<leader>mu brings it all back')


@clip('next-prev', '<leader>mn / <leader>mN: next / previous annotation', file=ESSAY, cursor=(1, 0))
def _(c):
    c.step(' mn', 'next')
    c.step(' mn', 'next')
    c.step(' mN', 'previous')
    c.mark_still()


@clip('next-same', '<leader>m] / <leader>m[: next / previous with the same label', file=ESSAY, cursor=(3, 16))
def _(c):
    c.step(' m]', 'next label-3 ("Claim") annotation')
    c.mark_still()
    c.step(' m]', 'again: wraps back to the first')


@clip('jump', '<leader>mj: jump labels on every visible annotation (flash.nvim)', file=ESSAY, cursor=(1, 0))
def _(c):
    c.step(' mj', 'a letter appears on each annotation', hold=3.0)
    c.mark_still()
    c.step('d', 'type one to jump there', before=0)


@clip('pick', '<leader>mp: pick an annotation in this file', file=ESSAY, cursor=(1, 0))
def _(c):
    c.step(' mp', 'each line: label name, text, tags, first line of the note', hold=3.0)
    c.mark_still()
    c.note('typing narrows the list (here a tag)')
    c.text('#todo', hold=2.5)
    c.step('<CR>', 'Enter jumps there', before=0)


@clip('pick-all', '<leader>mP: pick from every annotation in the project', file=ESSAY, cursor=(1, 0))
def _(c):
    c.step(' mP', 'annotations from all files', hold=3.0)
    c.mark_still()
    c.note('narrow it')
    c.text('votes', hold=2.0)
    c.step('<CR>', 'Enter opens the file at the annotation', before=0)


@clip('pick-query', ':Earmark pick_all takes a query: tags, labels, status, has:note', file=ESSAY, cursor=(1, 0), typo=True)
def _(c):
    c.ex('Earmark pick_all has:note #todo', 'only annotations with a note and the tag #todo', hold=3.0)
    c.mark_still()


@clip('qf-query', ':Earmark qf puts the same kind of query into the quickfix list', file=ESSAY, cursor=(1, 0))
def _(c):
    c.ex('Earmark qf all #todo', 'every #todo in the project, in the quickfix list', hold=3.0)
    c.mark_still()


@clip('review', '<leader>md: review annotations whose text changed or disappeared', file=CHANGED, cursor=(1, 0))
def _(c):
    c.note('this file was edited outside Neovim: one phrase rewritten, one paragraph deleted')
    c.shot(3.0)
    c.step(' md', 'stale = text rewritten, detached = text gone', hold=3.0)
    c.mark_still()
    c.step('<CR>', 'choose one: what can be done with it', before=0, hold=3.0)
    c.step('<C-n><CR>', '"Compare": what it said then, and now', before=0, hold=3.5)


@clip('reanchor', 'Attach a detached annotation to the text where it belongs now', file=CHANGED, cursor=(1, 0))
def _(c):
    c.step(' md', '"parking near the square" was deleted (detached)')
    c.text('parking', hold=1.5)
    c.step('<CR>', 'choose it', before=0)
    c.note('"Attach it to a selection"')
    c.text('selection', hold=1.5)
    c.more('<CR>', hold=2.0)
    c.goto(10, 18)
    c.step('v$h', 'select where its text is now')
    c.step(' mR', '<leader>mR attaches it', before=0, hold=3.0)
    c.mark_still()


@clip('qf', '<leader>mq: this file\'s annotations in the quickfix list', file=ESSAY, cursor=(1, 0))
def _(c):
    c.step(' mq', 'one line per annotation: place, name, text, tags, note', hold=3.5)
    c.mark_still()


@clip('diff', '<leader>mD: what the annotated text said then, and now', file=CHANGED, cursor=(8, 22))
def _(c):
    c.note('"grew by 40%" was rewritten to "shrank to 4%" outside Neovim')
    c.shot(3.0)
    c.step(' mD', 'removed in red, added in green', hold=3.5)
    c.mark_still()


@clip('occurrences', '<leader>mo: give every other occurrence the same labels', file=ESSAY, cursor=(12, 19))
def _(c):
    c.step('4ghiw', 'label 4 on one "treasurer"')
    c.step(' mo', 'the other "treasurer" (line 15) gets label 4 too', hold=3.0)
    c.mark_still()


@clip('regrow', '<leader>mg{motion}: move an annotation onto other text', file=ESSAY, cursor=(3, 16))
def _(c):
    c.step(' mg$', '"approved the annual budget" grows to the end of the line ($)')
    c.step('l', 'its note, name and labels stay', before=0, hold=3.0)
    c.mark_still()


@clip('cycle-set', '<leader>ms switches to the next label set', file=FRESH, cursor=(3, 0))
def _(c):
    c.step('1ghiww2ghiww3ghiw', 'labels 1 to 3 of "vivid" (the default set)')
    c.step(' ms', 'next set: a popup shows its colours', hold=3.0)
    c.mark_still()
    c.step('w1ghiww2ghiww3ghiw', 'the same counts now use "pastel"; old ones keep theirs')


@clip('pick-set', '<leader>mS chooses the label set from a list', file=FRESH, cursor=(3, 0))
def _(c):
    c.step(' mS', 'the five default sets and the project\'s "review" set', hold=3.0)
    c.mark_still()
    c.note('choose one')
    c.text('cyber', hold=1.5)
    c.step('<CR>', 'the statusline now shows cyber\'s colours', before=0)
    c.step('1ghiww2ghiww3ghiw', 'labels 1 to 3 of "cyber"')


@clip('palette', '<leader>mc: the palette, every label of the set at a glance', file=ESSAY, cursor=(3, 20))
def _(c):
    c.step(' mc', 'each label as a colour patch: your name, the colour\'s name, hex and uses', hold=3.5)
    c.mark_still()
    c.step('5', 'a digit jumps to that key: 5 ("Vague")', before=0, hold=2.0)
    c.step('<Tab>', 'Tab shows the next set', before=0, hold=2.5)
    c.step('<S-Tab>', 'Shift-Tab goes back', before=0)
    c.step('<CR>', 'Enter makes label 5 the one gh offers first (see the statusline)', before=0, hold=3.0)


@clip('color', ':Earmark color recolours a label in this file only', file=ESSAY, cursor=(3, 20))
def _(c):
    c.ex('Earmark color #ff79c6', 'label 3 ("Claim") becomes pink in this file', hold=3.0)
    c.mark_still()
    c.ex('Earmark color reset', 'and back to its own colour')


# ------------------------------------------------------------- Notes and the hover ----------

@clip('note', '<leader>mm: write a note on an annotation', file=ESSAY, cursor=(4, 40), typo=True)
def _(c):
    c.step(' mm', 'a Markdown note opens under the text, in Insert mode')
    c.note('#tags and @identifiers anywhere in the note are picked up')
    c.text('Ask when the wing was first proposed. #todo @council', hold=2.0)
    c.step('<Esc>q', 'q saves and closes', before=0)
    c.step('h', 'a pencil at the end of the line; the hover shows the note', before=0, hold=3.5)
    c.mark_still()


@clip('note-split', 'A note can move to a split (,s) and back to a float (,f)', file=ESSAY, cursor=(3, 20))
def _(c):
    c.step(' mm', 'open the note of "approved the annual budget"')
    c.step(',s', ',s: the note in a split at the bottom', before=0)
    c.mark_still()
    c.step(',f', ',f: back to the float', before=0)
    c.step('q', 'q saves and closes', before=0)


@clip('hover', 'The hover: rest the cursor on an annotation', file=ESSAY, cursor=(7, 3))
def _(c):
    c.step('jj', 'down onto "vague promise": the hover shows its name, tags and note, focus stays here',
           hold=3.5)
    c.mark_still()
    c.step('kk', 'move off "vague promise": the hover goes away', hold=2.0)
    c.step('jj', 'back on: it shows again', hold=3.0)


@clip('hover-overlap', 'Overlapping annotations: the hover lists them innermost first', file=ESSAY, cursor=(3, 34))
def _(c):
    c.step('h', '"budget" (label 7) inside "approved the annual budget" (label 3)', hold=4.0)
    c.mark_still()


@clip('hover-toggle', '<leader>mh turns the automatic hover off and on', file=ESSAY, cursor=(7, 3))
def _(c):
    c.step(' mh', 'hover off')
    c.step('jj', 'onto "vague promise": nothing shows now', hold=2.5)
    c.mark_still()
    c.step(' mh', 'on again')
    c.step('kj', 'move off and back: it shows', hold=3.0)


@clip('peek', '<leader>mi: show the details float now, and enter it', file=ESSAY, cursor=(11, 3))
def _(c):
    c.step(' mi', 'the cursor is inside: scroll or copy from it', hold=3.0)
    c.mark_still()
    c.step('q', 'q closes', before=0)


@clip('tags', '<leader>mt: add or remove tags', file=ESSAY, cursor=(9, 2))
def _(c):
    c.step(' mt', 'every tag you have used, to toggle on this annotation', hold=3.0)
    c.mark_still()
    c.note('choose "todo"')
    c.text('todo', hold=1.5)
    c.more('<CR>', hold=2.0)
    c.step('<Esc>', 'done', before=0)
    c.step(' mv', '<leader>mv shows tags at the ends of lines', before=0, hold=3.0)


# ------------------------------------------------------------------ Indicators -------------

@clip('indicators', 'End-of-line indicators: pencils for notes; <leader>mv shows tags too', file=ESSAY, cursor=(1, 0))
def _(c):
    c.note('a pencil for each note, in the label colour (always shown)')
    c.shot(3.0)
    c.step(' mv', '<leader>mv: #tags, and @identifiers as [A]', hold=3.5)
    c.mark_still()
    c.step(' mv', '<leader>mv again hides them (hidden at startup)', hold=2.5)


# -------------------------------------------------------------- Overlaps --------------------

def build_overlaps(c):
    c.note('building the example')
    c.goto(3, 12)
    c.keys('v3e2gh')            # line 3: "the library for" = 2
    c.goto(3, 16)
    c.keys('5ghiw')             # "library" = 5 inside it
    c.goto(4, 4)
    c.keys('4gh3e')             # line 4: "reading room is" = 4
    c.goto(4, 12)
    c.keys('4gh2e')             # "room is" = 4
    c.keys('4ghiw')             # "room" = 4
    c.goto(5, 0)
    c.keys('6ghiw')             # line 5: "leaks" = 6
    for k in '389':             # + labels 3, 8, 9 on the same span (a = add, at the question)
        c.keys(k + 'ghiw')
        c.keys('a')
    c.goto(7, 22)
    c.keys('7ghiw')             # line 7: "budget" = 7, then rewritten
    c.keys('ciwmoney<Esc>')
    c.goto(11, 0)


OVERLAP_LEGEND = [
    'Line 3: different labels overlap. "the library for" = 2, "library" = 5 inside it: the overlap is the mix of '
    'both colours, underlined in the outer colour.',
    'Line 4: the same label nested: "reading room is", "room is", "room" all = 4. Each inner level is a deeper '
    'shade of the same colour, like highlighter strokes crossing.',
    'Line 5: one word, four labels: 6 is the fill; the undercurl is cut into three runs, one each for 3, 8 and 9. '
    'Nothing is added to the line, so the text after it does not move.',
    'Line 7: "budget" (label 7) was retyped as "money": the annotation is now stale, its fill faded and a dashed '
    'underline.',
]


@clip('overlaps', 'What overlaps look like (default: overlap.style = "blend")', file=FRESH, still=True,
      legend=OVERLAP_LEGEND, zoom=(0.0, 0.11, 0.6, 0.22))
def _(c):
    build_overlaps(c)
    still(c)


@clip('overlaps-squares', 'Overlaps with overlap = { extra = "squares" }: a square per extra label', file=FRESH,
      still=True, opts="{ overlap = { extra = 'squares' } }", zoom=(0.0, 0.11, 0.6, 0.22),
      legend=['The same annotations with squares: line 5 keeps the undercurl for label 3 and adds a small square '
              'after the word for each label from the third on. The squares take room, so the line shifts.'])
def _(c):
    build_overlaps(c)
    still(c)


@clip('light-theme', 'Colours adapt to the background: the same labels on a light theme', file=ESSAY, cursor=(3, 20))
def _(c):
    c.note('a dark theme: the labels as they were designed')
    c.shot(3.0, wait=0.5)
    c.ex('colorscheme tokyonight-day', 'a light theme: each colour is darkened to stay as readable',
         hold=3.5)
    c.mark_still()
    c.ex('colorscheme tokyonight-night', 'and back: the colours return to their originals', hold=2.5)


@clip('overlaps-top', 'Overlaps with overlap = { style = "top" }: the smallest span on top', file=FRESH, still=True,
      opts="{ overlap = { style = 'top' } }", zoom=(0.0, 0.11, 0.6, 0.22),
      legend=['The same annotations as above with blending off: where spans overlap, the smaller one is drawn on '
              'top in its own colour. Underlines, undercurls and squares are the same.'])
def _(c):
    build_overlaps(c)
    still(c)


# --------------------------------------------------------- Configure / sets / statusline -----

@clip('keymaps', 'The default keys, as Neovim lists them (:nmap, in a buffer)', file=ESSAY, still=True)
def _(c):
    c.note('')
    c.keys(':')
    c.text("enew | put =execute('filter /earmark/ nmap') | setl nowrap", hold=0.5)
    c.more('<CR>gg', hold=1.0)
    still(c)


@clip('custom-set', 'A label set of your own, from setup()', file=FRESH, cursor=(5, 32),
      opts="{ sets = { 'vivid', feedback = { labels = { { key = 'c', name = 'contradiction', color = '#e06c75' }, "
           "{ key = 'v', name = 'vague' }, 'cut this' } } } }")
def _(c):
    c.step(' mS', 'setup() defined a set "feedback" with named labels')
    c.text('feedback', hold=1.0)
    c.more('<CR>', hold=1.5)
    c.step('ghiw', 'its labels in the prompt: keys c, v, 3 and their names', hold=3.0)
    c.mark_still()
    c.step('cut', 'names match as you type', before=0)
    c.step('<CR>', 'applied', before=0, hold=3.0)


@clip('set-files', 'Label set files: questions with choices (rubrics, surveys)', file=ESSAY, cursor=(7, 32))
def _(c):
    c.step(' mS', 'the project has .earmark/sets/review.json')
    c.text('review', hold=1.0)
    c.more('<CR>', hold=1.5)
    c.step('gh3e', 'its labels: q1 Accuracy, q2 Tone', hold=3.0)
    c.step('<CR>', 'q1 asks for a choice', before=0, hold=3.0)
    c.mark_still()
    c.step('<C-n><CR>', '"Minor issue" asks for a line of text', before=0)
    c.text('should say bridges', hold=1.5)
    c.step('<CR>', 'saved', before=0)
    c.step('<Esc>l', 'the hover: Accuracy · b Minor issue, and the text', before=0, hold=3.5)


@clip('statusline', 'The statusline', file=CHANGED, still=True, cursor=(1, 0),
      legend=['require("earmark").statusline(), at the right of the bottom line: a swatch and the label the next '
              'gh uses (vivid·1), the number of annotations (4), notes (pencil 1), ⚠ detached or ambiguous ones (1), '
              'and the digits 1234567890 in the current set\'s colours.'])
def _(c):
    still(c)


# ------------------------------------------------------------------ Storage ------------------

@clip('live-edits', 'Annotations follow the text through edits, and come back on undo', file=ESSAY, cursor=(3, 0))
def _(c):
    c.step('OA new first line.<Esc>', 'insert a line above: everything moves down with the text')
    c.step('jdd', 'delete an annotated line: detached, not dropped')
    c.mark_still()
    c.step('u', 'undo: it comes back')


@clip('external-edit', 'An edit made outside Neovim: annotations stay on their words', file=ESSAY, cursor=(1, 0), typo=True)
def _(c):
    c.ex("!sed -i '2a The council met late on Tuesday.\\n' %",
         'add two lines near the top with sed, outside Neovim', hold=1.5)
    c.more('<CR>', hold=0.5)
    c.ex('e', 'reloaded: every highlight moved down with its words', hold=3.0)
    c.mark_still()


@clip('external-edit-inline', 'An outside edit inside an annotated line', file=ESSAY, cursor=(1, 0))
def _(c):
    c.ex("!sed -i 's/The committee approved/After midnight, the committee finally approved/' %",
         'insert words before "approved" on line 3, outside Neovim', hold=1.5)
    c.more('<CR>', hold=0.5)
    c.ex('e', 'reloaded: still on "approved the annual budget"', hold=3.5)
    c.mark_still()


@clip('check', ':Earmark check: how each annotation was placed', file=CHANGED, still=True)
def _(c):
    c.note('')
    c.keys(':')
    c.text('Earmark check', hold=0.5)
    c.more('<CR>', hold=1.0)  # output waits for Enter, which also blocks RPC: no still() here
    c.mark_still()


@clip('scratch', 'Scratch buffers keep their annotations: :Earmark scratch', file=FRESH, cursor=(1, 0), typo=True)
def _(c):
    c.ex('enew', 'a new unnamed buffer', hold=1.0)
    c.keys('i')
    c.text('call the plumber after lunch.', hold=0.5)
    c.step('<Esc>0w3gh2e', 'annotate "the plumber"')
    c.ex('bwipeout!', 'throw the buffer away', hold=1.5)
    c.ex('Earmark scratch', 'reopen it', hold=2.0)
    c.step('<CR>', 'text and annotation are back', before=0, hold=3.0)
    c.mark_still()


@clip('export', '<leader>me: export this file\'s annotations to Markdown', file=ESSAY, cursor=(1, 0))
def _(c):
    c.step(' me', 'it asks where; the default is .earmark/export/<project>-<file>.md', hold=3.0)
    c.step('<CR>', 'grouped by label, with names, lines, tags and notes', before=0, hold=4.0)
    c.mark_still()


@clip('health', ':checkhealth earmark', file=ESSAY, still=True)
def _(c):
    c.note('')
    c.keys(':')
    c.text('checkhealth earmark', hold=0.5)
    c.more('<CR>', hold=1.0)
    still(c)
