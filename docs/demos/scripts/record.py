#!/usr/bin/env python3
"""Record the earmark.nvim demo clips.

Runs Neovim (this checkout, a minimal init, never your own config) in ghostty on a hidden
agentwin desk, types into it with wtype, screenshots each step and joins the frames into a
GIF and an MP4 with ffmpeg.

    python3 docs/demos/scripts/record.py            # every clip
    python3 docs/demos/scripts/record.py hover note # only these clips
    python3 docs/demos/scripts/record.py --list

Needs: agentwin (desk 'earmark-demo', started here if missing), ghostty, wtype (via agentwin),
grim (via agentwin), ffmpeg. Output goes to docs/demos/<clip>.{gif,mp4,png}.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import time

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
OUT = os.path.join(REPO, 'docs', 'demos')
WORK = os.environ.get('EARMARK_DEMOS_DIR', '/tmp/earmark-demos')
DESK = os.environ.get('EARMARK_DEMOS_DESK', 'earmark-demo')
SIZE = os.environ.get('EARMARK_DEMOS_SIZE', '')  # empty: fit the desk to its viewer
BASE, RUN = WORK + '/base', WORK + '/run'
SOCK = WORK + '/nvim.sock'
FONT = os.environ.get('EARMARK_DEMOS_FONT', 'CaskaydiaCove NFM')
FONT_SIZE = os.environ.get("EARMARK_DEMOS_FONT_SIZE", "")  # empty: from the desk width

def sh(*cmd, check=True, timeout=30, **kw):
    return subprocess.run(cmd, check=check, text=True, capture_output=True, timeout=timeout, **kw)


def desk_size():
    out = sh('agentwin', 'ctl', '--desk', DESK, 'monitors', '-j').stdout
    m = json.loads(out)[0]
    return m['width'], m['height']


def font_size():
    if FONT_SIZE:
        return FONT_SIZE
    w, _ = desk_size()
    return str(max(14, round(w / 84)))

def desk_up():
    st = sh('agentwin', 'desk', 'status', DESK, check=False).stdout
    if 'paused' in st:
        sys.exit('desk is paused (gaming mode); try again later')
    if 'up' not in st:
        env = dict(os.environ)
        env.pop('AGENTWIN_SIZE', None)
        if SIZE:
            env['AGENTWIN_SIZE'] = SIZE
        subprocess.run(['agentwin', 'desk', 'start', DESK], check=True, env=env)
        if not SIZE:
            sh('agentwin', 'desk', 'fit', DESK, check=False)
    # no mouse pointer in the frames
    sh('agentwin', 'ctl', '--desk', DESK, 'eval', 'hl.config({cursor={invisible=true}})', check=False)

def build_fixture():
    sh('nvim', '--headless', '--clean', '-l', REPO + '/docs/demos/scripts/fixture.lua', REPO, BASE)

# --- key notation -> wtype arguments -------------------------------------------------------
SPECIAL = {
    'CR': ['-k', 'Return'], 'Esc': ['-k', 'Escape'], 'Tab': ['-k', 'Tab'],
    'S-Tab': ['-M', 'shift', '-k', 'Tab', '-m', 'shift'], 'BS': ['-k', 'BackSpace'],
    'Down': ['-k', 'Down'], 'Up': ['-k', 'Up'], 'Space': [' '], 'lt': ['<'],
}

def tokens(seq):
    """'3ghiw<CR>' -> ['3','g','h','i','w','<CR>']"""
    out, i = [], 0
    while i < len(seq):
        m = re.match(r'<([A-Za-z0-9-]+)>', seq[i:])
        if m:
            out.append('<%s>' % m.group(1))
            i += m.end()
        else:
            out.append(seq[i])
            i += 1
    return out

def wtype_args(tok):
    if tok.startswith('<') and len(tok) > 2:
        name = tok[1:-1]
        if name in SPECIAL:
            return SPECIAL[name]
        m = re.match(r'C-(.)$', name)
        if m:
            return ['-M', 'ctrl', m.group(1), '-m', 'ctrl']
        raise ValueError('unknown key ' + tok)
    return [tok]

# --- one recording -------------------------------------------------------------------------
class Clip:
    """One recording. Pacing: a 'before' frame for each step, then the keys, then the result
    held a few seconds; the last frame of the clip is held longest."""
    BEFORE, AFTER, END = 1.5, 2.5, 3.5

    def __init__(self, name, title, file='notes/essay.md', opts='', cursor=None, still=False, legend=None,
                 zoom=None):
        self.name, self.title, self.file, self.opts, self.cursor = name, title, file, opts, cursor
        self.still_only, self.legend = still, legend
        self.zoom = zoom  # (x, y, w, h) as fractions of the frame: also write <name>-zoom.png at 2x
        self.frames = []  # (png, seconds)
        self.dir = os.path.join(WORK, 'frames', name)

    # lifecycle
    def __enter__(self):
        shutil.rmtree(RUN, ignore_errors=True)
        shutil.copytree(BASE, RUN)
        for root, _, files in os.walk(RUN):
            for f in files:
                if f.endswith('.json'):
                    p = os.path.join(root, f)
                    s = open(p).read()
                    if BASE in s:
                        open(p, 'w').write(s.replace(BASE, RUN))
        shutil.rmtree(self.dir, ignore_errors=True)
        os.makedirs(self.dir)
        if os.path.exists(SOCK):
            os.remove(SOCK)
        env = dict(os.environ, EARMARK_DEMO_OPTS=self.opts, EARMARK_DEMO_REC='1',
                   EARMARK_DEMO_LAZY=os.path.expanduser('~/.local/share/nvim/lazy'),
                   XDG_CONFIG_HOME=RUN + '/xdg/config', XDG_DATA_HOME=RUN + '/xdg/data',
                   XDG_STATE_HOME=RUN + '/xdg/state', XDG_CACHE_HOME=RUN + '/xdg/cache')
        cmd = ['agentwin', 'run', '--desk', DESK, '--',
               'ghostty', '--config-default-files=false', '--font-family=' + FONT,
               '--font-size=' + font_size(), '--window-decoration=false', '--gtk-titlebar=false',
               '--window-padding-x=10', '--window-padding-y=6', '--background=#1a1b26',
               '--confirm-close-surface=false', '--cursor-style-blink=false',
               '--working-directory=' + RUN + '/proj',
               '-e', 'nvim', '-u', RUN + '/init.lua', '--listen', SOCK, RUN + '/proj/' + self.file]
        self.proc = subprocess.Popen(cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(100):
            if os.path.exists(SOCK):
                break
            time.sleep(0.1)
        else:
            raise RuntimeError('nvim did not start')
        time.sleep(1.5)
        if self.cursor:
            self.lua('vim.api.nvim_win_set_cursor(0, {%d, %d})' % self.cursor)
        self.note('')
        time.sleep(0.3)
        return self

    def __exit__(self, et, ev, tb):
        if et is None and self.frames:
            f, _ = self.frames[-1]
            self.frames[-1] = (f, max(self.frames[-1][1], self.END))
        try:
            self.expr('execute("qall!")')
        except Exception:
            pass
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        if et is None:
            self.encode()

    # neovim RPC (setup and the on-screen title/notes only; features are driven by real keys)
    def expr(self, e):
        return sh('nvim', '--server', SOCK, '--remote-expr', e, timeout=10).stdout

    def lua(self, code):
        return self.expr('luaeval(%s)' % json.dumps('(function() ' + code + ' end)() or ""'))

    def note(self, text=''):
        """Title stays; set the step note and clear the key box."""
        self.expr('v:lua.Demo_step(%s, %s)' % (json.dumps(self.title), json.dumps(text)))

    def goto(self, row, col):
        self.lua('vim.api.nvim_win_set_cursor(0, {%d, %d})' % (row, col))

    # input and frames
    def key(self, tok):
        sh('agentwin', 'key', '--desk', DESK, '--', *wtype_args(tok))

    def shot(self, hold=None, wait=0.4):
        time.sleep(wait)
        f = os.path.join(self.dir, '%04d.png' % len(self.frames))
        sh('agentwin', 'shot', '--desk', DESK, f)
        self.frames.append((f, self.AFTER if hold is None else hold))
        return f

    def keys(self, seq, gap=0.12):
        for t in tokens(seq):
            self.key(t)
            time.sleep(gap)

    def step(self, seq, note='', before=None, hold=None, wait=1.0):
        """One keystroke group: note + 'before' frame, type the keys, pause, result frame."""
        self.note(note)
        if before is None:
            before = self.BEFORE
        if before:
            self.shot(before, wait=0.3)
        self.keys(seq)
        return self.shot(hold, wait=wait)

    def more(self, seq, hold=None, wait=1.0):
        """More keys in the same step (into a prompt, a picker...), then a result frame."""
        self.keys(seq)
        return self.shot(hold, wait=wait)

    def text(self, s, hold=None, wait=0.8):
        """Literal text in one go (no key notation), then a frame."""
        sh('agentwin', 'key', '--desk', DESK, '--', s)
        return self.shot(hold, wait=wait)

    def ex(self, line, note='', hold=None):
        """Type an Ex command visibly (frame before Enter), then run it."""
        self.note(note)
        self.shot(self.BEFORE, wait=0.3)
        self.keys(':')
        self.text(line, hold=1.5)
        return self.more('<CR>', hold=hold)

    def mark_still(self):
        """Use the latest frame as the clip's still screenshot."""
        self.still = self.frames[-1][0]

    @staticmethod
    def _size(png):
        out = sh('magick', 'identify', '-format', '%w %h', png).stdout.split()
        return int(out[0]), int(out[1])

    # output
    def encode(self):
        if not self.frames:
            return
        width = os.environ.get('EARMARK_DEMOS_GIF_WIDTH', '1280')
        png = os.path.join(OUT, self.name + '.png')
        still = getattr(self, 'still', self.frames[-1][0])
        if self.legend:
            # an annotated screenshot: the frame with a numbered legend under it
            text = '\n'.join(self.legend)
            sh('magick', still, '-resize', width + 'x',
               '(', '-size', '%dx' % (int(width) - 36), '-background', '#1f2335', '-fill', '#c0caf5',
               '-font', 'Adwaita-Sans', '-pointsize', '22', '-interline-spacing', '6',
               'caption:' + text, '-bordercolor', '#1f2335', '-border', '18', ')',
               '-append', png)
        else:
            sh('ffmpeg', '-y', '-loglevel', 'error', '-i', still, '-vf', 'scale=%s:-1:flags=lanczos' % width, png)
        if self.zoom:
            x, y, w, h = self.zoom
            sh('magick', still, '-crop', '%d%%x%d%%+0+0' % (100, 100), '+repage',
               '-gravity', 'NorthWest', '-crop',
               '%sx%s+%s+%s' % tuple(str(int(v * d)) for v, d in
                                     zip((w, h, x, y), [self._size(still)[0], self._size(still)[1]] * 2)),
               '+repage', '-filter', 'point', '-resize', '200%',
               os.path.join(OUT, self.name + '-zoom.png'))
        if self.still_only:
            print('  %s: still, png %.0f KB' % (self.name, os.path.getsize(png) / 1024), flush=True)
            return
        lst = os.path.join(self.dir, 'list.txt')
        with open(lst, 'w') as fh:
            for f, d in self.frames:
                fh.write("file '%s'\nduration %.2f\n" % (f, d))
            fh.write("file '%s'\n" % self.frames[-1][0])
        gif = os.path.join(OUT, self.name + '.gif')
        mp4 = os.path.join(OUT, self.name + '.mp4')
        sh('ffmpeg', '-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', lst,
           '-vf', 'scale=%s:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=96:stats_mode=full[p];'
                  '[b][p]paletteuse=dither=none' % width,
           '-fps_mode', 'vfr', gif)
        sh('ffmpeg', '-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', lst,
           '-vf', 'fps=10,scale=1600:-2:flags=lanczos,format=yuv420p',
           '-c:v', 'libx264', '-crf', '30', '-preset', 'slow', '-movflags', '+faststart', mp4)
        print('  %s: %d frames, gif %.0f KB, mp4 %.0f KB' % (
            self.name, len(self.frames), os.path.getsize(gif) / 1024, os.path.getsize(mp4) / 1024), flush=True)


def main():
    from clips import CLIPS
    args = sys.argv[1:]
    if args == ['--list']:
        for name, _, _ in CLIPS:
            print(name)
        return
    desk_up()
    build_fixture()
    os.makedirs(OUT, exist_ok=True)
    for name, kw, fn in CLIPS:
        if args and name not in args:
            continue
        print('recording', name, flush=True)
        with Clip(name, **kw) as c:
            fn(c)


if __name__ == '__main__':
    sys.path.insert(0, os.path.dirname(__file__))
    main()
