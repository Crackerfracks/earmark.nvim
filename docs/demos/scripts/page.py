#!/usr/bin/env python3
"""Writes docs/demos/index.html from the clips in docs/demos (README order, one card each).

    python3 docs/demos/scripts/page.py
"""
import html
import os
import re

OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))

ESSAY, FRESH, CHANGED = 'notes/essay.md', 'notes/fresh.md', 'notes/changed.md'

# Each card: clip, title, file, steps (list of (where/what, keys)), what, why, default (or None).
# `keys` is written in Vim notation; <leader> is Space.
SECTIONS = []


def section(name, intro=''):
    SECTIONS.append((name, intro, []))


def card(clip, title, file, steps, what, why, default=None):
    SECTIONS[-1][2].append(dict(clip=clip, title=title, file=file, steps=steps, what=what, why=why, default=default))


# ---------------------------------------------------------------------------------------------
section('Annotate', 'Marking text with a label: the operator <code>gh</code>, with or without a count.')
card('annotate-count', 'A count picks the label', FRESH,
     [('put the cursor on "library"', '/library<CR>'), ('label 3 on the word', '3ghiw'),
      ('next line, start', 'j0'), ('label 12 to the end of the line', '12gh$')],
     'The word "library" turns label 3\'s colour; then a whole line segment takes label 12. The statusline swatch '
     'at the bottom right shows the label the next <code>gh</code> uses.',
     'This is the fast path: the count is the label, so marking text is one motion, like any Vim operator.',
     'Default key: <code>gh</code> is the operator (it replaces Select mode\'s <code>gh</code>).')
card('default-labels', 'The default labels', FRESH,
     [('line 3', '3G0'), ('labels 1 to 5', '1ghiww2ghiww3ghiww4ghiww5ghiw'),
      ('labels 6 to 10', 'w6ghiww7ghiww8ghiww9ghiww10ghiw')],
     'Labels 1 to 10 of the default set "vivid", one per word. The digits <code>1234567890</code> in the statusline '
     'use the same colours, so you can see which number is which colour.',
     'You pick labels by number, so the colours have to be easy to tell apart.',
     'Default: five generated sets (vivid, pastel, earth, metal, cyber), the same on any background '
     '(item 6 of the defaults you are asked to confirm: no per-background palettes).')
card('label-shades', 'Labels 11 to 99: shades', FRESH,
     [('line 4', '4G0'), ('labels 1, 11, 21, 31, 41', '1ghiww11ghiww21ghiww31ghiww41ghiw')],
     'Five words with labels 1, 11, 21, 31 and 41: one colour family in different shades. The last digit picks '
     'the colour, the tens digit the shade.',
     'Ninety-nine labels without ninety-nine unrelated colours.')
card('annotate-line', 'A whole line: ghh', FRESH, [('line 7', '7G'), ('label 4 on the line', '4ghh')],
     'The whole line takes label 4.', 'Quicker than <code>gh$</code> from the start of the line.',
     'Default key: <code>ghh</code>. (Typed slowly, Neovim waits <code>timeoutlen</code> before running it.)')
card('annotate-visual', 'A selection: Visual mode then {count}gh', FRESH,
     [('on "the library"', '/the library<CR>'), ('select three words', 'v3e'), ('label 6', '6gh')],
     'Three selected words become one annotation with label 6.', 'For spans that no motion describes well.')
card('annotate-block', 'A Visual block: one annotation per line', FRESH,
     [('line 7, start', '7G0'), ('a block over three lines', '<C-v>jj3e'), ('label 2', '2gh')],
     'Three separate annotations, one per line of the block.', 'Columns and lists.')
card('repeat', 'Repeat with .', FRESH,
     [('on "reading"', '/reading<CR>'), ('label 7', '7ghiw'), ('two words on, repeat', 'ww.'), ('again', 'w.')],
     'Each <code>.</code> marks another word with the same label, no prompt.', 'Marking a run of things the same way.')
card('same-span', 'The same word twice: both labels stay', FRESH,
     [('on "places"', '/places<CR>'), ('label 3', '3ghiw'), ('label 5 on the same word', '5ghiw'),
      ('label 5 again', '5ghiw'), ('rest on it', 'l')],
     'The second label is added to the annotation (it shows as an overlap); repeating a label it already has does '
     'nothing. The hover lists both.',
     'This is the old complaint about overlapping highlights on one word: both labels stay visible.',
     'Default to confirm (item 13): another label on exactly the same span is added, not swapped; '
     '<code>&lt;leader&gt;ml</code> swaps.')

