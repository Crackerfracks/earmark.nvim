Provenance: planned by Fable (claude-fable-5-1), 2026-10-18

# earmark.nvim — overnight implementation plan (rev 4)

Successor to the rev-3 "2026-10 Rebuild Plan". Phases 0–2 of rev 3 are done (commit `d319fbb`, 33 tests). This plan replaces rev 3's phases 3–7 and adds everything the digest found missing. The implementer follows it literally; where Stephen's wishes were unknown a default was chosen and marked **[decided for Stephen, revisit]**.

Stephen's goal, verbatim: "continue work on the plugin and don't stop until it eclipses the prior version's vision and features, has none of the bugs and issues, and feels polished/intuitive enough for daily use."

## 0. Working rules for the implementer

- Repo: `/home/claude/earmark.nvim` (remote `origin` = `github.com/Crackerfracks/earmark.nvim`, default branch `main`). One branch per milestone, named `m<N>-<slug>` (e.g. `m1-prompt`), one **draft PR** per milestone via `gh pr create --draft`, merged into `main` in order with `gh pr merge --merge` (merge commit, keep history) before starting the next one. If `gh` auth fails, merge locally with `git merge --no-ff` and keep going; never block on GitHub.
- Every milestone ends green on `make test` (mini.test, headless, `nvim` on `PATH` via `/home/claude/bin`, container Neovim 0.11.4; laptop runs 0.12.5; minimum stays **0.11**). Never remove or weaken an existing test. New behaviour gets a test in the same PR.
- Stylua: add `.stylua.toml` (2 spaces, 110 cols, single quotes, no call parens on single-table args) in M0. `make lint` runs `stylua --check` if `stylua` is on PATH, else prints "stylua not installed" and exits 0.
- Commit discipline: small commits with imperative messages; the PR body says what changed and which digest items it closes (use the matrix row ids below, e.g. `F12`).
- Keep `README.md` current **in every milestone** (keys table, config, commands). `doc/earmark.txt` is written once in M10 from the README.
- Neovim API hygiene: no `nvim_buf_add_highlight`, `nvim_buf_set_option`, `nvim_buf_get_option`, `vim.tbl_islist`, `vim.tbl_flatten`, `vim.highlight.*`. Use `vim.hl`, `vim.bo[buf]`, `vim.wo[win]`. Diff via a shim: `local diff = (vim.text and vim.text.diff) or vim.diff` (0.12 deprecates `vim.diff`; a deprecation popup on his laptop counts as a bug).
- Never change global options (`updatetime`, `timeoutlen`, `signcolumn`). Never write into the user's files. Never use the sign column.
- Priority tiers: **M0–M5 must land.** M6–M9 land in order as time allows. **M10 must land even if M6–M9 are cut** (do it after the last milestone you finish). If a milestone cannot be finished, leave its branch and PR as draft with a `BLOCKED.md` note at the branch root and move on to M10.
- Final hand-off: append a "What shipped / what did not / what Stephen should look at first" section to `README.md`'s bottom under `## Status (2026-10-19)` and list open questions from section F.

## A. Product definition

**earmark is an annotation layer for Neovim buffers**: mark a span, give it a label (colour + name), a note and tags, and earmark keeps it attached to that text while the text changes, shows it legibly even when annotations overlap, and lets you navigate, pick, review and export them. It serves four workflows with one data model: plain coloured highlighting with numbered palettes (v1 NumHi), annotating his own changing drafts/prompts/feedback, rubric/survey labelling with sets that change weekly (Q3 / Q3.1 letter options, conditional text), and the future DM notebook (zk).

"Eclipses v1's vision" means: every row below marked **keep** or **redesign** exists, works from a key, is tested, and none of the section-E bugs reproduce.

### A.1 Feature matrix

Ids `F#` are referenced by milestones (`M#`). Status: **keep** (build as asked), **redesign** (build, differently; why), **drop** (not tonight; why). Source tags as in the digest (`[Want]`, `[Jun5]`, …).

