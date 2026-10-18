"""Render a Neovim screen to HTML (no terminal needed): attach to `nvim --embed` as a UI,
run a Lua scene file, and write the grid with its colours, underlines and undercurls.

    python3 docs/demos/scripts/screen.py SCENE.lua OUT.html [--size 90x14] [--nvim PATH]

The scene runs after earmark is on the runtimepath; it should set up a buffer and call
earmark's API (see docs/demos/scripts/scene_overlaps.lua).
"""
import argparse, html, os, sys
import pynvim

p = argparse.ArgumentParser()
p.add_argument('scene'); p.add_argument('out')
p.add_argument('--size', default='90x14'); p.add_argument('--nvim', default='nvim')
p.add_argument('--title', default='')
p.add_argument('--keys', default='', help='keys typed after the scene (nvim_input notation); '
               '"||" separates steps typed 300 ms apart')
a = p.parse_args()
W, H = map(int, a.size.split('x'))
root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
nvim = pynvim.attach('child', argv=[a.nvim, '--embed', '--clean', '-n', '--cmd', 'set rtp^=' + root])
grid = [[' '] * W for _ in range(H)]
hls = [[0] * W for _ in range(H)]
attrs = {0: {}}
default = {'fg': 0xc0caf5, 'bg': 0x1a1b26, 'sp': 0xff0000}

def handle(name, args):
    for ev in args:
        if name == 'grid_line':
            _, row, col, cells = ev[:4]
            hl = 0
            for c in cells:
                text = c[0]
                if len(c) > 1: hl = c[1]
                rep = c[2] if len(c) > 2 else 1
                for _ in range(rep):
                    if col < W and row < H:
                        grid[row][col] = text; hls[row][col] = hl
                    col += 1
        elif name == 'hl_attr_define':
            attrs[ev[0]] = ev[1]
        elif name == 'default_colors_set':
            if ev[0] >= 0: default['fg'] = ev[0]
            if ev[1] >= 0: default['bg'] = ev[1]
        elif name == 'grid_clear':
            for r in range(H):
                for c in range(W): grid[r][c] = ' '; hls[r][c] = 0

nvim.ui_attach(W, H, rgb=True, ext_linegrid=True)
nvim.exec_lua(open(a.scene).read())
# type the steps, let everything (scheduled UI) settle, then say when to stop listening
nvim.exec_lua('''
  local steps = ...
  local function step(i)
    if i > #steps then
      vim.defer_fn(function()
        vim.cmd('redraw!')
        vim.defer_fn(function() vim.rpcnotify(0, 'screen_done') end, 50)
      end, 400)
      return
    end
    vim.api.nvim_input(steps[i])
    vim.defer_fn(function() step(i + 1) end, 300)
  end
  step(1)
''', [s for s in a.keys.split('||') if s])
def on_notify(name, args):
    if name == 'redraw':
        for ev in args: handle(ev[0], ev[1:])
    elif name == 'screen_done':
        nvim.stop_loop()
nvim.run_loop(None, on_notify)

def css(n): return '#%06x' % n
rows = []
for r in range(H):
    spans, cur, buf = [], None, ''
    def flush():
        if not buf: return
        at = attrs.get(cur, {})
        fg, bg = at.get('foreground', default['fg']), at.get('background', default['bg'])
        if at.get('reverse'): fg, bg = bg, fg
        st = ['color:' + css(fg), 'background:' + css(bg)]
        sp = css(at.get('special', fg))
        deco = None
        if at.get('undercurl'): deco = 'underline wavy ' + sp
        elif at.get('underdouble'): deco = 'underline double ' + sp
        elif at.get('underdashed'): deco = 'underline dashed ' + sp
        elif at.get('underdotted'): deco = 'underline dotted ' + sp
        elif at.get('underline'): deco = 'underline ' + sp
        if deco: st.append('text-decoration:' + deco + ';text-underline-offset:3px;text-decoration-thickness:1.5px')
        if at.get('bold'): st.append('font-weight:bold')
        if at.get('italic'): st.append('font-style:italic')
        spans.append('<span style="%s">%s</span>' % (';'.join(st), html.escape(buf)))
    for c in range(W):
        if hls[r][c] != cur:
            flush(); buf = ''; cur = hls[r][c]
        buf += grid[r][c] or ''
    flush()
    rows.append(''.join(spans))
title = ('<div style="font:600 14px sans-serif;color:%s;margin:0 0 6px">%s</div>' % (css(default['fg']), html.escape(a.title))) if a.title else ''
page = ('<div style="background:%s;padding:12px;display:inline-block">%s<pre style="margin:0;font:16px/1.45 '
        '\'DejaVu Sans Mono\',monospace">%s</pre></div>') % (css(default['bg']), title, '\n'.join(rows))
with open(a.out, 'w') as fh: fh.write(page)
nvim.close()