section('The label prompt', '<code>gh</code> without a count opens a small prompt beside the text.')
card('prompt', 'gh without a count opens the prompt', FRESH,
     [('line 7', '7G'), ('open the prompt on the paragraph', 'ghip'), ('type a key', '12'), ('apply', '<CR>'),
      ('skip naming', '<Esc>')],
     'The prompt opens beside the paragraph. Typing <code>12</code> recolours the paragraph live and lists 12 and its '
     'shades; Enter applies it. Because 12 is new in this project, it then asks for a name; Esc skips that.',
     'You see the colour on your text before you commit to it.',
     'Default to confirm (item 7): <code>gh</code> without a count always opens the prompt.')
card('prompt-name', 'First use of a label: name it', FRESH,
     [('line 7', '7G'), ('label 12 on the paragraph', 'ghip12<CR>'), ('type a name', 'staffing'),
      ('save the name', '<CR>')],
     'After Enter the prompt switches to "12 name"; typing <code>staffing</code> and Enter names label 12. The hover '
     'then shows the name.',
     'Numbers are hard to remember; names are matched when you type in the prompt and shown in the hover, pickers and export.',
     'Default to confirm (item 1): <code>prompt.ask_name = \'first_use\'</code> asks the first time a label is used in a '
     'project, and that name then applies in the project\'s other files (item 12: <code>.earmark/names.json</code> is committed).')
card('prompt-last', 'Empty input: the last label first', ESSAY,
     [('on "roads"', '/roads<CR>'), ('open the prompt', 'ghiw'), ('apply the first candidate', '<CR>')],
     'With nothing typed, the list starts with the last label used, then the labels already used in this file, '
     'with their names and how often they are used. Enter applies the first.',
     'Re-using the label you just used is one key.',
     'Default to confirm (item 7): Enter on empty input re-uses the last label.')
card('prompt-names', 'Type part of a name', ESSAY,
     [('on "roads"', '/roads<CR>'), ('open the prompt', 'ghiw'), ('type part of a name', 'vag'), ('apply', '<CR>')],
     '"vag" narrows the list to label 5, named "Vague".', 'Find labels by what they mean, not by number.')
card('prompt-shades', 'Type a digit: the key, then its shades', ESSAY,
     [('on "explain"', '/explain<CR>'), ('open the prompt', 'ghiw'), ('type 3', '3'),
      ('move down twice', '<C-n><C-n>'), ('apply, skip naming', '<CR><Esc>')],
     'Typing 3 lists 3, then 13, 23, 33 and so on; Ctrl-n moves down and the text follows the selection.',
     'Browse a colour family without remembering numbers.')
card('prompt-sets', 'Ctrl-s: try the next label set', ESSAY,
     [('on "explain"', '/explain<CR>'), ('label 3', 'ghiw3'), ('next set, twice', '<C-s><C-s>'),
      ('apply', '<CR><Esc>')],
     'The prompt title changes from vivid to pastel to earth, and the text shows label 3 of each.',
     'Compare sets without leaving the prompt.')
card('prompt-tab', 'Tab: name the label; Shift-Tab: back', FRESH,
     [('on "roof"', '/roof<CR>'), ('label 5', 'ghiw5'), ('name stage', '<Tab>'), ('back', '<S-Tab>'),
      ('cancel', '<Esc><Esc>')],
     'Tab applies the label and moves to the name stage; Shift-Tab goes back to choosing the label.',
     'Name a label in the same breath as using it.')
card('prompt-normal', 'Esc: Normal mode in the prompt; Esc again cancels', FRESH,
     [('on "roof"', '/roof<CR>'), ('label 5', 'ghiw5'), ('Normal mode', '<Esc>'), ('move', 'jj'),
      ('cancel', '<Esc>')],
     'After Esc, <code>j</code>/<code>k</code> move through the candidates; a second Esc closes the prompt and the '
     'word is left unmarked.',
     'Vim keys work in the prompt, and cancelling never leaves a half-made annotation.')

section('Change and erase')
card('relabel', 'Change the label: <leader>ml', ESSAY,
     [('on "vague promise"', '/vague<CR>'), ('change the label', '<leader>ml'), ('to 2', '2<CR>'),
      ('skip naming', '<Esc>')],
     '"vague promise" changes from label 5 ("Vague") to label 2.', 'Fix a mislabel without erasing.',
     'Default key: <code>&lt;leader&gt;ml</code> (a count picks among overlapping annotations).')
card('add-label', 'Add another label: <leader>ma', ESSAY,
     [('on "vague promise"', '/vague<CR>'), ('add a label', '<leader>ma'), ('label 6', '6<CR><Esc>'),
      ('rest on it', 'jk')],
     'The second label shows as an undercurl in its colour under the text; the hover lists both labels.',
     'One phrase can be two things at once (vague and a quote).',
     'Default to confirm (item 3): a second label is an undercurl; labels 3 and up are small squares after the span.')
