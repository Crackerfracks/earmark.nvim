# History

How the 2026-10 rebuild went and what was decided along the way. The plan is in
`PLAN.md`.

## Status on 2026-10-18

The 2026-10 rebuild plan is done: milestones M0 to M10 landed as PRs #1 to #11, and #12
fixed what an audit against the old Numhi conversations found. Since then: bug fixes found
while recording the demos (#13), the demos page (#14, #16 to #18), colour names, the palette
and the count hint (#15), the same-span question (#19), colours that adapt to light themes
(#20), new overlap looks (#21), a clearer naming prompt and exports beside the file (#22).
The plan is in `docs/PLAN.md`.

Decided with Stephen on 2026-10-18 (from his comments on the demos page):

1. Naming: the prompt asks for a name the first time a label is used in a project
   (`prompt.ask_name = 'first_use'`), and that name then applies in the project's other
   files (`.earmark/names.json` is committed). The naming step now says plainly what is
   being named.
2. Identifier tags are written `@A` in notes and shown as `[A]` at the end of the line;
   `<leader>mv` shows or hides tags and identifiers (hidden at startup); pencils always show.
3. Overlaps: mixed colours with the outer colour as underline; a second label is an
   undercurl and more labels split the undercurl into equal runs (nothing shifts the line);
   nested levels of one label are deeper shades; stale marks are faded.
4. The hover header is the label colour as text (`▍ name`), not a filled bar.
5. Colours adapt to the colour scheme's background (`color_adapt`).
6. `gh` without a count always opens the prompt; `<CR>` on empty input reuses the last label.
7. Text snapshots are gitignored, so a fresh clone re-anchors by quote and context only.
8. Exports go to `<root>/.earmark/export/<project>-<path>.md` by default; `export.location`
   can put them next to the annotated files too.
9. Another label on exactly the same span asks first: a adds it (an overlap), r replaces,
   Esc cancels (`prompt.confirm_stack`); `<leader>ml` replaces directly.
10. Notes open in a float by default; `picker = 'auto'`; `<leader>ml` with a count picks
    among overlapping annotations; `<leader>mg` accepts the new text as the annotation's text.

Still open:

- What the statusline shows: the next label, counts, the warning count and the digit row.
- Storage is JSON only; SQLite and encryption are dropped.
- An annotation re-placed by a close fuzzy match (one typo) stays "ok" rather than "stale".
- `<leader>mo` has no one-step undo (erase the extra annotations with `<leader>mx`).
- Set files are reloaded when Neovim regains focus or you switch buffers (no file watcher).
- The hover clip on the demos page needs re-recording (it rests on the wrong word).
