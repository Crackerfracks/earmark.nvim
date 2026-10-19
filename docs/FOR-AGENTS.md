# Asking for feedback through earmark (for agents)

Stephen reviews plans, drafts, option lists and demo files in Neovim with earmark. When you
hand him a file to review, you can give it a label set made for that review, so the labels
he needs are already there when he opens it.

## Default: nothing to do

The built-in `feedback` set (keys 1 to 9: Keep, Change, Wrong, Question, Unclear, Cut,
Idea, Prefer, Later) covers general review. If your file needs nothing more, don't add a
set.

## A set for one review

Add a set when the review has its own choices, for example "Option A / B / C", or
questions you want answered per section. Write `<stem>.earmark-set.json` next to the file
(`plan.earmark-set.json` for `plan.md`):

```json
{
  "extends": "feedback",
  "desc": "Pick a layout for the DM dashboard",
  "labels": [
    { "key": "a", "name": "Option A: one big picker", "tags": ["option-a"] },
    { "key": "b", "name": "Option B: two small pickers", "tags": ["option-b"] }
  ],
  "tags": ["pick"],
  "expires": "2026-11-15"
}
```

Rules:

- Always `"extends": "feedback"`, so the general labels stay on keys 1 to 9. Put your own
  labels on letter keys (`a`, `b`, ...). A label with the key of a feedback label replaces
  it; only do that on purpose.
- Name labels so they make sense in an export without the file open: "Option A: one big
  picker", not "A".
- Give each option label a tag (`option-a`). The export and the pickers can then filter by
  it.
- Set `"expires"` two to four weeks out. After that day the set is not offered anymore, so
  sets for finished reviews don't pile up. Existing annotations keep their colours.
- The set applies to `<stem>.*` in its folder. For other files use `"files": ["*.md"]`
  (globs relative to the set file's folder). Don't make one set apply to a whole project
  unless Stephen asks.
- Don't name it after a general set (`feedback`, `vivid`): it would be renamed.
- JSON only. Lua set files need Stephen to `:trust` them.

## Reading the feedback back

Stephen exports with `<leader>me` (a Markdown list grouped by label, with notes and tags;
written to `<root>/.earmark/export/`, or next to the file with
`export.location = 'beside'`). Annotations are also stored as JSON under
`<root>/.earmark/docs/`; `require('earmark').list(buf)` reads them from Lua.