card('rename', 'Name or rename a label: <leader>mr', ESSAY,
     [('on "approved"', '/approved<CR>'), ('rename', '<leader>mr'), ('clear the old name', '<C-u>'),
      ('new name', 'Disputed<CR>')],
     'Label 3 was "Claim"; after renaming, both label-3 annotations show "Disputed".',
     'Names belong to the label in this file, so one rename updates every use.')
card('erase-restore', 'Erase one, restore it: <leader>mx, <leader>mu', ESSAY,
     [('on "new library"', '/new library<CR>'), ('erase', '<leader>mx'), ('restore', '<leader>mu')],
     '"new library" loses its colour, then gets it back.', 'Erasing is safe: the last batch comes back.')
card('erase-visual', 'Erase a selection: Visual <leader>mx', ESSAY,
     [('line 3', '3G'), ('select three lines', 'Vjj'), ('erase', '<leader>mx'), ('restore', '<leader>mu')],
     'Every annotation in the selected lines disappears, then comes back.', 'Clear an area at once.')
card('clear-all', 'Erase everything: <leader>mX', ESSAY,
     [('erase all', '<leader>mX'), ('restore', '<leader>mu')],
     'All annotations go, then all come back.', 'Start over without losing work for good.')

section('Move around and find')
card('next-prev', 'Next / previous: <leader>mn, <leader>mN', ESSAY,
     [('top of the file', 'gg'), ('next, next', '<leader>mn<leader>mn'), ('previous', '<leader>mN')],
     'The cursor jumps from annotation to annotation.', 'Read through your marks in order. Wraps at the ends.')
card('next-same', 'Same label only: <leader>m], <leader>m[', ESSAY,
     [('on "approved"', '/approved<CR>'), ('next with this label', '<leader>m]'), ('again (wraps)', '<leader>m]')],
     'From "approved the annual budget" (label 3) to "new library" (also 3), then back.',
     'Walk through every "Claim" and skip the rest.')
card('jump', 'Jump labels: <leader>mj', ESSAY, [('show jump labels', '<leader>mj'), ('jump to the 3rd', 'd')],
     'flash.nvim puts a letter on each visible annotation; typing one jumps there.',
     'Two keystrokes to any mark on screen. Without flash.nvim this opens the picker.')
card('pick', 'Pick in this file: <leader>mp', ESSAY,
     [('open the picker', '<leader>mp'), ('filter by tag', '#todo'), ('jump', '<CR>')],
     'Each line shows the label name, the text, its tags and the first line of its note; typing filters.',
     'Find an annotation by what you wrote about it.', 'Default: <code>picker = \'auto\'</code> (snacks.nvim here, then telescope, else vim.ui.select).')
card('pick-all', 'Pick in the whole project: <leader>mP', ESSAY,
     [('open the project picker', '<leader>mP'), ('filter', 'votes'), ('open it', '<CR>')],
     'Annotations from every file in the project; choosing one opens its file.', 'Search all your notes at once.')
card('pick-query', 'Queries: :Earmark pick_all', ESSAY,
     [('pick with a query', ':Earmark pick_all has:note #todo<CR>')],
     'Only annotations that have a note and the tag #todo.',
     'Query words: <code>#tag</code>, <code>@ident</code>, <code>label:</code>, <code>set:</code>, '
     '<code>status:ok|stale|ambiguous|detached</code>, <code>has:note</code>, <code>has:tags</code>, or any text.')
card('qf-query', 'Queries into the quickfix list: :Earmark qf', ESSAY,
     [('query into quickfix', ':Earmark qf all #todo<CR>')],
     'Every #todo in the project, as quickfix entries.', 'Use <code>:cnext</code> and friends across files.')
card('qf', 'This file into quickfix: <leader>mq', ESSAY, [('quickfix', '<leader>mq')],
     'One quickfix line per annotation: position, name, text, tags and note.', 'A plain list you can keep open.')

section('When the text changes', 'Annotations stay attached when the text is edited, reformatted or changed '
        'outside Neovim. When the annotated text itself is rewritten, the annotation is <b>stale</b>; when it is '
        'gone, <b>detached</b>, never dropped.')
card('live-edits', 'Edits, deletes and undo', ESSAY,
     [('on line 3', '3G'), ('insert a line above', 'OA new first line.<Esc>'), ('delete an annotated line', 'jdd'),
      ('undo', 'u')],
     'Annotations move down with the text; deleting the line removes its highlight; undo brings it back.',
     'Highlights that break on every edit are useless; these follow the text.')
