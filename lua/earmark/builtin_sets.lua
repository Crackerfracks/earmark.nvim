-- Named sets that ship with earmark. List one by name in `sets` like a palette:
--   sets = { 'vivid', 'feedback' }
local M = {}

-- Feedback on something Claude (or anyone) made: a plan, a demo, a draft, code. Keys 1-9,
-- so a count picks the label (2ghip: "change this paragraph"); the note says what to do.
M.feedback = {
  desc = 'Feedback on a draft, plan, demo or code',
  labels = {
    { key = '1', name = 'Keep', color = '#98c379', desc = 'good as it is' },
    { key = '2', name = 'Change', color = '#e5c07b', desc = 'change this (the note says how)' },
    { key = '3', name = 'Wrong', color = '#e06c75', desc = 'incorrect, or a bug' },
    { key = '4', name = 'Question', color = '#61afef', desc = 'I have a question about this' },
    { key = '5', name = 'Unclear', color = '#c678dd', desc = 'confusing or hard to follow' },
    { key = '6', name = 'Cut', color = '#7f848e', desc = 'remove this' },
    { key = '7', name = 'Idea', color = '#56b6c2', desc = 'an idea or something to add' },
    { key = '8', name = 'Prefer', color = '#d19a66', desc = 'choose this option' },
    { key = '9', name = 'Later', color = '#a9b1d6', desc = 'not now; park it' },
  },
  tags = { 'todo', 'blocker', 'nit' },
}

return M
