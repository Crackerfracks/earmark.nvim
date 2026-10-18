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
STATE = WORK + '/keybox.json'  # the step note and the keys being pressed, drawn by keyview.py
KEYBOX_H = int(os.environ.get('EARMARK_DEMOS_KEYBOX_HEIGHT', '120'))  # px band under Neovim for the key box
NVIM_CLASS, KEYS_CLASS = 'earmark.nvim', 'earmark.keys'
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

def _clients():
    return json.loads(sh('agentwin', 'ctl', '--desk', DESK, 'clients', '-j').stdout or '[]')


def _dispatch(lua):
    sh('agentwin', 'ctl', '--desk', DESK, 'eval', lua)


def place_windows():
    """Neovim on top, the key box in a band under it (both floating, exact sizes)."""
    for _ in range(100):
        classes = {c.get('class') for c in _clients()}
        if NVIM_CLASS in classes and KEYS_CLASS in classes:
            break
        time.sleep(0.1)
    else:
        raise RuntimeError('windows did not appear')
    w, h = desk_size()
    for cls, (x, y, cw, ch) in ((NVIM_CLASS, (0, 0, w, h - KEYBOX_H)), (KEYS_CLASS, (0, h - KEYBOX_H, w, KEYBOX_H))):
        sel = 'class:^(%s)$' % cls
        _dispatch('hl.dispatch(hl.dsp.window.float({ action = "enable", window = "%s" })) '
                  'hl.dispatch(hl.dsp.window.resize({ x = %d, y = %d, window = "%s" })) '
                  'hl.dispatch(hl.dsp.window.move({ x = %d, y = %d, window = "%s" }))'
                  % (sel, cw, ch, sel, x, y, sel))


def close_window(cls):
    _dispatch('hl.dispatch(hl.dsp.window.close({ window = "class:^(%s)$" }))' % cls)


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
    if tok == '-':  # a lone "-" means "read stdin" to wtype
        return ['-k', 'minus']
    return [tok]

# --- how keys read in the key box ---------------------------------------------------------
KEY_NAMES = {
    '<CR>': ' ⏎Enter ', '<Esc>': ' Esc ', '<Tab>': ' Tab ', '<S-Tab>': ' S-Tab ', '<BS>': ' ←Backspace ',
    '<Down>': ' ↓ ', '<Up>': ' ↑ ', '<lt>': '<',
}


def key_label(tok, literal=False):
    """How a key reads in the key box: Space is <leader> in a key string, a space in typed text."""
    if tok == ' ':
        return ' ' if literal else '<leader>'
    if tok in KEY_NAMES:
        return KEY_NAMES[tok]
    m = re.match(r'<C-(.)>$', tok)
    if m:
        return ' Ctrl-%s ' % m.group(1).lower()
    return tok


# --- one recording -------------------------------------------------------------------------
# Neighbouring keys on a QWERTY keyboard, for believable typos.
NEIGHBOURS = {
    'a': 'sq', 'b': 'vn', 'c': 'xv', 'd': 'sf', 'e': 'wr', 'f': 'dg', 'g': 'fh', 'h': 'gj', 'i': 'uo',
    'j': 'hk', 'k': 'jl', 'l': 'k', 'm': 'n', 'n': 'bm', 'o': 'ip', 'p': 'o', 'q': 'w', 'r': 'et',
    's': 'ad', 't': 'ry', 'u': 'yi', 'v': 'cb', 'w': 'qe', 'x': 'zc', 'y': 'tu', 'z': 'x',
}