card('external-edit', 'Edits outside Neovim', ESSAY,
     [('add two lines near the top with sed', ":!sed -i '2a The council met late on Tuesday.\\n' %<CR>"),
      ('reload', ':e<CR>')],
     'The file was changed behind Neovim\'s back, then reloaded with <code>:e</code>. Every annotation moves down '
     'with its words; nothing is left behind at the old places.',
     'Formatters, git checkouts and other editors change files under you; the marks follow the text.',
     'Default to confirm (item 8): text snapshots in <code>.earmark/snap/</code> are gitignored, so a fresh clone '
     're-anchors by quote and context only.')
card('external-edit-inline', 'An outside edit inside an annotated line', ESSAY,
     [('insert words before "approved" with sed',
       ":!sed -i 's/The committee approved/After midnight, the committee finally approved/' %<CR>"),
      ('reload', ':e<CR>')],
     'Words are added in front of the annotation on the same line. After <code>:e</code> the highlights are still '
     'on "approved the annual budget" and "budget", not at the old columns.',
     'Re-anchoring works by the words, not by line and column.')
card('review', 'Review what changed: <leader>md', CHANGED,
     [('open the review list', '<leader>md'), ('choose the first', '<CR>'), ('Compare', '<C-n><CR>')],
     'notes/changed.md was annotated, then edited outside Neovim: "grew by 40%" became "shrank to 4%" (stale) and '
     'the parking paragraph was deleted (detached). The list shows both; choosing one offers jump, compare, accept, '
     'attach or erase.', 'Nothing is silently lost: you decide what happens to each.')
card('diff', 'Compare then and now: <leader>mD', CHANGED,
     [('on "shrank"', '/shrank<CR>'), ('compare', '<leader>mD')],
     'A float: what the text said when you annotated it, and what it says now, with the changed characters marked.',
     'See whether your note still applies.')
card('reanchor', 'Attach a detached annotation: <leader>mR', CHANGED,
     [('review list', '<leader>md'), ('choose "parking"', 'parking<CR>'), ('"Attach it to a selection"', 'selection<CR>'),
      ('on "where"', '/where<CR>'), ('select to the end', 'v$h'), ('attach', '<leader>mR')],
     'The deleted annotation is given the new sentence about parking; the ⚠ in the statusline goes away.',
     'Keep a note and labels when the text was rewritten elsewhere.')
card('check', ':Earmark check', CHANGED, [('check', ':Earmark check<CR>')],
     'How each annotation was placed: ok/stale/detached, how sure, and where.',
     'Also works headless in scripts (exit status 1 if any is detached).')
card('occurrences', 'Every occurrence: <leader>mo', ESSAY,
     [('on "treasurer" (line 12)', '12G/treasurer<CR>'), ('label 4', '4ghiw'), ('the other occurrences', '<leader>mo')],
     'The other "treasurer" on line 15 gets label 4 too.', 'Mark a name everywhere it appears.',
     'Behaviour to confirm: <code>&lt;leader&gt;mo</code> has no one-step undo (erase the extra ones with <code>&lt;leader&gt;mx</code>).')
card('regrow', 'Move an annotation: <leader>mg', ESSAY,
     [('on "approved"', '/approved<CR>'), ('grow it to the end of the line', '<leader>mg$')],
     '"approved the annual budget" becomes "approved the annual budget yesterday"; its note, name and labels stay.',
     'Fix the extent of a mark without redoing it.',
     'Behaviour to confirm: <code>&lt;leader&gt;mg</code> accepts the new text as the annotation\'s text.')

section('Label sets')
card('cycle-set', 'Next set: <leader>ms', FRESH,
     [('line 3', '3G0'), ('labels 1-3', '1ghiww2ghiww3ghiw'), ('next set', '<leader>ms'),
      ('labels 1-3 again', 'w1ghiww2ghiww3ghiw')],
     'A popup shows the new set\'s colours; the same counts now give pastel colours, and the earlier words keep vivid.',
     'Different sets for different jobs, switched in one key.')
card('pick-set', 'Choose a set: <leader>mS', FRESH,
     [('set list', '<leader>mS'), ('choose cyber', 'cyber<CR>'), ('labels 1-3', '1ghiww2ghiww3ghiw')],
     'The five default sets plus the project\'s own "review" set; after choosing "cyber" the statusline digits change.',
     'Jump straight to the set you want.')
