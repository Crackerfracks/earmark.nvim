#!/usr/bin/env python3
"""The key box for the demo recordings: a small terminal under Neovim that shows the current
step's note and the keys as they are pressed.

    keyview.py STATE.json

record.py writes STATE.json ({"note": ..., "keys": ...}) just before every keypress; this
redraws within ~30 ms. It lives outside Neovim on purpose: while a count, an operator or a
mapping prefix such as <leader>m waits for more keys, Neovim redraws nothing, so a box drawn by
Neovim itself can only show those keys once the command is complete.
"""
import json
import os
import shutil
import sys
import time

BG = (26, 27, 38)        # page background (#1a1b26), same as the editor
BOX = (47, 53, 73)       # box background (#2f3549)
BORDER = (224, 175, 104)  # amber border (#e0af68)
NOTE = (192, 202, 245)   # note text (#c0caf5)
KEYS_FG = (26, 27, 38)
KEYS_BG = (224, 175, 104)
MIN_W = 46


def fg(c):
    return '\x1b[38;2;%d;%d;%dm' % c


def bg(c):
    return '\x1b[48;2;%d;%d;%dm' % c


def draw(note, keys):
    cols, rows = shutil.get_terminal_size((100, 4))
    out = ['\x1b[H', bg(BG), '\x1b[2J']
    if note or keys:
        inner = min(cols - 4, max(MIN_W, len(note) + 2, len(keys) + 9))
        k = keys or '…'
        room = inner - 8
        if len(k) > room:
            k = '…' + k[-(room - 1):]
        note_line = (' ' + note).ljust(inner)[:inner]
        keys_line = (' keys: ' + k).ljust(inner)[:inner]
        x = cols - inner - 3  # right-aligned, like the old box at the bottom right
        top = max(0, (rows - 4) // 2) if rows >= 4 else 0
        lines = []
        if rows >= 4:
            lines.append(fg(BORDER) + bg(BG) + '╭' + '─' * inner + '╮')
        if note:
            lines.append(fg(BORDER) + bg(BOX) + '│' + fg(NOTE) + '\x1b[3m' + note_line + '\x1b[23m'
                         + fg(BORDER) + '│')
        lines.append(fg(BORDER) + bg(BOX) + '│' + fg(KEYS_FG) + bg(KEYS_BG) + '\x1b[1m' + keys_line
                     + '\x1b[22m' + fg(BORDER) + bg(BOX) + '│')
        if rows >= 4:
            lines.append(fg(BORDER) + bg(BG) + '╰' + '─' * inner + '╯')
        for i, l in enumerate(lines[:rows]):
            out.append('\x1b[%d;%dH' % (top + i + 1, x + 1) + l)
    out.append(bg(BG))
    sys.stdout.write(''.join(out))
    sys.stdout.flush()


def main():
    path = sys.argv[1]
    sys.stdout.write('\x1b[?25l\x1b[?7l')  # no cursor, no wrapping
    last = None
    while True:
        try:
            st = os.stat(path)
            sig = (st.st_mtime_ns, st.st_size, shutil.get_terminal_size())
        except OSError:
            sig = None
        if sig != last:
            last = sig
            try:
                with open(path) as fh:
                    d = json.load(fh)
            except (OSError, ValueError):
                d = {}
            draw(d.get('note', ''), d.get('keys', ''))
        time.sleep(0.03)


if __name__ == '__main__':
    main()
