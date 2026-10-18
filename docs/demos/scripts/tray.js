// Comment tray for the demos page (page.py inlines this file).
// A card's Comment button opens a box; Add (or Ctrl+Enter) puts the comment in the tray, which
// is kept in this browser until "Send all to Claude" sends every comment as one message.
// Viewers who can't send to Claude get "Post all as comments" (each on its own card) instead.
(async () => {
  const KEY = 'earmark-demos-tray';
  const LIMIT = 4000; // bytes per message; the platform takes at most 4 KiB
  const bytes = s => new TextEncoder().encode(s).length;
  let items = [];
  try { items = JSON.parse(localStorage.getItem(KEY) || '[]') || []; } catch (e) { items = []; }
  const save = () => { try { localStorage.setItem(KEY, JSON.stringify(items)); } catch (e) {} };

  const c = window.claude && await window.claude.use('comments');
  if (!c) return;
  document.querySelectorAll('.commenting').forEach(p => p.hidden = false);

  const el = (tag, props, kids) => {
    const e = Object.assign(document.createElement(tag), props || {});
    (kids || []).forEach(k => e.append(k));
    return e;
  };

  // ---- the tray ----
  const tray = el('section', { className: 'tray', hidden: true });
  tray.setAttribute('aria-label', 'Comments waiting to be sent');
  const count = el('b');
  const toggle = el('span', { className: 'hint' });
  const head = el('header', {}, [el('span', {}, ['Comments in the tray: ', count]), toggle]);
  const list = el('ol');
  const sendBtn = el('button', { className: 'btn primary', type: 'button' });
  const clearBtn = el('button', { className: 'btn', type: 'button', textContent: 'Clear' });
  const status = el('div', { className: 'status' });
  const body = el('div', { className: 'body' }, [list, el('div', { className: 'row' }, [sendBtn, clearBtn]), status]);
  tray.append(head, body);
  document.body.append(tray);

  let open = true, can = 'off', busy = false;
  const say = (text, kind) => { status.textContent = text || ''; status.className = 'status' + (kind ? ' ' + kind : ''); };

  async function check() {
    try { can = await c.canSendToClaude(); } catch (e) { can = 'off'; }
    render();
  }

  function render() {
    tray.hidden = items.length === 0 && !status.textContent;
    count.textContent = String(items.length);
    toggle.textContent = open ? 'hide' : 'show';
    body.hidden = !open;
    sendBtn.textContent = can === 'available' ? 'Send all to Claude' : 'Post all as comments';
    sendBtn.title = can === 'available' ? 'One message to the working session, with every comment in the tray'
      : can === 'no_session' ? 'No Claude session is listening right now: each comment is posted on its card instead'
      : 'Each comment is posted on its own card';
    sendBtn.disabled = busy || items.length === 0;
    clearBtn.disabled = busy || items.length === 0;
    list.replaceChildren(...items.map((it, i) => {
      const edit = el('a', { textContent: 'edit' });
      edit.addEventListener('click', () => { items.splice(i, 1); save(); render(); openBox(document.getElementById(it.id), it.text); });
      const del = el('a', { textContent: 'remove' });
      del.addEventListener('click', () => { items.splice(i, 1); save(); render(); });
      const go = el('a', { textContent: 'go to card', href: '#' + it.id });
      return el('li', {}, [el('div', { className: 't', textContent: it.title }), el('div', { className: 'x', textContent: it.text }),
        el('div', { className: 'acts' }, [edit, del, go])]);
    }));
  }

  head.addEventListener('click', () => { open = !open; render(); });
  clearBtn.addEventListener('click', () => {
    if (!confirm('Remove all ' + items.length + ' comments from the tray?')) return;
    items = []; save(); say(''); render();
  });

  // ---- sending ----
  const ERR = {
    consent_required: 'Allow this page to post comments when asked, then press the button again. Your comments are kept.',
    forbidden: 'This page cannot post comments for you. Your comments are kept in the tray.',
    rate_limited: 'That was too quick for the comment service. Wait a moment and press again.',
    claude_unavailable: 'Claude could not receive it just now, so nothing was sent. Your comments are kept.',
    invalid: 'The comment service refused the text. Edit the longest comment and try again.',
  };

  function pack() {
    // as many comments as fit in one message, in order
    let take = 0, text = '';
    for (let k = 1; k <= items.length; k++) {
      const parts = items.slice(0, k).map((it, i) => (i + 1) + '. ' + it.title + ' (#' + it.id + ')\n' + it.text);
      const t = 'Comments on the earmark demos page (' + k + (k < items.length ? ' of ' + items.length : '') + '):\n\n' + parts.join('\n\n');
      if (bytes(t) > LIMIT) break;
      take = k; text = t;
    }
    return { take, text };
  }

  sendBtn.addEventListener('click', async () => {
    if (busy || !items.length) return;
    busy = true; render();
    try {
      if (can === 'available') {
        const { take, text } = pack();
        await c.sendToClaude({ anchor: await c.anchorFor(document.querySelector('h1')), text });
        items.splice(0, take); save();
        say(items.length
          ? 'Sent ' + take + ' to Claude. ' + items.length + ' more did not fit in one message: press Send again.'
          : 'Sent ' + take + ' to Claude. Its answer appears in the comment thread at the page title.', 'ok');
      } else {
        let posted = 0;
        while (items.length) {
          const it = items[0];
          const card = document.getElementById(it.id) || document.querySelector('h1');
          await c.create({ anchor: await c.anchorFor(card), text: it.text });
          items.shift(); save(); posted++;
        }
        say('Posted ' + posted + ' comments on their cards. Tell Claude in chat to read the demo comments.', 'ok');
      }
    } catch (e) {
      const code = e && e.code;
      if (code === 'claude_unavailable') await check();
      if (code === 'not_granted' || code === 'capability_disabled' || code === 'capability_removed') {
        say('This view cannot post comments. Your comments are kept in the tray.', 'err');
      } else {
        say(ERR[code] || ('Could not send (' + (code || 'error') + '). Your comments are kept; try again.'), 'err');
      }
    } finally {
      busy = false; render();
    }
  });

  // ---- the box on each card ----
  function add(article, text) {
    text = text.trim();
    if (!text) return false;
    if (bytes(text) > 3500) { alert('That comment is too long for one message. Split it in two.'); return false; }
    items.push({ id: article.id, title: article.querySelector('h3 a').textContent, text });
    save(); say(''); open = true; render();
    tray.classList.remove('flash'); void tray.offsetWidth; tray.classList.add('flash');
    return true;
  }

  function openBox(article, text) {
    if (!article) return;
    let box = article.querySelector('.cbox');
    if (!box) {
      const ta = el('textarea', { placeholder: 'Your comment on this demo' });
      const addBtn = el('button', { className: 'btn primary', type: 'button', textContent: 'Add to tray' });
      const cancel = el('button', { className: 'btn', type: 'button', textContent: 'Cancel' });
      box = el('div', { className: 'cbox' }, [ta, el('div', { className: 'row' }, [addBtn, cancel,
        el('span', { className: 'hint', textContent: 'Ctrl+Enter adds it, Esc cancels' })])]);
      const close = () => box.remove();
      const commit = () => { if (add(article, ta.value)) close(); };
      addBtn.addEventListener('click', commit);
      cancel.addEventListener('click', close);
      ta.addEventListener('keydown', e => {
        if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) { e.preventDefault(); e.stopPropagation(); commit(); }
        else if (e.key === 'Escape') { e.preventDefault(); close(); }
      });
      article.querySelector('h3').after(box);
    }
    const ta = box.querySelector('textarea');
    if (text) ta.value = text;
    box.scrollIntoView({ block: 'nearest' });
    ta.focus();
  }

  document.querySelectorAll('article .cbtn').forEach(b => {
    b.hidden = false;
    b.addEventListener('click', () => openBox(b.closest('article')));
  });

  window.addEventListener('focus', check);
  await check();
})();