card('custom-set', 'Your own set in setup()', FRESH,
     [('start with the option', "EARMARK_DEMO_OPTS=\"{ sets = { 'vivid', feedback = { labels = { { key = 'c', name = 'contradiction', color = '#e06c75' }, { key = 'v', name = 'vague' }, 'cut this' } } } }\" nvim -u ../init.lua notes/fresh.md"),
      ('choose it', '<leader>mSfeedback<CR>'), ('on "heating"', '/heating<CR>'),
      ('prompt', 'ghiw'), ('by name', 'cut<CR>')],
     'A set "feedback" with labels "contradiction", "vague" and "cut this" (keys c, v, 3); the prompt matches names. '
     'Recorded with <code>sets = { \'vivid\', feedback = { labels = { { key = \'c\', name = \'contradiction\', color = '
     '\'#e06c75\' }, { key = \'v\', name = \'vague\' }, \'cut this\' } } }</code>.',
     'Labels with meaning for your own workflow.')
card('set-files', 'Set files with questions', ESSAY,
     [('choose the project\'s set', '<leader>mSreview<CR>'), ('on "roads were in"', '/roads<CR>'),
      ('prompt', 'gh3e'), ('q1 Accuracy', '<CR>'), ('"Minor issue"', '<C-n><CR>'), ('the text', 'should say bridges<CR>'),
      ('look', '<Esc>l')],
     'The project file <code>.earmark/sets/review.json</code> defines q1 "Accuracy" with choices; "Minor issue" asks for '
     'a line of text. The hover shows <code>Accuracy · b Minor issue</code> and the text.',
     'Rubrics, surveys and structured review, not just colours.',
     'Behaviour to confirm: set files are reloaded by checking their modification time on focus and buffer switches.')
card('color', 'Recolour a label in this file: :Earmark color', ESSAY,
     [('on "approved"', '/approved<CR>'), ('recolour', ':Earmark color #ff79c6<CR>'), ('undo it', ':Earmark color reset<CR>')],
     'Label 3 turns pink in this file only, then back.', 'Fix a colour clash in one document.')

section('Notes and the hover')
card('note', 'Write a note: <leader>mm', ESSAY,
     [('on "new library"', '/new library<CR>'), ('open the note', '<leader>mm'),
      ('type', 'Ask when the wing was first proposed. #todo @council'), ('save', '<Esc>q'), ('rest on it', 'h')],
     'The note opens under the text in Insert mode; <code>q</code> saves. A pencil ✎ appears at the end of the line and '
     'the hover shows the note.', 'Your thoughts sit on the text they are about.',
     'Default: <code>note.layout = \'float\'</code>.')
card('note-split', 'Note in a split: ,s and ,f', ESSAY,
     [('on "approved"', '/approved<CR>'), ('open the note', '<leader>mm'), ('to a split', ',s'), ('back', ',f'), ('close', 'q')],
     'The note moves to a split at the bottom and back to the float.', 'Longer notes get room.')
card('hover', 'The hover', ESSAY,
     [('on "vague promise"', '/vague<CR>'), ('move off and back', 'jjkk')],
     'Resting on an annotation with a name, note or tags shows a float with the label name (in its colour), tags and '
     'note, without taking focus; it goes away when you leave.', 'See what you wrote without opening anything.',
     'Default to confirm (item 4): the header is the label colour as text (<code>▍ name</code>), not a filled bar. '
     'Shown for annotations with a name or note (<code>hover.show_when = \'named_or_note\'</code>).')
card('hover-overlap', 'Overlaps in the hover', ESSAY,
     [('on "budget" (line 3)', '3G/budget<CR>')],
     '"budget" (label 7) sits inside "approved the annual budget" (label 3): the hover lists both, innermost first (①, ②).',
     'When marks overlap you can still read each one.')
card('hover-toggle', 'Hover off and on: <leader>mh', ESSAY,
     [('on "vague promise"', '/vague<CR>'), ('off', '<leader>mh'), ('move', 'jjkk'), ('on', '<leader>mh')],
     'With the hover off, resting on the annotation shows nothing.', 'Quiet reading when you want it.')
card('peek', 'Details now: <leader>mi', ESSAY,
     [('on "Revenue"', '/Revenue<CR>'), ('details', '<leader>mi'), ('close', 'q')],
     'The details float opens at once and the cursor goes inside it to scroll or copy.', 'Long notes.')
card('tags', 'Tags: <leader>mt', ESSAY,
     [('on "vague promise"', '/vague<CR>'), ('tags', '<leader>mt'), ('toggle todo', 'todo<CR>'), ('done', '<Esc>'),
      ('show tags', '<leader>mv')],
     'The list of every tag you have used; choosing one adds it. With <code>&lt;leader&gt;mv</code> the tags appear at the end of the line.',
     'Group marks across files (#todo, #source ...) and find them with the picker.')