| id | Feature (source) | Decision | Milestone |
|---|---|---|---|
| F1 | Operator `gh{motion}`, Visual `gh`, `ghh` line, count picks label, dot-repeat (HAS) | keep | done |
| F2 | No count → visible, editable label prompt with live colour preview `[Jun5]` | keep (replaces "reuse last label"; the prompt pre-selects the last label so `gh{motion}<CR>` is the old behaviour) | M1 |
| F3 | `<BS>` edits, `<Esc>` cancels, `<CR>` applies, digits select, prompt is a real buffer you can type/paste into (mini.surround feel) `[Jun5]` | keep | M1 |
| F4 | Name a colour at point of use; per-file scope; directory defaults pre-filled; up/down history like a shell; clear-name action `[Bomb#12-13]`, `[Jun5]` | keep (doc-level `names`, project + global MRU history, name stage in the prompt, `<leader>mr`) | M1 |
| F5 | Favourite default colour `[Want]` | keep as `default_label` config | M8 |
| F6 | Five palettes × 99 distinct shades, OKLCH (HAS) | keep | done |
| F7 | Visible overlaps, incl. same-colour nested spans (his only hands-on feedback) | redesign: decoration provider draws overlap segments as an OKLab blend of the members plus an underline in the outer span's colour; same-colour overlaps get the underline alone. Priority stacking alone was invisible | M2 |
| F8 | Several colour codes on one highlight, readable at a glance `[Curr]` | redesign: value 1 = background, value 2 = undercurl in its colour, values 3+ = inline `■` swatches after the span. Gradient/interleave per character was judged gimmicky and expensive **[decided for Stephen, revisit]** | M2 |
| F9 | Highlight shows a note is attached without hover `[Bomb]` | keep: eol `✎` per note, coloured | M4 |
| F10 | Tag/indicator text coloured as **foreground**, never a second background `[Jun5]` | keep | M4 |
| F11 | One markdown note per highlight, float **below the lowest edge of the span**, never covering it, Insert mode when new, title/icon, split fallback `[Want]`, `[Curr]` | keep | M3 |
| F12 | Notes never lost: autosave on close/leave, `q` saves, `:w` works, erase goes to trash with note, restore brings note back `[Curr]` | keep | M3 |
| F13 | Hover window: fast, persists while on span, coloured, name + code + tags + pencil, expand to full note, 50% caps, inside the pane, placed opposite to cursor motion and below the whole span, auto-show only when named or noted `[Jun5]` | keep | M3 |
| F14 | Note window modes: follow-cursor, hide/shrink key, float↔split toggle, transparency `[Jun5]` | redesign: float↔split toggle (`,s`/`,f` inside the note) and `winblend` option ship; follow-cursor and shrink are dropped tonight (the hover already follows the cursor) | M3 |
| F15 | flash.nvim: hide note on remote operator, flash can enter the note, flash labels on highlights `[Arb l.753]`, `[Bomb#60]` | redesign: hide hover/editor on `ModeChanged *:no*` (covers `yr`/`dr`), flash jumps into floats natively, `<leader>mj` runs flash with a custom matcher over annotations. Direction-aware label avoidance dropped | M3, M5 |
| F16 | Virtual-line "drawer" under the line `[Jun2]` | drop tonight: hover + eol indicators cover it; drawer conflicts with wrapped lines | — |
| F17 | Per-line indicators: pencil per note (≤3) or `+N`, coloured, empty vs filled, overflow to a virtual line `[Jun2]`, `[tmp]` | keep (empty highlights show nothing by default; `indicators.show_empty`) | M4 |
| F18 | Gutter never used `[Jun5]` | keep | all |
| F19 | Free-form `#tags` parsed from notes, global reusable tag list, add tags without typing inline, tag display toggle (one key, no initial-state bug), search by tag `[Want]`, `[Jun2]`, `[Arb l.868]` | keep | M4, M5 |
| F20 | Identifier-type tags (Model A/B, Response 1/2) displayed differently, own toggle `[Curr]` | keep: tags starting with `@` are identifiers, rendered `[A]` bold **[decided for Stephen, revisit]** | M4 |
| F21 | Sidecar JSON in a hidden dir, atomic writes, no file mutation (HAS) | keep; schema v2 (snapshot moves to a sibling file) | M0 |
| F22 | Survive formatters, external edits, renames; stale/detached statuses (HAS) | keep + fuzzy fallback, `ambiguous`, scores | M6 |
| F23 | SQLite / password protection `[Jun5]` | drop: JSON travels with the repo and diffs; encryption is out of scope. Confirm with Stephen | — |
| F24 | Error logging / crash diagnostics `[Jun2]` | keep: `earmark.log` ring buffer + file, `:Earmark log`, every autocmd/provider callback pcall'd | M0 |
| F25 | next/prev any, same label, wraparound messages, count `[Want]` | keep | M5 |
| F26 | Pickers: buffer and project lists, searchable by text/label/tag/status, sortable; linked multi-mode picker `[Curr]` | redesign: one adapter (snacks → telescope → `vim.ui.select`), query grammar `#tag label:x status:detached has:note`. The linked multi-mode cursor carry-over is dropped (picker-specific, fragile) | M5 |
| F27 | Picker/float positioned under the highlight `[Bomb#14]` | keep for earmark's own floats (prompt, note, hover); pickers use their own layout | M1, M3 |
| F28 | Notifications/floats, never the echo line; no popup spam `[Bomb#38]` | keep: `vim.notify` only for results and errors, never per keystroke | all |
| F29 | All actions under one prefix, every action has a key and `<Plug>`, no trap namespaces `[Curr]` | keep: `<leader>m` + `gh`; test enumerates every `<Plug>` and subcommand | M0 |
| F30 | Palette cycling with a transient swatch popup `[Want]` | keep | M7 |
| F31 | Statusline component with swatch, set and coloured digits; mini.statusline/lualine/vanilla `[Want]` | keep (function returning a `%#…#` string; never monkey-patches) | M7 |
| F32 | Colour-code picker with live shade preview `[Want]` | keep (prompt candidates show every shade of the typed digit's family) | M1 |
| F33 | Note templates per code with cycleable/editable fields, auto-updating counts `[Want]` | redesign: rev-3 `choices` / `text` / `requires` forms as prompt stages; auto-updating counts dropped | M7 |
| F34 | Label sets from spec, `~/.config/earmark/sets`, `.earmark/sets`, hot reload (rev 3) | keep | M7 |
| F35 | Export Markdown (primary), HTML, filename prompt, templates, sort, manual reorder, open in split `[Bomb#46-52]` | redesign: Markdown with `group_by = label|position|tag|time`, filename prompt (default `<root>-<dir>-<file>.md`), opens in a split, `format` hook. HTML and manual reorder dropped (he said tool-specific export is out of scope) | M8 |
| F36 | Highlight all occurrences (explicit, never default) `[Want]` | keep: `<leader>mo` | M8 |
| F37 | Grow/shrink a highlight `[Want]` | keep: `<leader>mg` re-span operator | M8 |
| F38 | ccc.nvim / arbitrary colour per label `[Curr]` | redesign: doc-level colour override `:Earmark color #hex` (so ccc or anything can feed it); ccc UI wiring deferred | M8 |
| F39 | zk: promote a note to a zk note; sets in the notebook `[Plan]` | keep `<leader>mz` (guarded on `zk` being loadable); `frontmatter_sync` deferred (writes into his files) | M9 |
| F40 | Public Lua API + `User Earmark*` events for the DM dashboard `[Plan]` | keep | M0, M9 |
| F41 | Stale/detached list with "what I annotated → what it says now" diff (rev 3) | keep | M5 |
| F42 | Margin view (glossator idea, rev 3) | drop tonight: pickers + hover cover review; revisit for the DM dashboard | — |
| F43 | Scratch/plugin buffers stored by id, reopenable (rev 3) | keep (stored already); `:Earmark scratch` reopen | M5 |
| F44 | Undotree-style history browsing `[Curr]` | drop: Neovim undo + trash/restore cover it | — |
| F45 | `:checkhealth earmark`, vimdoc, which-key group, quickstart | keep | M10 |

Research ideas adopted (from `research/*.md`): one decoration provider for derived visuals (ed#6, ed#9); never silently relocate/drop + explicit states (ed#3, web#4); uniqueness-aware context and fuzzy with a floor and ambiguity margin (web#3, web#8); fingerprint fast path (already); snapshots out of the committed JSON (ed#13); keyboard prompt with live preview that reverts on cancel (ed#10); navigation by identity with wrap messages (ed#11); quickfix items with `user_data` (ed#6.bqf); `.tag`-style quick tagging → we use `#tag`/`@ident` in the note (web#13); sticky colour = `default_label` and the pre-selected last label (web#13); flash custom matcher; "detached" section in export (web#15); per-label-set overlap policy is **not** adopted (allow overlaps everywhere; simpler).

## B. Key decisions

1. **Prompt = editable scratch buffer in a float, not a `getchar` loop.** Stephen asked for mini.surround/snacks.input feel: type, paste, flash into it; `<Esc>` in Insert goes to Normal (vim editing), `<Esc>`/`q` in Normal cancels. Buffer-local maps only, so nothing leaks (fixes the v1 `<BS>` = cancel bug).
2. **Count path stays instant.** `{count}gh{motion}` never prompts. Only the no-count path prompts (and can name). Dot-repeat repeats the last accepted value silently.
3. **Names are per document, with history.** `record.names["set/key"]`, plus MRU histories in `<root>/.earmark/names.json` and `storage_dir/names.json`. Prefill order: doc → project MRU → global MRU → set label name. Saving a name writes all three; empty input clears the doc name. `prompt.ask_name = 'first_use'` (name stage opens automatically the first time a *numbered* label is used in a doc via the prompt) **[decided for Stephen, revisit]**.
4. **Tags have two sources, one display.** Explicit tags (`record.tags`, from the tag picker) ∪ tags parsed from the note (`#word`, `@ident`) at load/save; never copied between sources (v1 lost notes by "syncing"). `@` prefix = identifier tag **[decided for Stephen, revisit]**.
5. **Overlaps via one decoration provider.** Persistent extmarks stay the anchors (bg = value 1, priority by span size as now). In `on_win`, for visible rows, sweep-line segments with ≥2 annotations get an ephemeral mark: bg = OKLab mean of member colours, `underline` with `sp` = outer member's colour (same colour → underline in the contrast fg). Value 2 = `undercurl` (its colour); values 3+ = inline `■` swatches. Cached composite groups, cap 2000.
6. **Hover and note floats share one placement engine** (`ui/place.lua`): below the span's last screen line, else above its first; prefer the side opposite the last vertical cursor motion; clamped inside the current window; caps 50%×50% (hover) / configurable (note). Hover is non-focusable, 120 ms debounce on `CursorMoved`, persists while the hit set is unchanged, auto-shows only if a hit has a name, note or tag.
7. **Note editor** = unlisted `acwrite` scratch buffer named `earmark://note/<id>` (reused if it exists; refreshed from the store before showing), `BufWriteCmd` saves, `q` saves and closes, close always saves if modified, `,s`/`,f` toggle split/float. Content is written through `buffer.set_note` — the single write path.
8. **Keys.** `gh` operator (approved), `ghh` line (same ambiguity as built-in `gcc`, accepted), everything else under `<leader>m` (free in his config; which-key `delay=0` shows the group). Full map in D.1. Count before an action picks the n-th overlapping annotation (innermost first).
9. **Storage schema v2.** Snapshot leaves the committed JSON into `<store>/snap/<key>.snap` (gitignored by an auto-written `.earmark/.gitignore`); new fields `names`, `colors`, per-annotation `note`, `tags`, `score`, `how`. Lazy migration from v1 records on read (his two records in `~/.local/share/nvim/earmark/files/` are v1). Missing snapshot → anchor by quote/context only.
10. **Anchor statuses: `ok | stale | ambiguous | detached`** plus `score` (0–1) and `how` (`same|mapped|edited|relocated|fuzzy`). `ambiguous` when the top two relocation candidates score within 0.1; fuzzy search is bounded (±200 lines first, error budget `min(len/4, 64)`, floor 0.75).
11. **Performance:** provider does work only for visible rows and returns `false` for buffers without state; marks fetched with `nvim_buf_get_extmarks(..., {overlap=true})`; highlight groups created lazily per label and re-applied on `ColorScheme`; saves debounced 500 ms; hover 120 ms; no `CursorHold` dependence; every callback pcall'd and logged, a failing provider disables itself for that buffer after the first error.
12. **Integrations tonight:** picker adapter (snacks.picker → telescope → `vim.ui.select`, each behind `pcall`, fallback on error), which-key group (pcall), flash jump matcher + op-pending hide, mini.statusline/lualine examples, zk promote (M9). **Later:** ccc UI, `frontmatter_sync`, noice-specific views, margin view, DM dashboard hooks beyond the API.
13. **Messages**: `earmark: …`, lowercase, one `vim.notify` per completed action or error, none per keystroke; wraparound says `earmark: wrapped to top/bottom`.
14. **Colours in light themes:** single palette set, auto-contrast fg; no per-background palettes tonight **[decided for Stephen, revisit]**. `ui.keep_syntax_fg = false` (default forces fg for readability, like v1).

## C. Milestones

Common test harness: `tests/test_*.lua` with `MiniTest.new_child_neovim()`; call `child.set_size(30, 100)` in `pre_case` for float tests; keep `scripts/minimal_init.lua`; a new `tests/helpers.lua` (`open`, `texts`, `settle`, `floats()` = list of floating windows with config and buffer lines, `hl_at(row, col)` via `vim.inspect_pos`/`nvim_buf_get_extmarks` on the earmark namespaces).

### M0 — Foundations: schema v2, logging, key coverage (`m0-foundations`)

Scope: everything risky and structural, no UI.
- `store.lua`: `VERSION = 2`; `doc.snap` path; `read()` returns `rec, err, migrated`; `migrate_v1(rec, doc)` moves `snapshot` → snap file, adds `names = {}`; `write_snapshot(doc, lines)`, `read_snapshot(doc)`; `.earmark/.gitignore` written once with `snap/` and `*.tmp*`; `names.json` / `tags.json` helpers (`store.mru_get(path, key)`, `store.mru_push(path, key, value, cap=50)`), atomic.
- `buffer.lua`: `S.by_ext` reverse map; `serialize` adds `note`, `tags`, `score`, `how` (omit empty/1.0); load tolerates missing fields; `M.find` fixes the end-of-line miss (cursor col == #line hits a span ending there); `M.set_note(buf, id, text)`, `M.set_tags(buf, id, tags)`, `M.set_values(buf, id, values)`, `M.rename_label(buf, value, name)` all go through `schedule_save` and emit events; `M.names(buf)` resolves display names.
- `events`: `User EarmarkChanged` stays; add specific patterns `EarmarkAdd|Update|Erase|Restore|Repair|Note|Load` with the same `data`.
- `log.lua`: ring buffer (200), `log.warn/error/debug`, mirror WARN+ to `storage_dir/earmark.log`; `:Earmark log` opens it in a split; `vim.g.earmark_debug` enables debug.
- `compat.lua`: `diff` shim (`vim.text.diff or vim.diff`), `getcharstr`, version check (`vim.fn.has('nvim-0.11') == 1` else `error` once in `setup`).
- `sets.lua`: lazy highlight groups (`sets.group(value)` creates on demand; `apply_highlights` re-applies only created ones); `sets.display_name(value, buf)`.
- `init.lua`: `:Earmark` gains `clear`, `restore`, `reload`, `set`, `log` with keys/`<Plug>` for `clear` (`<leader>mX`); table-driven action registry `actions.lua` = `{ name, plug, default_key, modes, fn, desc }` used for keymaps, `:Earmark` subcommands and completion, so a key can never point at a missing function.
- `.stylua.toml`, `make lint`, `Makefile` unchanged otherwise.
Tests (`test_store.lua`, extend `test_buffer.lua`, `test_keys.lua`): v1 fixture (`tests/fixtures/v1_record.json`, sanitised copy of his record) loads, annotations re-anchor, snap file written, JSON rewritten as v2 without `snapshot`; missing snap file still anchors by quote; `names.json` MRU push/get/cap; every action in the registry has a `<Plug>` that resolves to a function and every `:Earmark` subcommand runs without error on an empty buffer; `find` at EOL; `set_note` persists through write/reopen; `:saveas` keeps one record; `cp` + open creates an independent record.
Acceptance: his two v1 records open with their 5 annotations and trash intact and are rewritten as v2; `:Earmark log` shows a warning after a forced parse error; no deprecation message on 0.12 (grep the code for the banned APIs in a test).

### M1 — Label prompt and naming (`m1-prompt`)

Scope: F2, F3, F4, F27, F32.
- `ui/prompt.lua`: `prompt.open({ mode = 'add'|'relabel'|'add_value', target = {buf, s, e} | {buf, id}, on_accept, on_cancel })`. Float per D.2; scratch buffer, Insert mode, buffer-local maps per D.2; candidates computed from the current set: digits match keys (exact first, then same family `3,13,23…` so the shade preview shows), letters fuzzy-match names (`vim.fn.matchfuzzy` on `key .. ' ' .. name`); live preview = temporary extmark in namespace `earmark_preview` over the target span in the selected candidate's group plus `line_hl_group` on the input line; preview removed on accept/cancel/`BufWipeout`.
- Name stage (`<Tab>`): input prefilled per B.3, `<Up>/<Down>`/`<C-p>/<C-n>` cycle history, `<CR>` applies and saves the name; `ask_name='first_use'` auto-enters the stage once per doc per label when the set is numbered and no name exists anywhere.
- `init.lua`: no-count `gh{motion}` / Visual `gh` → operatorfunc stores the region and schedules the prompt (Visual is already left by `g@`); accept → `buffer.add`; `pending` set so `.` repeats silently. `<leader>ml` relabel (replaces `values[1]`), `<leader>ma` add value, `<leader>mr` rename (name stage only; empty clears). `<C-s>` inside the prompt cycles the set and re-renders candidates.
- `sets.resolve_query(set, text)` pure function for candidates (testable without UI).
Tests (`test_prompt.lua`): `ghiw` opens one float whose buffer is unlisted; typing `3<CR>` annotates with label 3 and closes; `<BS>` removes a digit and does not close; `<Esc><Esc>` cancels, no annotation, preview extmark gone; `.` after a prompted add repeats label 3 without a float; typing `fac` in a named set filters to "Factually…" and `<CR>` picks it; `<Tab>`, type `Factually Inaccurate`, `<CR>` → `record.names['vivid/3']` set, `names.json` MRU contains it, hover name resolves (via `buffer.names`); reopening the prompt for label 3 in another doc in the same root prefills `Factually Inaccurate`; `<leader>mr` with empty input clears; `3ghiw` never opens a float; prompt float sits below the span's last line and inside the window (`nvim_win_get_config`).
Acceptance: he can `gh` a selection, see the colour change live as he types `2`, `23`, `<BS>`, name it, `<CR>`; nothing is echo-line based; `.` works.

### M2 — Rendering: overlaps and multi-value (`m2-render`)

Scope: F7, F8, F18.
- `render.lua`: single `nvim_set_decoration_provider(ns_render, { on_win })`; `on_win(_, win, buf, top, bot)` returns `false` when `buffer.state[buf]` is nil or `S.render_disabled`; else fetches marks overlapping `[top, bot]`, builds segments, sets ephemeral marks: overlap composites (B.5), value-2 undercurl, values-3+ inline swatches at span end (`virt_text_pos='inline'`, `■` per value, fg = value colour). Composite group cache keyed by sorted hex list, name `EarmarkMix<n>`, cleared on `ColorScheme`. Whole callback in `pcall`; on error: `log.error`, `S.render_disabled = true`, one `vim.notify` WARN.
- `color.lua`: `color.mix(hexes)` (OKLab mean), `color.underline_for(hexes)`.
- `buffer.add` on the exact same span with the same value → no-op (returns existing); same span, different value → relabel (as now); `overlap.style = 'top'` config disables composites (priority stacking only).
Tests (`test_render.lua`): nested same-colour spans (`this` label 2 and `is` label 2, his exact probe) produce an ephemeral underline mark over `is` after a redraw (`child.cmd('redraw')`, then inspect `nvim_buf_get_extmarks` on `ns_render` is impossible for ephemeral marks — instead expose `render.segments(buf, top, bot)` pure function and test it, plus a screenshot test with `child.get_screenshot()` asserting the attr ids differ between an overlapped and non-overlapped cell); partial overlap of different colours gets a blend group whose bg differs from both; multi-value annotation gets undercurl and one swatch per value ≥ 3; provider disabled buffers cost nothing (`on_win` returns false); `ColorScheme` keeps everything visible.
Acceptance: his `numhi_feedback_and_scratch.md` probe shows every overlap distinctly.

### M3 — Notes, hover, placement (`m3-notes`)

Scope: F11, F12, F13, F14 (partial), F15 (hide), F27.
- `ui/place.lua`: `place.for_span(win, s, e, want_w, want_h, opts)` → `{ relative='win', win, row, col, width, height, side }` per D.3; tracks the last vertical cursor direction per window via `CursorMoved` (compare rows).
- `ui/note.lua`: `note.open(buf, id)`, `note.close(save=true)`, `note.toggle_layout()`; buffer `earmark://note/<id>`, `buftype=acwrite`, `bufhidden=hide` while the window exists then wiped on close, `swapfile=false`, `filetype=markdown`, unlisted; `BufWriteCmd` → `buffer.set_note`, `modified=false`; `BufLeave`/`WinClosed`/`QuitPre` → save if modified; Insert mode when the note is empty; keys per D.4; split mode uses `botright 10split` keeping the same buffer.
- `ui/hover.lua`: timer restarted on `CursorMoved` (Normal mode only; never in Insert), `hover.show(hits)` content per D.5, `hover.focus()` for `<leader>mi` (enters the float; `q`/`<Esc>` closes), hidden while a prompt/note editor/picker is open, on `InsertEnter`, `BufLeave`, `WinScrolled`, `ModeChanged *:[nov]*` (op-pending/visual), and restored on `ModeChanged no*:n`; `hover.auto` toggle `<leader>mh`.
- Tags parsing `tags.lua`: `tags.parse(note) → { tags = {...}, idents = {...} }` (pattern `#([%a][%w_/%-%.]*)` not at line start followed by space, `@([%w][%w_%-]*)`), ignores fenced code blocks.
Tests (`test_note.lua`, `test_hover.lua`, `test_place.lua`): `<leader>mm` on a span opens a float whose top row is span_end_row+1 (window coords) and whose col ≤ span start col clamped; typing text, `q` → store has the note, buffer wiped, no E382 on `:w`, `<leader>mm` again reopens the same content (no E95, one buffer named `earmark://note/<id>`); an unmodified reopen never overwrites a changed store value (set via API while the editor is hidden → reopen shows the new text); erase then restore keeps the note; note with `#todo @A` → `tags.parse`; hover appears after 120 ms on a named annotation and not on an unnamed, note-less one; hover persists across `l` moves within the span and closes on leaving; hover stays inside the window (`row+height ≤ win height`, `col+width ≤ win width`) with a span near the bottom (placed above); cursor moving down makes the hover prefer above when room; `ModeChanged` to op-pending closes the hover; `,s` in the note moves it to a split and `,f` back without losing text.
Acceptance: his daily loop works: select → `gh` → `3<CR>` → `<leader>mm` → type → `q`; hovering shows name, tags, pencil and the note; nothing in the gutter.

### M4 — Tags and indicators (`m4-tags-indicators`)

Scope: F9, F10, F17, F19 (display + add), F20.
- `ui/tags_picker.lua`: `<leader>mt` → multi-select of global tags (`tags.json` MRU with counts) + "new tag" entry; with snacks/telescope use their multi-select, with `vim.ui.select` loop until "done"; writes explicit tags via `buffer.set_tags`; removing a note-derived tag notifies `earmark: "#x" comes from the note text; edit the note to remove it`.
- `render.lua` eol indicators (same provider): per visible row, for annotations **ending** on that row: `✎` per note (max `indicators.max_pencils = 3`, then `+N`), `#tag` list (dedup per row), `[A]` identifiers (bold); all `fg = annotation colour`, no bg; `virt_text_pos='eol'`; if `strdisplaywidth(line) + width > win width - textoff` → `virt_lines` below, indented to span start col. Modes `indicators.mode = 'eol' | 'none'`; `<leader>mv` toggles between them with one notify; `indicators.identifiers = true|false` is config only (no key) **[decided for Stephen, revisit]**.
- `tags.json` updated on every note save and tag edit; `buffer.all_tags(buf)`.
Tests: note `#a #b` renders eol virt text `✎ #a #b` in the label's fg group (inspect `render.eol_items(buf, row)` pure function + screenshot attr check); two notes on one line → two pencils; four → `✎✎✎ +1`; long line → `virt_lines` item instead of eol; toggle changes only `config.options.indicators.mode`, the record file is byte-identical before/after (the v1 "toggle re-read disk" bug); `@A` renders `[A]`; tag picker (stubbed `vim.ui.select`) adds an explicit tag and `tags.json` records it.

### M5 — Navigation, pickers, review (`m5-navigate-pick`)

Scope: F15 (jump), F19 (search), F25, F26, F41, F43.
- `nav.lua`: `next/prev` wrap with `earmark: wrapped to top|bottom`, `{count}` repeats, `<leader>m]`/`<leader>m[` same label as under cursor (value 1), `<leader>mj` flash jump (`require('flash').jump({ matcher = …annotations in win…, label = { after = false, before = true } })` guarded by `pcall(require, 'flash')`, fallback to the picker).
- `ui/picker.lua` adapter: `picker.pick(items, opts)` with `items = { text, file, pos, end_pos, annotation, preview }`; backends `snacks` (`Snacks.picker.pick` with `items`, `format`, `preview = 'file'`, `confirm`), `telescope` (`pickers.new` + `finders.new_table` + `entry_maker` with `lnum/col/filename`, grep previewer, `attach_mappings` for `<CR>` jump, `<C-q>` quickfix), `select` (`vim.ui.select` with formatted lines). `picker = 'auto'` detects in that order; any backend error → log + fallback.
- `<leader>mp` doc annotations, `<leader>mP` project (reads every record under the root's `.earmark/docs` via an index `store.index(root)` cached per write); query grammar applied before the backend gets items: `#tag`, `label:3`, `set:vivid`, `status:stale|detached|ambiguous`, `has:note`, free text matches quote/note/name.
- `<leader>md` detached/stale/ambiguous list: items show status, name, original quote, best candidate; actions `<CR>` jump (if placed), `r` re-anchor to candidate N (menu of up to 3 candidates from `anchor.candidates`), `v` re-anchor to the current Visual selection (`:Earmark reanchor` in Visual), `x` erase (to trash).
- `<leader>mD` diff float: "originally / now" with char-level diff highlights (`DiffDelete`/`DiffAdd`).
- `:Earmark qf` → quickfix with `lnum/col/end_lnum/end_col/text/user_data.id` and a `quickfixtextfunc`.
- `:Earmark scratch` → `vim.ui.select` over `storage_dir/scratch/*.json`, reopen into a new buffer with the stored snapshot and annotations.
Tests (`test_nav.lua`, `test_picker.lua`): wrap message and position; same-label skip; `vim.ui.select` stub returns an item → cursor jumps; project picker lists annotations from two docs; grammar filters; detached list re-anchor to a candidate restores status `ok`; Visual re-anchor sets the span to the selection; qf items correct; scratch reopen restores text and annotations; flash absent → fallback path runs without error.

### M6 — Anchoring v2 (`m6-anchor`)

Scope: F22, research ed#2/3, web#3/#8.
- `anchor.fuzzy(t, item, near, opts)`: banded Sellers DP of `quote` against windows of `new.str` (first ±200 lines around `near`, then whole text if `#t.str ≤ 2 MB`), whitespace-collapsed matching with an offset map back to bytes, error budget `min(floor(#quote/4), 64)`, returns candidates `{s, e, sim}` with `sim ≥ 0.75`.
- `anchor.candidates(t, item, near, n)` → up to `n` scored candidates (exact occurrences with context score, then fuzzy), each `{ s, e, score, how }`, `score = 0.5*sim + 0.3*context + 0.2*proximity`.
- `reanchor` and `locate` use `candidates`; `ambiguous` when `#cands ≥ 2` and `cands[1].score - cands[2].score < 0.1`; results carry `score`, `how`; `buffer` stores them and sets `status`; `ambiguous` renders like `stale` (see D.6) and appears in `<leader>md`.
- Creation-time context: `anchor.context` grows prefix/suffix (up to 96 bytes) until the quote+context is unique in the buffer, then pads to a word boundary; `original_quote` unchanged.
- `:Earmark check` (headless-friendly): prints one line per annotation `status score how quote` and exits non-zero if any detached (for scripts).
Tests (extend `test_anchor.lua`): typo inside a 30-char quote after reopen → placed, `how='fuzzy'`, status `stale`, score < 1; two equal candidates with equal context → `ambiguous`; a quote duplicated with distinct context relocates to the right one with `score ≥ 0.9`; 20k-line buffer with 200 annotations reanchors after a full reindent in < 400 ms (`vim.uv.hrtime`, generous bound); missing snapshot path uses `candidates`.

### M7 — Sets from files, forms, set popup, statusline (`m7-sets`)

Scope: F30, F31, F33, F34.
- `sets.lua`: load order spec → `~/.config/earmark/sets/*.{lua,json}` → `<root>/.earmark/sets/*.{lua,json}` (nearest wins by name); `FileChangedShellPost`/`BufWritePost` on those paths → `sets.reload()` + `buffer.rerender` for all buffers; labels gain `choices = { a = 'Correct', … }` (ordered via list form too), `text = { when = {...}, prompt = '…' }`, `requires = { q1 = {'b','c'} }`; a value becomes `{ set, label, choice?, text? }`.
- Prompt stages: after label → choice stage (letters as candidates, colour of the choice if given) → text stage (free line) when `text.when` matches; `requires` filters candidates against the other values on the same annotation (`add_value` mode) and shows disabled ones dimmed with the reason.
- Display name of a value with a choice: `Accuracy · b Minor issue`; hover shows the text.
- `<leader>ms` cycles with a transient popup (D.7) for 1500 ms; `<leader>mS` picks a set (adapter).
- `statusline()` per D.8 and `statusline_digits()`; README shows mini.statusline and lualine snippets.
Tests (`test_sets.lua`): project `.earmark/sets/wf.lua` loads and overrides a same-named spec set; editing the file hot-reloads (`child.cmd('checktime')` after write) and the label name changes; prompt with `choices` asks for the letter and stores `choice`; `text.when` only prompts for `b`/`c`; `requires` hides `q1.1` until `q1 = b`; set popup opens and closes by timer; `statusline()` contains the set name and a `%#EarmarkStl` group.

### M8 — Export, occurrences, regrow, defaults, colour override (`m8-export-ops`)

Scope: F5, F35, F36, F37, F38.
- `export.lua`: `export.markdown(buf | root, { group_by, include_detached = true, template })` → lines; default template per D.9; `<leader>me` prompts for the filename via `vim.ui.input` (default `<root basename>-<rel dir with / → ->-<file>.md` in `<root>/.earmark/export/`, outside a root `storage_dir/export/`), writes, opens in a vertical split; `export.format` hook `function(annotations, ctx) → lines`.
- `<leader>mo` occurrences: annotate every other exact occurrence of the span's quote with the same values as one trash batch; notify count; `default_label` config used when nothing was used yet.
- `<leader>mg` regrow operator: `g@`; target = innermost annotation containing the cursor at invocation (else overlapping the motion); new span = motion/selection; `original_quote` kept, `quote` updated, status recomputed.
- `:Earmark color <#hex|reset>` sets `record.colors['set/key']` for the label under cursor; `sets.group` consults doc overrides (group per (doc, set, key) when overridden).
Tests: export groups by label with names, includes a "Detached" section, filename default computed, split opened; occurrences skips the original and is restorable in one `<leader>mu`; regrow changes the span to `quick brown fox` and keeps the note; colour override changes the hl group bg and persists.

### M9 — API, events, zk (`m9-api-zk`)

Scope: F39, F40.
- Public API (documented, stable): `annotate`, `list`, `at`, `get(id)`, `set_note`, `set_tags`, `set_values`, `erase(ids)`, `restore`, `rename_label`, `names(buf)`, `export`, `pick`, `hover.show/hide`, `on(pattern, fn)` (sugar over `User Earmark*`). Everything else is private.
- zk: `<leader>mz` when `pcall(require, 'zk')` succeeds: `require('zk.api').new(root, { title = name or first note line, content = <quote block + note + `[source](path#L{row})`>, dir = config.zk.dir }, cb)` then stores the created note's path in `annotation.zk` (the `note` text stays as it was) and the hover shows `↗ zk`; absent zk → notify once.
Tests: API round trip; `on('EarmarkNote')` fires on `set_note`; zk path with a stub `zk.api` module injected into `package.loaded`.

### M10 — Polish and docs (`m10-polish`)

- `doc/earmark.txt` (vimdoc: intro, quickstart, keys, commands, config, sets file format, storage schema v2, API, events, troubleshooting), `:helptags` generated in `make test` to catch tag errors.
- `lua/earmark/health.lua`: nvim version, storage dir writable, root for cwd, record parse errors (walk records), backend detection (snacks/telescope/flash/which-key/zk), banned-API scan omitted.
- which-key: `pcall(require('which-key').add, { { '<leader>m', group = 'earmark', icon = '󰃉' } })` in `vim.schedule` after setup.
- README rewrite: pitch, 60-second quickstart (five steps), key table, config with defaults, sets files, storage, API, FAQ (gh vs Select mode, `ghh` ambiguity, 0.12 note), recommended lazy spec for his config (`dir = '~/Projects/earmark.nvim'`, `lazy = false`).
- `tests/test_docs.lua`: every default key in `config.defaults.keys` and every `:Earmark` subcommand appears in `README.md` and `doc/earmark.txt`.
- `make demo`: headless script writing a sample doc + record into `/tmp/earmark-demo` and printing the command to open it.

## D. UX spec

Icons assume a Nerd Font (he has one) with plain fallbacks when `vim.g.have_nerd_font ~= true`: `✎`→`*`, `■`→`#`, `▍`→`|`, `↗`→`^`.

### D.1 Keymap (defaults; every entry has `<Plug>(earmark-<name>)` and a `:Earmark <name>` subcommand)

| key | name | modes | action |
|---|---|---|---|
| `gh{motion}` / `{Visual}gh` | operator | n, x | annotate; count = label; no count = prompt |
| `ghh` | line | n | annotate line (count as above) |
| `<leader>mm` | note | n | open/close note editor for annotation under cursor (count = n-th) |
| `<leader>mi` | peek | n | show hover now / focus it (scroll, `q` closes) |
| `<leader>mt` | tags | n | tag picker (multi-select, add new) |
| `<leader>mr` | rename | n | name the label under cursor for this doc (empty clears) |
| `<leader>ml` | relabel | n | prompt; replaces value 1 |
| `<leader>ma` | add_value | n | prompt; appends a value |
| `<leader>mx` | erase | n, x | erase under cursor / all overlapping selection (to trash) |
| `<leader>mX` | clear | n | erase all in doc (to trash) |
| `<leader>mu` | restore | n | restore last erased batch |
| `<leader>mn` / `<leader>mN` | next / prev | n | any annotation, wraps, count repeats |
| `<leader>m]` / `<leader>m[` | next_same / prev_same | n | same label as under cursor |
| `<leader>mj` | jump | n | flash labels on annotations (fallback: picker) |
| `<leader>mp` / `<leader>mP` | pick / pick_all | n | annotations in doc / project |
| `<leader>md` | review | n | stale/ambiguous/detached list with re-anchor actions |
| `<leader>mD` | diff | n | original vs current text of annotation under cursor |
| `<leader>ms` / `<leader>mS` | cycle_set / pick_set | n | next set with popup / pick a set |
| `<leader>mv` | toggle_indicators | n | eol ↔ none |
| `<leader>mh` | toggle_hover | n | auto-hover on/off |
| `<leader>mo` | occurrences | n | annotate all other occurrences of the span text |
| `<leader>mg{motion}` / `{Visual}<leader>mg` | regrow | n, x | re-span annotation under cursor |
| `<leader>me` | export | n | markdown export (filename prompt, opens split) |
| `<leader>mz` | zk | n | promote note to a zk note |
| — | log, check, qf, scratch, reload, color, reanchor | cmd only | `:Earmark …` |

Conflict check against his config: `<leader>m*` unused (interestingwords uses `<leader>k/K` and `<leader><leader>m/M`; mini.surround `<leader>s*`, `<leader>n`/`<leader>l` only as surround suffixes; marks.nvim uses bare `m`; flash `s/S/r/R`; portal `<leader>o/i`; oil `<leader>pv`; `<leader>y/Y/p/x/q`). `gh` unused. `,s`/`,f` inside the note buffer only (localleader `,`).

### D.2 Label prompt float

- `relative='win'`, placed via D.3 relative to the target span; `width = min(prompt.width (44), win width - 4)`; `height = 1 + min(#candidates, prompt.max_rows (8))` (+1 for a "no label …" hint row when empty); `border = ui.border ('rounded')`, border fg = selected candidate colour (`EarmarkPromptBorder` updated live), `title = ' earmark · <set> '` (`title_pos='left'`), `footer = ' ⏎ apply  ⇥ name  ^n/^p  ^s set  ␛ cancel '` (`footer_pos='right'`), `style='minimal'`, `zindex=60`, `noautocmd=false`.
- Line 1 = input: `› 3▁` (prompt glyph as inline virt text, not buffer text so `<BS>` cannot eat it); `line_hl_group` = selected candidate's highlight group (bg = colour, fg = contrast) so the input area takes the colour, as he asked.
- Candidate rows are **`virt_lines` attached to line 1** (the buffer is always exactly one line, so Normal-mode editing can never touch them): `■ 3   Factually Inaccurate        used 4×`; `■` fg = colour; selected row drawn in `CursorLine`; shade siblings of a typed digit listed in family order (`3, 13, 23, …`); name match shows the matched chars in `EarmarkPromptMatch` (link `Special`). The float height is `1 + #rows` so every row is visible.
- Name stage: title becomes ` earmark · <set> · 3 name `, input prefilled, footer ` ⏎ save name  ↑/↓ history  ⇤ back  ␛ cancel `; history source badge on the right of the input: `(this file)`, `(project)`, `(history)`.
- Keys, Insert mode: printable → edit; `<BS>`/`<C-w>`/`<C-u>` edit; `<CR>` accept; `<Tab>` to name stage, `<S-Tab>` back; `<C-n>/<C-p>/<Down>/<Up>` move selection (label) / history (name); `<C-s>` next set; `<Esc>` → Normal mode. Normal mode: `<Esc>`/`q` cancel, `<CR>` accept, `j/k` selection, `i/a/A/I/p/P/x/dd…` default Vim editing of the single input line, `<Tab>` name stage. Clicking elsewhere / `BufLeave` cancels.
- Accept with no matching candidate: hint row `no label "343" in vivid` in `Comment`; `<CR>` does nothing (no notify).

### D.3 Placement engine (`ui/place.lua`)

Inputs: `win`, span `s,e` (0-based), wanted `w,h`, `opts.prefer` (`'below'|'above'|nil`), `opts.min_h` (3). Steps: `sp_end = vim.fn.screenpos(win, e_row+1, 1)`, `sp_start = screenpos(win, s_row+1, s_col+1)`; `win_row, win_col = nvim_win_get_position(win)`; `H, W = nvim_win_get_height/width(win)`; `below_row = sp_end.row - win_row` (window-relative row just under the span's last screen line; if `sp_end.row == 0` the line is off-screen → use `H`), `room_below = H - below_row`, `room_above = sp_start.row - win_row - 1` (0 if off-screen). `prefer` default = `'below'` unless the window's last vertical cursor move was downward → `'above'`. Choose the preferred side if `room ≥ min(h, min_h)`, else the other side if it fits, else the side with more room; `height = min(h, room)`. `col = clamp(sp_start.col - win_col - 1, 0, W - w)`; `width = min(w, W)`. Return `{ relative='win', win=win, row=below_row or room_above-height, col, width, height, side }`. Never covers the span lines by construction; the hover also never covers the cursor line since the cursor is inside the span.

### D.4 Note editor

- Float: `width = clamp(longest note line + 4, 40, min(note.max_width 100, floor(W * note.width 0.6)))`, `height = clamp(#lines + 1, note.height.min 5, floor(H * note.height.max 0.5))`, placed via D.3; border rounded, fg = label colour; `title = ' ✎ <display name> '` left; `footer = ' "<quote, 1 line, ≤ 30 cols, …> " · ,s split ' ` right; `winblend = note.winblend (0)`; `wrap`, `linebreak`, `conceallevel=2`, `signcolumn=no`, `number=false`; `zindex=50`.
- Buffer: `earmark://note/<id>`, `buftype=acwrite`, `filetype=markdown`, unlisted, `swapfile=false`; Insert mode at end when empty.
- Keys (buffer-local): Normal `q` save+close; `<C-s>` (n,i) save; `<leader>mm` close; `,s` → bottom split (10 rows, same buffer), `,f` → back to float; `<Esc>` is plain Vim. Insert `<C-s>` saves. Closing by any route saves when `modified`; the buffer is never saved when unmodified (protects the store from stale buffers).
- Messages: none on save (title gets a transient `·` → `✓` for 800 ms via `nvim_win_set_config`), `earmark: note saved` only for `:w` from the split.

### D.5 Hover float

- Non-focusable (`focusable=false`), `style='minimal'`, border rounded fg = innermost hit's colour, no title; `zindex=45`; `width = clamp(longest content line + 2, 20, floor(W*hover.max_width 0.5))`, `height = min(#lines, floor(H*hover.max_height 0.5))`, `wrap`; placed via D.3 with the cursor-direction preference.
- Content per hit (innermost first; `①②③` prefix only when >1): header `▍ Factually Inaccurate  vivid·3  #tag #tag2 [A]  ✎` — `▍` and name in `EarmarkHoverName_<group>` (fg = colour, bold), set·key in `Comment`, tags fg = colour, `✎` only when the note has text; status badge `~ stale (72%)`, `? ambiguous`, in `DiagnosticWarn`/`DiagnosticInfo`; then the note body (markdown via `vim.treesitter.start` when the parser exists, else plain), blank line between hits.
- Show rule: `hover.show_when='named_or_note'`: a hit counts if its display name differs from the bare key, or has a note, or has tags. `'always'` shows for every hit.
- Timing: 120 ms after the last `CursorMoved`; stays while the set of hit ids is unchanged (re-places silently if the cursor row changed); closes on leaving, `InsertEnter`, `WinScrolled`, `BufLeave`, op-pending/visual mode, prompt/note/picker open. `<leader>mi` opens immediately and focuses (`focusable=true` for that instance; `q`/`<Esc>` closes).

### D.6 Highlight looks

- Span: bg = label colour, fg = `color.contrast_fg` (dark `#111111` / light `#ffffff`) unless `ui.keep_syntax_fg`; `priority` by size as now. Stale: same bg + `underdashed` in contrast fg; ambiguous: `underdotted`; detached: not rendered (listed). Overlap composite: bg = OKLab mean of members, `underline`, `sp` = outer member's colour (same colour → contrast fg). Value 2: `undercurl sp = colour2`. Values 3+: inline `■` per value right after the span, fg = colour, no bg.
- Palettes unchanged (vivid L 0.70, pastel 0.86, earth 0.64, metal 0.74, cyber 0.76). With `background=light` the same colours are used; fg contrast handles legibility.
- Indicators (eol): `✎` fg colour; `#tag` fg colour; `[A]` fg colour bold; separators one space; `+N` in `Comment`.
- Named groups for users to override (all `default=true` links): `EarmarkPromptBorder`, `EarmarkPromptMatch` (Special), `EarmarkHoverBorder`, `EarmarkStale`, `EarmarkAmbiguous`, `EarmarkIndicator`, `EarmarkStlName` (StatusLine bold), `EarmarkStlDigit<k>`.

### D.7 Set popup (`<leader>ms`)

Centered-top float (`relative='editor'`, row 1), 1 line: ` pastel  ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ` (first ten labels' swatches; named sets show `■ name` pairs up to the width), border rounded, closes after 1500 ms or any key (`nvim_create_autocmd('CursorMoved')` once).

### D.8 Statusline

`require('earmark').statusline()` returns `''` when the buffer has no state, else `%#EarmarkStlSwatch_<g>#▍%* vivid·3 %#EarmarkStlName#Factually Inaccurate%*` (last used label, or the set's first) followed by ` 12 ✎4` (annotation count, notes count) and ` ⚠2` (detached+ambiguous, hidden at zero). With `statusline.digits=true` (default) and a numbered set, append ` 1234567890` with each digit in `EarmarkStlDigit<k>` (fg = colour k, **no bg**, so no asymmetric patches). No surrounding brackets; `%*` resets to the host section's group. README shows `MiniStatusline` `content.active` composition and a lualine component `{ require('earmark').statusline }`. The swatch digit groups are defined once per set in `apply_highlights`.

### D.9 Export template (Markdown)

```
# <file name> — earmark export (<date>)

## <Label display name> (<set·key>)         ← group_by = label (default)
- **"<quote>"** (L<start>–L<end>) #tag @A
  <note, indented 2>
...
## Detached
- "<original quote>" — <name> — <note first line>
```
`group_by = position` lists in document order with a `**name**` prefix; `tag` groups by tag (untagged last); `time` by `created`. `format(annotations, ctx)` replaces the whole body when set.

### D.10 Messages (exact strings)

`earmark: nothing under the cursor` · `earmark: erased %d (restore with %s)` (key name from config) · `earmark: restored %d` + ` (%d detached: text not found)` · `earmark: wrapped to top` / `bottom` · `earmark: no annotations` · `earmark: label set → %s` · `earmark: indicators %s` (`on`/`off`) · `earmark: hover %s` · `earmark: exported %d to %s` · `earmark: annotated %d more occurrence(s)` · `earmark: %s has no zk; install zk-nvim` · errors: `earmark: could not save %s: %s` (ERROR) · `earmark: rendering disabled for this buffer after an error (:Earmark log)` (WARN).

## E. Bugs and pitfalls checklist (each must have a test by the milestone shown)

| # | Pitfall / v1 root cause | Guard | Test in |
|---|---|---|---|
| E1 | Stale `'<`/`'>` ("one selection behind", whole-buffer highlight) | operator reads `'[`/`']` only | done (keep) |
| E2 | Keys bound to undefined functions (`nl`, `ns`, `nm`) | action registry; test resolves every `<Plug>` and subcommand | M0 |
| E3 | Notes keyed by extmark id / bufnr / `0`; E95 on reopen; wiped on `:w` | notes keyed by annotation id; one buffer `earmark://note/<id>` reused; single write path `buffer.set_note` | M0, M3 |
| E4 | Stale/empty scratch buffer overwrote the note | save only when `modified`; refresh from store before showing a hidden buffer | M3 |
| E5 | `:w` → E382 | `acwrite` + `BufWriteCmd` + `modified=false` | M3 |
| E6 | Display toggle re-read disk, duplicated extmarks, wiped notes, needed two presses | toggles change one config field; provider is a pure view; record bytes unchanged | M4 |
| E7 | Pencil in sign column hid diagnostics | no `sign_text` anywhere (grep test) | M4 |
| E8 | Position-only persistence; formatter wiped marks | snapshot + diff + quote/context + fuzzy; save after repair | done, M6 |
| E9 | Global label names leaked across files | names per doc record; histories separate | M1 |
| E10 | `<BS>` cancelled the prompt; a third digit cancelled; notify per keystroke | editable buffer; `<BS>` edits; no notify in the prompt | M1 |
| E11 | Hover only on first cell, closed on first move, spilled over neighbour panes, below cursor not span | span-based `find`, hit-set persistence, `place.lua` clamps to the window, below the span's last line | M3 |
| E12 | Buffer line numbers used as screen rows | `screenpos` + `nvim_win_get_position` | M3 |
| E13 | Deprecated APIs; `vim.diff` deprecated on 0.12 | `compat.diff`; banned-API grep test | M0 |
| E14 | Highlight groups lost on `ColorScheme`; 495 eager groups | lazy groups + `ColorScheme` re-apply of created ones and composites | M0, M2 |
| E15 | Global `updatetime` changed; `CursorHold` dependence | timers only | M3 |
| E16 | Statusline monkey-patching lost to user override; brackets inherited mode colours | pure function, fg-only digit groups, no brackets | M7 |
| E17 | Trap prefix / stray key leaked into the new float | which-key group; prompt opens via `vim.schedule` after the operator finishes; buffer-local maps | M1 |
| E18 | Undo/redo stack global and wrong buffer | no custom stack; trash per buffer | done |
| E19 | Multibyte splits at span edges | `excl_end` + char-aware mapping (keep tests) | done |
| E20 | Same-colour nested overlaps invisible | composite underline | M2 |
| E21 | Decoration provider errors every redraw | pcall + self-disable + one WARN | M2 |
| E22 | Snapshot bloats committed JSON / diffs | `snap/` sibling, gitignored | M0 |
| E23 | v1 records on disk unreadable after schema change | lazy migration + fixture test | M0 |
| E24 | Picker backend API drift (snacks/telescope) | pcall + fallback to `vim.ui.select`; tests run the `select` backend | M5 |
| E25 | Ambiguous relocation silently picks wrong text | `ambiguous` status + review list | M6 |
| E26 | `find` misses at end of line | fixed + test | M0 |
| E27 | Hover/prompt opening while in Visual or op-pending mode | `ModeChanged` guards; operator path leaves Visual first | M1, M3 |
| E28 | Note buffers cluttering `:ls` / never wiped | unlisted, wiped on close; test `nvim_list_bufs` count | M3 |
| E29 | Record for a copied file hijacks the original's record | `find_renamed` only when the source is gone (test) | M0 |

## F. Non-goals tonight and items deferred to Stephen

Non-goals (do not build): SQLite backend, encryption/password protection (F23), HTML/Notion export, manual export reorder, PDF/web, S-Reader, sync/sharing, virtual-line drawer (F16), margin view (F42), cursor-following/shrinkable note window (F14), flash label-avoidance geometry, ccc.nvim UI (F38: only the `:Earmark color` hook), `frontmatter_sync` (writes into his files), note-template auto counts, per-background palettes, linked multi-mode picker, DM dashboard work (notes only).

Decided for Stephen, revisit (ask him in the hand-off):
1. `prompt.ask_name = 'first_use'` vs `'always'` (he said the prompt "should always appear"; default picks speed on the count path).
2. `@ident` prefix for identifier tags, rendered `[A]`.
3. Overlap look: blend + underline; value 2 as undercurl; values 3+ as swatches (vs his gradient/interleave idea).
4. Hover header is fg-coloured (`▍ name`), not a filled bar.
5. Indicators toggle has two states (`eol`/`none`); identifiers toggled by config only.
6. No per-background palette; `ui.keep_syntax_fg=false`.
7. `gh` no-count opens the prompt instead of reusing the last label (`<CR>` reuses it).
8. Snapshot gitignored: a fresh clone re-anchors by quote/context only.
9. Statusline content and the digit row.
10. SQLite/encryption dropped for good; JSON only.
11. Default export filename and location (`.earmark/export/`).
12. Should `.earmark/names.json` (directory defaults) be committed? Currently yes (not ignored).