class Clip:
    """One recording, paced like a person at the keyboard.

    Every keystroke gets its own frame, shown for a human-like gap (90-220 ms, more before
    Enter, now and then a hesitation). Before each action the step note is held 1.6-2 s so it
    can be read; each result is held at least 3 s and the last one 4.5 s. Literal text (names,
    notes, queries, Ex commands) may get one typo, fixed with Backspace, in clips that ask for it;
    keys that drive an operator never do."""
    BEFORE, AFTER, END = 1.8, 3.0, 4.5

    def __init__(self, name, title, file='notes/essay.md', opts='', cursor=None, still=False, legend=None,
                 zoom=None, typo=False):
        import random
        self.name, self.title, self.file, self.opts, self.cursor = name, title, file, opts, cursor
        self.still_only, self.legend = still, legend
        self.zoom = zoom  # (x, y, w, h) as fractions of the frame: also write <name>-zoom.png at 2x
        self.typo = typo  # one typo, fixed with Backspace, in the first long enough literal text
        self.rng = random.Random(name)  # the same clip is paced the same way every run
        self.frames = []  # (png, seconds, step note, keys shown)
        self.cap_note, self.cap_keys, self.cap_fresh = '', [], False
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
        self.write_state()
        env = dict(os.environ, EARMARK_DEMO_OPTS=self.opts, EARMARK_DEMO_REC='1', EARMARK_DEMO_KEYBOX='outside',
                   EARMARK_DEMO_LAZY=os.path.expanduser('~/.local/share/nvim/lazy'),
                   XDG_CONFIG_HOME=RUN + '/xdg/config', XDG_DATA_HOME=RUN + '/xdg/data',
                   XDG_STATE_HOME=RUN + '/xdg/state', XDG_CACHE_HOME=RUN + '/xdg/cache')
        cmd = ['agentwin', 'run', '--desk', DESK, '--',
               'ghostty', '--config-default-files=false', '--font-family=' + FONT,
               '--font-size=' + font_size(), '--window-decoration=false', '--gtk-titlebar=false',
               '--window-padding-x=10', '--window-padding-y=6', '--background=#1a1b26',
               '--confirm-close-surface=false', '--cursor-style-blink=false', '--class=' + NVIM_CLASS,
               '--working-directory=' + RUN + '/proj',
               '-e', 'nvim', '-u', RUN + '/init.lua', '--listen', SOCK, RUN + '/proj/' + self.file]
        keybox = ['agentwin', 'run', '--desk', DESK, '--',
                  'ghostty', '--config-default-files=false', '--font-family=' + FONT,
                  '--font-size=' + str(int(font_size()) + 1), '--window-decoration=false', '--gtk-titlebar=false',
                  '--window-padding-x=6', '--window-padding-y=0', '--background=#1a1b26',
                  '--confirm-close-surface=false', '--class=' + KEYS_CLASS,
                  '-e', 'python3', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'keyview.py'), STATE]
        self.keys_proc = subprocess.Popen(keybox, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.proc = subprocess.Popen(cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        place_windows()
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
            f, d, n, k = self.frames[-1]
            self.frames[-1] = (f, max(d, self.END), n, k)
        try:
            self.expr('execute("qall!")')
        except Exception:
            pass
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        close_window(KEYS_CLASS)
        try:
            self.keys_proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.keys_proc.kill()
        if et is None:
            self.encode()

    # neovim RPC (setup and the on-screen title/notes only; features are driven by real keys)
    def expr(self, e):
        return sh('nvim', '--server', SOCK, '--remote-expr', e, timeout=10).stdout

    def lua(self, code):
        return self.expr('luaeval(%s)' % json.dumps('(function() ' + code + ' end)() or ""'))

    def note(self, text='', clear=False):
        """Title stays; set the step note. The key box keeps the last keys until the next key
        (or clears them now, with clear=True)."""
        self.expr('v:lua.Demo_step(%s, %s, %d)' % (json.dumps(self.title), json.dumps(text), int(clear)))
        self.cap_note, self.cap_fresh = text, True
        if clear:
            self.cap_keys = []
        self.write_state()

    def goto(self, row, col):
        self.lua('vim.api.nvim_win_set_cursor(0, {%d, %d})' % (row, col))

    # input and frames
    def key(self, tok):
        sh('agentwin', 'key', '--desk', DESK, '--window', 'class:^(%s)$' % NVIM_CLASS, '--', *wtype_args(tok))

    def show(self, tok, literal=False):
        """Add a pressed key to the caption strip (the keys stay until the next step's first key)."""
        if self.cap_fresh:
            self.cap_keys, self.cap_fresh = [], False
        self.cap_keys.append(key_label(tok, literal))
        self.write_state()

    def write_state(self):
        """What the key box (keyview.py) shows: the step note and the keys so far."""
        tmp = STATE + '.tmp'
        with open(tmp, 'w') as fh:
            json.dump({'note': self.cap_note, 'keys': ''.join(self.cap_keys)}, fh)
        os.replace(tmp, STATE)

    def shot(self, hold=None, wait=0.4):
        time.sleep(wait)
        f = os.path.join(self.dir, '%04d.png' % len(self.frames))
        sh('agentwin', 'shot', '--desk', DESK, f)
        self.frames.append((f, self.AFTER if hold is None else hold, self.cap_note, ''.join(self.cap_keys)))
        return f

    def gap(self, nxt=None):
        """How long a person takes before the next key."""
        if nxt == '<CR>':
            return self.rng.uniform(0.55, 0.9)
        g = self.rng.uniform(0.09, 0.22)
        if self.rng.random() < 0.08:
            g += self.rng.uniform(0.3, 0.6)  # a hesitation
        return g

    def _type(self, toks, hold, wait):
        """Press each key with its own frame; the last frame is held 'hold' seconds."""
        if self.still_only:  # stills only keep the last frame: no need to film each key
            for t in toks:
                self.show(t)
                self.key(t)
            return self.shot(hold, wait=wait)
        f = None
        for i, t in enumerate(toks):
            self.show(t)
            self.key(t)
            if i + 1 < len(toks):
                f = self.shot(self.gap(toks[i + 1]), wait=0.1)
            else:
                f = self.shot(hold, wait=wait)
        return f

    def keys(self, seq, hold=None, wait=1.0):
        return self._type(tokens(seq), hold, wait)

    def _result_hold(self, hold):
        return self.AFTER if hold is None else max(hold, self.AFTER)

    def step(self, seq, note='', before=None, hold=None, wait=1.0):
        """One action: the note is shown and held (with the cursor already on its target, as a
        pause for effect), then the keys one by one, then the result held to be read."""
        self.note(note)
        if before is None:
            before = self.rng.uniform(1.6, 2.0)
        if before:
            self.shot(before, wait=0.3)
        return self.keys(seq, self._result_hold(hold), wait)

    def more(self, seq, hold=None, wait=1.0):
        """More keys in the same step (into a prompt, a picker...), then the result held."""
        return self.keys(seq, self._result_hold(hold), wait)

    def text(self, s, hold=None, wait=0.8):
        """Literal text, a character at a time (maybe with one typo fixed with Backspace), then
        a pause on the typed text, usually before Enter."""
        toks = list(s)
        if self.typo and len(s) >= 6:
            spots = [i for i in range(2, len(s) - 1) if s[i].lower() in NEIGHBOURS and s[i].islower()]
            if spots:
                i = self.rng.choice(spots)
                wrong = self.rng.choice(NEIGHBOURS[s[i]])
                toks = list(s[:i]) + [wrong, '<HES>', '<BS>', '<HES>'] + list(s[i:])
                self.typo = False
        pressed = [t for t in toks if t != '<HES>']
        if self.still_only:
            for t in pressed:
                self.show(t, literal=True)
                self.key(t)
            return self.shot(max(hold or 0, 1.0), wait=wait)
        f = None
        for i, t in enumerate(toks):
            if t == '<HES>':
                continue
            self.show(t, literal=True)
            self.key(t)
            rest = toks[i + 1:]
            if not [x for x in rest if x != '<HES>']:
                f = self.shot(max(hold or 0, 1.0), wait=wait)
            elif rest[0] == '<HES>':
                f = self.shot(self.rng.uniform(0.45, 0.7), wait=0.1)  # notices the typo / recovers
            else:
                f = self.shot(self.gap(), wait=0.1)
        return f

    def ex(self, line, note='', hold=None):
        """Type an Ex command visibly, a key at a time, pause on it, then run it."""
        self.note(note)
        self.shot(self.rng.uniform(1.6, 2.0), wait=0.3)
        self.keys(':', hold=self.gap(), wait=0.1)
        self.text(line, hold=1.2)
        return self.more('<CR>', hold=hold)

    def mark_still(self):
        """Use the latest frame as the clip's still screenshot."""
        self.still_i = len(self.frames) - 1

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
        still = self.frames[getattr(self, 'still_i', -1)][0]
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
            for f, d, _, _ in self.frames:
                fh.write("file '%s'\nduration %.2f\n" % (f, d))
            fh.write("file '%s'\n" % self.frames[-1][0])
        gif = os.path.join(OUT, self.name + '.gif')
        mp4 = os.path.join(OUT, self.name + '.mp4')
        sh('ffmpeg', '-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', lst,
           '-vf', 'scale=%s:-1:flags=lanczos,split[a][b];'
                  '[a]palettegen=max_colors=96:stats_mode=full[p];[b][p]paletteuse=dither=none:diff_mode=rectangle'
                  % width,
           '-fps_mode', 'vfr', gif, timeout=600)
        sh('ffmpeg', '-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', lst,
           '-vf', 'fps=25,scale=1600:-2:flags=lanczos,format=yuv420p',
           '-c:v', 'libx264', '-crf', '30', '-preset', 'slow', '-movflags', '+faststart', mp4, timeout=600)
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