section('Indicators')
card('indicators', 'Pencils, tags and identifiers', ESSAY,
     [('show tags', '<leader>mv'), ('hide them', '<leader>mv')],
     'A ✎ for each note at the end of its line, in the label\'s colour. <code>&lt;leader&gt;mv</code> adds the '
     '<code>#tags</code> and <code>@identifiers</code> (as <code>[minutes]</code>); nothing goes in the sign column.',
     'You can see where notes are without hovering.',
     'Defaults to confirm (items 2 and 5): <code>@A</code> in notes shows as <code>[A]</code>; tags and identifiers are '
     'hidden at startup, pencils always show.')

section('What overlaps look like', 'Still pictures; the zoomed crop shows the lines that matter at twice the size.')
card('overlaps', 'Overlaps (default: blend)', FRESH,
     [('line 3: "the library for"', '/the library<CR>v3e2gh'), ('"library" inside it', 'w5ghiw'),
      ('line 4: "reading room is"', '/reading<CR>4gh3e'), ('"room is", then "room"', 'w4gh2e4ghiw'),
      ('line 5: four labels on "leaks"', '5G06ghiw3ghiw8ghiw9ghiw'),
      ('line 7: rewrite "budget"', '/budget<CR>7ghiwciwmoney<Esc>')],
     'See the legend under the picture.',
     'Overlapping marks on the same words are all visible and you can tell where each starts and ends.',
     'Default to confirm (item 3): mixed colours with the outer colour as underline; second label undercurl; labels 3+ '
     'as squares (not a gradient or interleave).')
card('overlaps-top', "Overlaps with overlap = { style = 'top' }", FRESH,
     [('start with the option', "EARMARK_DEMO_OPTS=\"{ overlap = { style = 'top' } }\" nvim -u ../init.lua notes/fresh.md"),
      ('then the same keys as above', '')],
     'The same annotations with blending off.', 'The alternative to the default, for comparison.')

section('Configure')
card('keymaps', 'The default keys', ESSAY, [('list them', ':filter /earmark/ nmap<CR>')],
     'Every default Normal-mode mapping, as Neovim lists it.', 'The full set of defaults in one place.',
     'Defaults to confirm: all of <code>keys = { ... }</code> in the README\'s Configure section.')
card('statusline', 'The statusline', CHANGED, [('look at the bottom right', '')],
     'See the legend under the picture.', 'The current label and the state of the file at a glance.',
     'Default to confirm (item 9): the next label, counts, the warning count and the digit row.')
card('health', ':checkhealth earmark', ESSAY, [('run it', ':checkhealth earmark<CR>')],
     'What earmark found: Neovim version, storage, optional plugins.', 'First stop when something looks wrong.')

section('Storage and export')
card('scratch', 'Scratch buffers: :Earmark scratch', FRESH,
     [('new buffer', ':enew<CR>'), ('type', 'icall the plumber after lunch.<Esc>'), ('annotate', '0w3gh2e'),
      ('throw it away', ':bwipeout!<CR>'), ('reopen', ':Earmark scratch<CR><CR>')],
     'An unnamed buffer with an annotation is thrown away and reopened with its text and annotation.',
     'Quick notes in throwaway buffers are kept.')
card('export', 'Export to Markdown: <leader>me', ESSAY, [('export', '<leader>me'), ('accept the path', '<CR>')],
     'A Markdown file with every annotation grouped by label (with names), each with text, lines, tags and note, opened in a split.',
     'Share or archive your annotations outside Neovim.',
     'Default to confirm (item 11): exports go to <code>&lt;root&gt;/.earmark/export/&lt;project&gt;-&lt;path&gt;.md</code> '
     '(gitignored).')

SKIPPED = [
    ('zk (<code>&lt;leader&gt;mz</code>)', 'the <code>zk</code> program is not installed on this laptop, so zk-nvim cannot create notes.'),
    ('API and events', 'Lua functions for other plugins; nothing to see on screen.'),
    ('Ambiguous annotations (underdotted)', 'the demo project doesn\'t produce one.'),
    ('JSON-only storage (item 10)', 'nothing to see: records are plain JSON in <code>.earmark/docs/</code>.'),
]


def kbd(keys):
    return '<kbd>%s</kbd>' % html.escape(keys) if keys else ''


def render_card(c):
    clip = c['clip']
    gif, mp4, png, zoom = clip + '.gif', clip + '.mp4', clip + '.png', clip + '-zoom.png'
    ex = lambda f: os.path.exists(os.path.join(OUT, f))
    if ex(gif):
        media = '<a href="%s"><img src="%s" alt="%s" loading="lazy"></a>' % (gif, gif, html.escape(c['title']))
    elif ex(png):
        media = '<a href="%s"><img src="%s" alt="%s" loading="lazy"></a>' % (png, png, html.escape(c['title']))
    else:
        media = '<p class="missing">(not recorded)</p>'
    if ex(zoom):
        media += '<a href="%s"><img class="zoom" src="%s" alt="zoomed" loading="lazy"></a>' % (zoom, zoom)
    links = ' · '.join('<a href="%s">%s</a>' % (f, lbl) for f, lbl in
                       ((gif, 'GIF'), (mp4, 'MP4'), (png, 'still')) if ex(f))
    steps = ''.join('<li>%s %s</li>' % (html.escape(w), kbd(k)) for w, k in c['steps'])
    default = '<p class="default">%s</p>' % c['default'] if c['default'] else ''
    return ('<article id="%s" data-comment-target><h3><a href="#%s">%s</a> <button class="cbtn" hidden>&#128172; Comment</button></h3>%s<p class="links">%s</p>'
            '<p><b>What you are looking at:</b> %s</p><p><b>Why it matters:</b> %s</p>%s'
            '<div class="try"><b>Try it yourself</b> in <code>%s</code>:<ol>%s</ol></div></article>') % (
        clip, clip, html.escape(c['title']), media, links, c['what'], c['why'], default, c['file'], steps)


def main():
    toc, body = [], []
    n = 0
    for name, intro, cards in SECTIONS:
        sid = re.sub(r'[^a-z]+', '-', name.lower()).strip('-')
        toc.append('<li><a href="#%s">%s</a> <span>(%d)</span></li>' % (sid, html.escape(name), len(cards)))
        body.append('<h2 id="%s">%s</h2>' % (sid, html.escape(name)))
        if intro:
            body.append('<p class="lede">%s</p>' % intro)
        body.extend(render_card(c) for c in cards)
        n += len(cards)
    skipped = ''.join('<li><b>%s</b>: %s</li>' % s for s in SKIPPED)
    page = (TEMPLATE.replace('{toc}', '\n'.join(toc)).replace('{body}', '\n'.join(body))
            .replace('{skipped}', skipped).replace('{n}', str(n)))
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'tray.js')) as fh:
        page = page.replace('{tray_js}', fh.read())
    with open(os.path.join(OUT, 'index.html'), 'w') as fh:
        fh.write(page)
    print('wrote %s (%d cards)' % (os.path.join(OUT, 'index.html'), n))


TEMPLATE = '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>earmark.nvim demos</title>
<style>
:root { --bg: #16161e; --fg: #c0caf5; --dim: #8b93bf; --card: #1f2335; --accent: #e0af68; --link: #7aa2f7; --ok: #9ece6a; }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--fg); font: 17px/1.55 system-ui, sans-serif; }
main { max-width: 980px; margin: 0 auto; padding: 16px; }
h1 { margin: .2em 0 .4em; } h2 { margin-top: 2.2em; border-bottom: 1px solid #3b4261; padding-bottom: .2em; }
h3 { margin: 0 0 .6em; font-size: 1.15em; } h3 a { color: var(--fg); text-decoration: none; }
a { color: var(--link); }
article { background: var(--card); border-radius: 10px; padding: 14px; margin: 18px 0; }
article img { width: 100%; height: auto; border-radius: 6px; display: block; }
article img.zoom { margin-top: 8px; }
p { margin: .5em 0; }
kbd { background: #292e42; color: var(--accent); padding: 1px 6px; border-radius: 4px; font: .95em ui-monospace, monospace; white-space: pre-wrap; word-break: break-word; }
code { background: #292e42; padding: 0 4px; border-radius: 3px; font-size: .92em; word-break: break-word; }
.links { font-size: .85em; color: var(--dim); margin: .4em 0 .6em; }
.lede { color: var(--dim); }
.toc span { color: var(--dim); }
.default { border-left: 4px solid var(--accent); background: #2a2a2f; padding: 6px 10px; border-radius: 4px; }
.try { background: #16161e; border: 1px solid #3b4261; border-radius: 8px; padding: 8px 12px; margin-top: .8em; }
.try ol { margin: .3em 0 0; padding-left: 1.4em; } .try li { margin: .2em 0; }
.intro { background: var(--card); border-radius: 10px; padding: 12px 16px; }
.missing { color: #f7768e; }
.cbtn { float: right; font: 600 .8em system-ui, sans-serif; color: var(--bg); background: var(--accent); border: 0; border-radius: 6px; padding: 4px 10px; cursor: pointer; }
.cbtn:focus-visible, .tray button:focus-visible, .cbox button:focus-visible { outline: 2px solid var(--link); outline-offset: 2px; }
.cbox { margin: .6em 0; }
.cbox textarea { width: 100%; min-height: 5.5em; background: #16161e; color: var(--fg); border: 1px solid #3b4261; border-radius: 6px; padding: 8px; font: 15px/1.45 system-ui, sans-serif; resize: vertical; }
.cbox .row, .tray .row { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; margin-top: 6px; }
.cbox .hint, .tray .hint { color: var(--dim); font-size: .8em; }
.btn { font: 600 .85em system-ui, sans-serif; border: 1px solid #3b4261; background: #292e42; color: var(--fg); border-radius: 6px; padding: 5px 12px; cursor: pointer; }
.btn.primary { background: var(--accent); color: var(--bg); border-color: var(--accent); }
.btn:disabled { opacity: .5; cursor: default; }
.tray { position: fixed; right: 16px; bottom: 16px; width: min(420px, calc(100vw - 32px)); background: var(--card); border: 1px solid #3b4261; border-radius: 10px; box-shadow: 0 8px 28px #0009; z-index: 20; font-size: .92em; }
.tray header { display: flex; align-items: center; justify-content: space-between; gap: 8px; padding: 8px 12px; cursor: pointer; }
.tray header b { color: var(--accent); }
.tray .body { padding: 0 12px 12px; }
.tray ol { margin: 0; padding-left: 1.4em; max-height: 45vh; overflow: auto; }
.tray li { margin: .4em 0; }
.tray li .t { font-weight: 600; } .tray li .x { white-space: pre-wrap; word-break: break-word; }
.tray li .acts { font-size: .8em; } .tray li .acts a { margin-right: 10px; cursor: pointer; }
.tray .status { color: var(--dim); font-size: .85em; margin-top: 6px; } .tray .status.ok { color: var(--ok); } .tray .status.err { color: #f7768e; }
.tray.flash { animation: flash .6s; } @keyframes flash { 50% { box-shadow: 0 0 0 3px var(--accent); } }
main { padding-bottom: 120px; }
@media (max-width: 600px) { body { font-size: 16px; } main { padding: 10px; } article { padding: 10px; } }
</style>
</head>
<body><main>
<h1>earmark.nvim, feature by feature</h1>
<div class="intro">
<p><b>The idea.</b> earmark lets you <b>label spans of text</b> in Neovim with colours, the way you would
mark up a printed page with highlighters. Labels are numbered (and can be named), so <code>3ghiw</code> means
"mark this word with label 3".</p>
<p><b>Marks stay on the text.</b> Edit around them, reformat the file, change it in another program, undo:
each annotation stays on its words. If the words themselves are rewritten it is marked <i>stale</i>; if they
are deleted it is <i>detached</i> and kept, so nothing is silently lost.</p>
<p><b>Notes on labels.</b> Any annotation can carry a Markdown note with <code>#tags</code>; a small hover shows it
when the cursor rests there, and pickers, the quickfix list and a Markdown export find it again.</p>
<p><b>How to read the clips.</b> The blue bar at the top says what the clip shows. The box under the editor
shows a note for the current step and, on the yellow line, the <b>keys as they are typed</b>, one at a time
(<code>&lt;leader&gt;</code> is Space). Each step waits a moment before the keys, so you can read the note, and
holds the result a few seconds; the keys stay up until the next step starts. Every clip uses
earmark's <b>default settings</b> unless its card says otherwise. Boxes marked like this one call out a default
you are asked to confirm:</p>
<p class="default">Default to confirm (item N): … (the numbers are the list at the end of the README, under "Status").</p>
<p><b>Try it yourself.</b> Run <code>make demo</code> in the repository, then
<code>cd /tmp/earmark-demo/proj &amp;&amp; nvim -u ../init.lua notes/essay.md</code> (open the other files with
<code>:e notes/fresh.md</code> and <code>:e notes/changed.md</code>). It is the same project the clips were recorded
in, with the same theme; nothing from your own config is loaded. Run <code>make demo</code> again to reset it.</p>
</div>
<p class="commenting" hidden><b>Comments.</b> Every card has a <b>Comment</b> button. Type what you think (about a default,
a bug, the clip itself) and press <b>Add</b> or <kbd>Ctrl+Enter</kbd>: the comment waits in the <b>tray</b> at the bottom
right, kept in this browser, where you can edit or remove it. When you are done, <b>Send all to Claude</b> sends every
comment in the tray as one message to the working session. (The page's own comment mode, outside these buttons, still
sends each comment straight away.)</p>
<p class="lede">{n} demonstrations, in the order of the README:</p>
<ul class="toc">
{toc}
</ul>
{body}
<h2 id="skipped">Not shown</h2>
<ul>{skipped}</ul>
<p class="lede">Re-record: <code>python3 docs/demos/scripts/record.py [clip ...]</code> (needs agentwin, ghostty,
ffmpeg), then <code>python3 docs/demos/scripts/page.py</code>.</p>
</main>
<script>
{tray_js}</script>
</body>
</html>
'''

if __name__ == '__main__':
    main()
