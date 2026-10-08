/*
 * app.js — Giao diện chính của Sổ tay DSA C++.
 */
(function () {
  'use strict';

  const { Store, Settings, Share, Cpp } = window.Services;
  const V = window.VCS;
  const T = window.TEMPLATES;

  // ===================== Tiện ích DOM =====================
  function h(tag, attrs, ...kids) {
    const el = document.createElement(tag);
    if (attrs)
      Object.entries(attrs).forEach(([k, v]) => {
        if (v === undefined || v === null || v === false) return;
        if (k === 'class') el.className = v;
        else if (k === 'style' && typeof v === 'object') Object.assign(el.style, v);
        else if (k.startsWith('on')) el.addEventListener(k.slice(2).toLowerCase(), v);
        else if (k === 'html') el.innerHTML = v;
        else if (k in el && typeof v !== 'string') el[k] = v;
        else el.setAttribute(k, v === true ? '' : v);
      });
    kids.flat(Infinity).forEach((c) => {
      if (c === null || c === undefined || c === false) return;
      el.appendChild(c instanceof Node ? c : document.createTextNode(String(c)));
    });
    return el;
  }
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const $app = document.getElementById('app');

  function toast(msg, isErr) {
    const el = h('div', { class: 'toast' + (isErr ? ' err' : '') }, msg);
    document.getElementById('toasts').appendChild(el);
    setTimeout(() => el.remove(), isErr ? 6000 : 3000);
  }

  function timeAgo(t) {
    const s = (Date.now() - t) / 1000;
    if (s < 60) return 'vừa xong';
    if (s < 3600) return `${Math.floor(s / 60)} phút trước`;
    if (s < 86400) return `${Math.floor(s / 3600)} giờ trước`;
    if (s < 86400 * 30) return `${Math.floor(s / 86400)} ngày trước`;
    return new Date(t).toLocaleDateString('vi-VN');
  }
  const fullTime = (t) => new Date(t).toLocaleString('vi-VN');

  // ===================== Modal =====================
  function modal({ title, body, actions = [], wide = false, onClose }) {
    const bg = h('div', { class: 'modal-bg' });
    const close = () => {
      bg.remove();
      document.removeEventListener('keydown', onKey);
      onClose && onClose();
    };
    const onKey = (e) => e.key === 'Escape' && close();
    document.addEventListener('keydown', onKey);
    bg.addEventListener('mousedown', (e) => e.target === bg && close());
    const box = h('div', { class: 'modal' + (wide ? ' wide' : ''), role: 'dialog', 'aria-modal': 'true' },
      h('button', { class: 'x', title: 'Đóng', onclick: close }, '✕'),
      h('h2', null, title),
      body,
      actions.length ? h('div', { class: 'actions' }, actions.map((a) =>
        h('button', {
          class: a.primary ? 'primary' : a.danger ? 'danger' : '',
          onclick: async () => {
            try {
              const keep = a.onClick ? await a.onClick() : undefined;
              if (keep !== false) close();
            } catch (err) {
              toast(err.message, true);
            }
          },
        }, a.label)
      )) : null
    );
    bg.appendChild(box);
    document.body.appendChild(bg);
    const f = box.querySelector('input, textarea, select');
    if (f) setTimeout(() => f.focus(), 30);
    return { close, box };
  }

  function confirmBox(title, text, okLabel = 'Đồng ý', danger = false) {
    return new Promise((resolve) => {
      let done = false;
      modal({
        title,
        body: h('p', null, text),
        actions: [
          { label: 'Huỷ', onClick: () => { done = true; resolve(false); } },
          { label: okLabel, primary: !danger, danger, onClick: () => { done = true; resolve(true); } },
        ],
        onClose: () => !done && resolve(false),
      });
    });
  }

  function promptBox(title, label, value = '') {
    return new Promise((resolve) => {
      const input = h('input', { value });
      let done = false;
      const m = modal({
        title,
        body: h('label', { class: 'field' }, label, input),
        actions: [
          { label: 'Huỷ' },
          { label: 'OK', primary: true, onClick: () => { done = true; resolve(input.value.trim()); } },
        ],
        onClose: () => !done && resolve(null),
      });
      input.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') { done = true; resolve(input.value.trim()); m.close(); }
      });
    });
  }

  // ===================== Theme =====================
  function applyTheme() {
    const pref = Settings.get('theme');
    const dark = pref === 'dark' || (pref === 'auto' && matchMedia('(prefers-color-scheme: dark)').matches);
    document.documentElement.dataset.theme = dark ? 'dark' : 'light';
    const l = document.getElementById('hljs-light');
    const d = document.getElementById('hljs-dark');
    if (l && d) { l.disabled = dark; d.disabled = !dark; }
  }
  matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => { applyTheme(); render(); });
  const isDark = () => document.documentElement.dataset.theme === 'dark';

  // ===================== Markdown =====================
  function renderMarkdown(text) {
    if (window.marked && window.DOMPurify) {
      const html = DOMPurify.sanitize(marked.parse(text || '', { gfm: true, breaks: true }));
      const div = h('div', { class: 'md', html });
      if (window.hljs) div.querySelectorAll('pre code').forEach((c) => {
        try { hljs.highlightElement(c); } catch (_) { /* ngôn ngữ lạ */ }
      });
      div.querySelectorAll('a').forEach((a) => { a.target = '_blank'; a.rel = 'noopener noreferrer'; });
      return div;
    }
    return h('div', { class: 'md', style: { whiteSpace: 'pre-wrap' } }, text || '');
  }

  // ===================== Video =====================
  function parseVideo(url) {
    if (!url) return null;
    let u;
    try { u = new URL(url.trim()); } catch (_) { return null; }
    const host = u.hostname.replace(/^www\.|^m\./, '');
    let id = null;
    if (host === 'youtu.be') id = u.pathname.slice(1).split('/')[0];
    else if (host.endsWith('youtube.com') || host === 'youtube-nocookie.com') {
      if (u.pathname === '/watch') id = u.searchParams.get('v');
      else {
        const m = u.pathname.match(/^\/(embed|shorts|live|v)\/([\w-]+)/);
        if (m) id = m[2];
      }
      const list = u.searchParams.get('list');
      if (!id && list) return { kind: 'yt-list', list };
    }
    if (id) {
      const t = u.searchParams.get('t') || u.searchParams.get('start');
      return { kind: 'yt', id, start: t ? parseTime(t) : 0 };
    }
    if (/\.(mp4|webm|ogg)(\?|$)/i.test(u.pathname)) return { kind: 'file', src: u.href };
    if (u.protocol === 'https:' || u.protocol === 'http:') return { kind: 'link', href: u.href };
    return null;
  }
  function parseTime(t) {
    if (/^\d+$/.test(t)) return Number(t);
    const m = String(t).match(/(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?/);
    if (m && (m[1] || m[2] || m[3])) return (Number(m[1]) || 0) * 3600 + (Number(m[2]) || 0) * 60 + (Number(m[3]) || 0);
    const parts = String(t).split(':').map(Number);
    return parts.reduce((acc, x) => acc * 60 + x, 0);
  }
  function parseTimestamps(text) {
    return (text || '').split('\n').map((line) => {
      const m = line.trim().match(/^((?:\d{1,2}:)?\d{1,2}:\d{2})\s*[-–:]?\s*(.*)$/);
      return m ? { sec: parseTime(m[1]), time: m[1], label: m[2] } : null;
    }).filter(Boolean);
  }
  const ytEmbed = (id, start = 0, autoplay = false) =>
    `https://www.youtube-nocookie.com/embed/${encodeURIComponent(id)}?rel=0${start ? `&start=${start}` : ''}${autoplay ? '&autoplay=1' : ''}`;

  // ===================== Trình soạn code =====================
  function codeEditor(value, mode, onChange) {
    const ta = h('textarea', { class: 'code-edit', spellcheck: 'false' }, value);
    const wrap = h('div', null, ta);
    if (!window.CodeMirror) {
      ta.addEventListener('input', () => onChange(ta.value));
      ta.addEventListener('keydown', (e) => {
        if (e.key === 'Tab') {
          e.preventDefault();
          const s = ta.selectionStart;
          ta.setRangeText('    ', s, ta.selectionEnd, 'end');
          onChange(ta.value);
        }
      });
      return { el: wrap, focus: () => ta.focus() };
    }
    let cm = null;
    // Khởi tạo sau khi gắn vào DOM để CodeMirror đo kích thước đúng.
    requestAnimationFrame(() => {
      cm = CodeMirror.fromTextArea(ta, {
        mode: mode === 'cpp' ? 'text/x-c++src' : 'javascript',
        theme: isDark() ? 'material-darker' : 'default',
        lineNumbers: true, indentUnit: 4, tabSize: 4, indentWithTabs: false,
        matchBrackets: true, autoCloseBrackets: true, viewportMargin: Infinity,
        extraKeys: { Tab: (c) => c.replaceSelection('    ') },
      });
      cm.on('change', () => onChange(cm.getValue()));
    });
    return { el: wrap, focus: () => cm && cm.focus() };
  }

  // ===================== Trạng thái app =====================
  const S = {
    repo: null,
    pageId: null,
    preview: null, // { ref, label, snapshot } khi xem một commit/nhánh remote (chỉ đọc)
    editing: new Set(),
    tab: 'pages',
    search: '',
    sidebarOpen: false,
  };
  const sims = new Set(); // các iframe mô phỏng đang mở (huỷ khi vẽ lại)

  let saveTimer = null;
  function saveSoon() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(saveNow, 400);
    updateStatus();
  }
  async function saveNow() {
    clearTimeout(saveTimer);
    if (!S.repo) return;
    try { await Store.put(S.repo); } catch (e) { toast('Không lưu được: ' + e.message, true); }
  }
  window.addEventListener('beforeunload', () => S.repo && saveNow());

  const author = () => Settings.get('author') || 'Ẩn danh';
  const snap = () => (S.preview ? S.preview.snapshot : S.repo.working);
  const readOnly = () => !!S.preview;
  const curPage = () => snap().pages.find((p) => p.id === S.pageId) || null;

  async function ensureAuthor() {
    if (Settings.get('author')) return true;
    const name = await promptBox('Bạn tên gì?', 'Tên hiển thị trong commit và khi chia sẻ', '');
    if (!name) return false;
    Settings.set('author', name);
    return true;
  }

  // ===================== Điều hướng =====================
  async function openRepo(id) {
    const repo = await Store.get(id);
    if (!repo) return toast('Không tìm thấy notebook.', true);
    S.repo = repo;
    S.preview = null;
    S.editing.clear();
    S.pageId = repo.working.pages[0] ? repo.working.pages[0].id : null;
    Settings.set('lastRepo', id);
    render();
  }
  function goHome() {
    saveNow();
    S.repo = null;
    S.preview = null;
    Settings.set('lastRepo', null);
    render();
  }

  // ===================== Vẽ =====================
  function render() {
    sims.forEach((s) => s.destroy());
    sims.clear();
    $app.innerHTML = '';
    if (!S.repo) return renderHome();
    $app.append(renderTopbar(), h('div', { class: 'layout' }, renderSidebar(), renderMain()));
    updateStatus();
  }

  // ---------- Trang chủ ----------
  async function renderHome() {
    const repos = (await Store.list()).sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0));
    const cards = h('div', { class: 'cards' });
    repos.forEach((r) => {
      const commits = Object.keys(r.commits).length;
      cards.appendChild(h('div', { class: 'card' },
        h('h3', null, r.working.title || '(không tên)'),
        r.working.description ? h('div', { class: 'small' }, r.working.description) : null,
        h('div', { class: 'meta' },
          `${r.working.pages.length} trang · ${Object.keys(r.branches).length} nhánh · ${commits} commit`,
          h('br'), `Sửa ${timeAgo(r.updatedAt || Date.now())}`),
        h('div', { class: 'row' },
          h('button', { class: 'primary', onclick: () => openRepo(r.id) }, 'Mở'),
          h('button', { onclick: () => duplicateRepo(r) }, 'Nhân bản'),
          h('button', {
            class: 'danger ghost',
            onclick: async () => {
              if (await confirmBox('Xoá notebook?', `Xoá vĩnh viễn "${r.working.title}" khỏi trình duyệt này? (Hãy xuất file trước nếu cần giữ.)`, 'Xoá', true)) {
                await Store.remove(r.id);
                render();
              }
            },
          }, 'Xoá'))
      ));
    });
    $app.appendChild(h('div', { class: 'home' },
      h('div', { class: 'row' },
        h('div', { class: 'grow' },
          h('h1', null, '📚 Sổ tay DSA C++'),
          h('div', { class: 'muted' }, 'Tổng hợp video bài giảng, ghi chú, code C++ và mô phỏng thuật toán — có nhánh và chia sẻ như GitHub.')),
        h('button', { class: 'ghost', title: 'Cài đặt', onclick: settingsDialog }, '⚙ Cài đặt')),
      h('div', { class: 'row', style: { marginTop: '18px' } },
        h('button', { class: 'primary', onclick: newRepoDialog }, '+ Notebook mới'),
        h('button', { onclick: importDialog }, '⬆ Nhập file / link'),
        h('button', { onclick: () => createRepo('Hướng dẫn sử dụng', T.guideSnapshot()) }, '📖 Mở notebook hướng dẫn')),
      repos.length ? cards : h('div', { class: 'empty', style: { marginTop: '20px' } },
        'Chưa có notebook nào. Tạo notebook mới hoặc mở notebook hướng dẫn để xem thử.')
    ));
  }

  async function createRepo(title, snapshot) {
    if (!(await ensureAuthor())) return;
    const repo = V.createRepo({ title, author: author(), snapshot });
    await Store.put(repo);
    openRepo(repo.id);
  }

  async function duplicateRepo(r) {
    const copy = V.clone(r);
    copy.id = V.newId();
    copy.working.title += ' (bản sao)';
    await Store.put(copy);
    render();
  }

  function newRepoDialog() {
    const title = h('input', { placeholder: 'VD: DSA C++ — ghi chú của tôi' });
    const desc = h('textarea', { rows: 2, placeholder: 'Mô tả ngắn (không bắt buộc)' });
    modal({
      title: 'Tạo notebook mới',
      body: h('div', null, h('label', { class: 'field' }, 'Tên notebook', title), h('label', { class: 'field' }, 'Mô tả', desc)),
      actions: [
        { label: 'Huỷ' },
        {
          label: 'Tạo', primary: true,
          onClick: () => {
            const t = title.value.trim() || 'Notebook DSA';
            const s = V.emptySnapshot(t);
            s.description = desc.value.trim();
            createRepo(t, s);
          },
        },
      ],
    });
  }

  // ---------- Thanh trên ----------
  function renderTopbar() {
    const r = S.repo;
    const branchSel = h('select', { class: 'branch', title: 'Nhánh hiện tại', onchange: (e) => switchBranch(e.target.value) });
    Object.keys(r.branches).sort().forEach((b) => branchSel.appendChild(h('option', { value: b, selected: b === r.head }, '⎇ ' + b)));
    branchSel.appendChild(h('option', { value: '__new' }, '+ Tạo nhánh mới…'));
    branchSel.appendChild(h('option', { value: '__manage' }, '⚙ Quản lý nhánh…'));

    const title = h('input', {
      class: 'title', value: r.working.title, readOnly: readOnly(), title: 'Tên notebook',
      oninput: (e) => { r.working.title = e.target.value; saveSoon(); },
    });
    return h('header', { class: 'topbar' },
      h('button', { class: 'ghost menu-btn', onclick: () => { S.sidebarOpen = !S.sidebarOpen; document.querySelector('.sidebar').classList.toggle('open', S.sidebarOpen); } }, '☰'),
      h('button', { class: 'ghost', title: 'Danh sách notebook', onclick: goHome }, '📚'),
      title,
      branchSel,
      h('span', { id: 'status' }),
      h('div', { class: 'grow' }),
      h('button', { class: 'primary', id: 'commit-btn', onclick: commitDialog, title: 'Lưu phiên bản (Ctrl+S)' }, '✔ Commit'),
      h('button', { onclick: historyDialog, title: 'Lịch sử commit' }, '🕘', h('span', { class: 'hide-sm' }, 'Lịch sử')),
      h('button', { onclick: () => mergeDialog(), title: 'Gộp nhánh' }, '⑂', h('span', { class: 'hide-sm' }, 'Merge')),
      h('button', { onclick: shareDialog, title: 'Chia sẻ' }, '🔗', h('span', { class: 'hide-sm' }, 'Chia sẻ')),
      h('button', { onclick: importDialog, title: 'Nhập file/link của người khác' }, '⬆', h('span', { class: 'hide-sm' }, 'Nhập')),
      h('button', { class: 'ghost', onclick: settingsDialog, title: 'Cài đặt' }, '⚙')
    );
  }

  function updateStatus() {
    const el = document.getElementById('status');
    if (!el || !S.repo) return;
    const changes = V.diffSnapshots(V.headSnapshot(S.repo), S.repo.working);
    const n = changes.length;
    el.className = n ? 'dirty' : 'clean';
    el.textContent = n ? `● ${n} thay đổi chưa commit` : '✓ đã commit';
    const btn = document.getElementById('commit-btn');
    if (btn) btn.disabled = !n;
  }

  // ---------- Cột trái ----------
  function renderSidebar() {
    const side = h('aside', { class: 'sidebar' + (S.sidebarOpen ? ' open' : '') });
    side.appendChild(h('div', { class: 'tabs' },
      h('button', { class: S.tab === 'pages' ? 'on' : '', onclick: () => { S.tab = 'pages'; render(); } }, '📄 Trang'),
      h('button', { class: S.tab === 'videos' ? 'on' : '', onclick: () => { S.tab = 'videos'; render(); } }, '🎬 Video')));
    const search = h('input', {
      placeholder: 'Tìm kiếm…', value: S.search, type: 'search',
      oninput: (e) => { S.search = e.target.value; fillList(); },
    });
    side.appendChild(search);
    const list = h('div');
    side.appendChild(list);
    if (S.tab === 'pages' && !readOnly())
      side.appendChild(h('div', { class: 'row', style: { marginTop: '12px' } }, h('button', { class: 'grow', onclick: addPage }, '+ Trang mới')));
    fillList();
    return side;

    function fillList() {
      list.innerHTML = '';
      const q = S.search.trim().toLowerCase();
      const pages = snap().pages.filter((p) => !q || JSON.stringify(p).toLowerCase().includes(q));
      if (S.tab === 'pages') {
        const groups = new Map();
        pages.forEach((p) => {
          const c = p.chapter || 'Chưa phân chương';
          if (!groups.has(c)) groups.set(c, []);
          groups.get(c).push(p);
        });
        groups.forEach((ps, c) => list.appendChild(h('div', { class: 'chapter' },
          h('div', { class: 'chapter-name' }, c),
          ps.map((p) => h('button', { class: 'page-link' + (p.id === S.pageId ? ' on' : ''), onclick: () => selectPage(p.id) },
            p.title || '(không tên)', h('span', { class: 'cnt' }, p.blocks.length))))));
        if (!pages.length) list.appendChild(h('p', { class: 'muted small' }, q ? 'Không có kết quả.' : 'Chưa có trang nào.'));
      } else {
        let count = 0;
        pages.forEach((p) => p.blocks.filter((b) => b.type === 'video').forEach((b) => {
          count++;
          const v = parseVideo(b.url);
          list.appendChild(h('button', { class: 'video-item', onclick: () => selectPage(p.id, b.id) },
            v && v.kind === 'yt' ? h('img', { src: `https://i.ytimg.com/vi/${encodeURIComponent(v.id)}/mqdefault.jpg`, alt: '', loading: 'lazy' }) : h('div', { class: 'thumb' }, '🎬'),
            h('div', null, h('div', { class: 't' }, b.title || b.url || '(chưa có link)'), h('div', { class: 'p' }, p.title))));
        }));
        if (!count) list.appendChild(h('p', { class: 'muted small' }, 'Chưa có video nào. Thêm khối 🎬 Video vào trang để tổng hợp ở đây.'));
      }
    }
  }

  function selectPage(id, blockId) {
    S.pageId = id;
    S.sidebarOpen = false;
    render();
    if (blockId) setTimeout(() => {
      const el = document.querySelector(`[data-block="${blockId}"]`);
      if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }, 50);
    else window.scrollTo(0, 0);
  }

  function addPage() {
    const cur = curPage();
    const p = { id: V.newId(12), title: 'Trang mới', chapter: cur ? cur.chapter : '', blocks: [] };
    const pages = S.repo.working.pages;
    const idx = cur ? pages.indexOf(cur) + 1 : pages.length;
    pages.splice(idx, 0, p);
    S.pageId = p.id;
    saveSoon();
    render();
    const t = document.querySelector('.page-title');
    if (t) { t.focus(); t.select(); }
  }

  // ---------- Nội dung chính ----------
  function renderMain() {
    const main = h('main', { class: 'main' });
    const inner = h('div', { class: 'main-inner' });
    main.appendChild(inner);
    if (S.preview)
      inner.appendChild(h('div', { class: 'banner' },
        h('span', { class: 'grow' }, '👁 Đang xem ', h('b', null, S.preview.label), ' (chỉ đọc)'),
        S.preview.onMerge ? h('button', { onclick: S.preview.onMerge }, '⑂ Merge vào nhánh hiện tại') : null,
        h('button', { onclick: () => branchFromRef(S.preview.ref) }, '⎇ Tạo nhánh từ đây'),
        h('button', { class: 'primary', onclick: () => { S.preview = null; render(); } }, '← Quay lại nhánh ' + S.repo.head)));

    const page = curPage();
    if (!page) {
      if (!snap().pages.length)
        inner.appendChild(h('div', { class: 'empty' },
          h('h2', null, snap().title || 'Notebook'),
          h('p', null, snap().description || 'Notebook trống.'),
          readOnly() ? null : h('button', { class: 'primary', onclick: addPage }, '+ Tạo trang đầu tiên')));
      else {
        S.pageId = snap().pages[0].id;
        return renderMain();
      }
      return main;
    }

    const pages = S.repo.working.pages;
    const ro = readOnly();
    const chapters = [...new Set(snap().pages.map((p) => p.chapter).filter(Boolean))];
    inner.appendChild(h('div', { class: 'page-head' },
      h('div', { class: 'grow' },
        h('input', { class: 'page-title', value: page.title, readOnly: ro, placeholder: 'Tên trang', oninput: (e) => { page.title = e.target.value; saveSoon(); }, onchange: () => render() }),
        h('div', { class: 'row', style: { marginTop: '4px' } },
          h('span', { class: 'muted small' }, 'Chương:'),
          h('input', { class: 'chapter-input', value: page.chapter || '', readOnly: ro, list: 'chapters', placeholder: 'VD: Sắp xếp, Đồ thị…', oninput: (e) => { page.chapter = e.target.value; saveSoon(); }, onchange: () => render() }),
          h('datalist', { id: 'chapters' }, chapters.map((c) => h('option', { value: c }))))),
      ro ? null : h('div', { class: 'row' },
        h('button', { class: 'sm', title: 'Chuyển trang lên', onclick: () => movePage(-1) }, '↑'),
        h('button', { class: 'sm', title: 'Chuyển trang xuống', onclick: () => movePage(1) }, '↓'),
        h('button', {
          class: 'sm danger', title: 'Xoá trang',
          onclick: async () => {
            if (!(await confirmBox('Xoá trang?', `Xoá trang "${page.title}"? (Có thể khôi phục từ lịch sử nếu đã commit.)`, 'Xoá', true))) return;
            const i = pages.indexOf(page);
            pages.splice(i, 1);
            S.pageId = pages[Math.max(0, i - 1)] ? pages[Math.max(0, i - 1)].id : null;
            saveSoon();
            render();
          },
        }, '🗑'))));

    if (!page.blocks.length && !ro) inner.appendChild(h('p', { class: 'muted' }, 'Trang trống — thêm khối đầu tiên:'));
    page.blocks.forEach((b, i) => {
      if (!ro && i === 0) inner.appendChild(adder(page, 0));
      inner.appendChild(renderBlock(page, b));
      if (!ro) inner.appendChild(adder(page, i + 1, i === page.blocks.length - 1));
    });
    if (!page.blocks.length && !ro) inner.appendChild(adder(page, 0, true));
    return main;

    function movePage(d) {
      const i = pages.indexOf(page);
      const j = i + d;
      if (j < 0 || j >= pages.length) return;
      [pages[i], pages[j]] = [pages[j], pages[i]];
      saveSoon();
      render();
    }
  }

  function adder(page, index, always) {
    const add = (type) => {
      const b = { id: V.newId(12), type };
      if (type === 'markdown') b.text = '';
      if (type === 'video') Object.assign(b, { title: '', url: '', timestamps: '' });
      if (type === 'code') Object.assign(b, { title: '', code: '#include <bits/stdc++.h>\nusing namespace std;\n\nint main() {\n    \n}\n', stdin: '' });
      if (type === 'sim') {
        const t = T.SIM_TEMPLATES[0];
        Object.assign(b, { title: '', code: t.code, input: t.input });
      }
      page.blocks.splice(index, 0, b);
      S.editing.add(b.id);
      saveSoon();
      render();
      const el = document.querySelector(`[data-block="${b.id}"]`);
      if (el) {
        el.scrollIntoView({ block: 'center' });
        const f = el.querySelector('textarea, input');
        if (f) f.focus();
      }
    };
    return h('div', { class: 'adder' + (always ? ' always' : '') },
      h('button', { onclick: () => add('markdown') }, '📝 Ghi chú'),
      h('button', { onclick: () => add('video') }, '🎬 Video'),
      h('button', { onclick: () => add('code') }, '💻 Code C++'),
      h('button', { onclick: () => add('sim') }, '▶️ Mô phỏng'));
  }

  // ---------- Khối ----------
  const KIND = { markdown: '📝 Ghi chú', video: '🎬 Video', code: '💻 Code C++', sim: '▶️ Mô phỏng' };

  function renderBlock(page, b) {
    const ro = readOnly();
    const editing = !ro && S.editing.has(b.id);
    const el = h('section', { class: 'block' + (editing ? ' editing' : ''), 'data-block': b.id });
    const toggle = () => {
      if (S.editing.has(b.id)) S.editing.delete(b.id);
      else S.editing.add(b.id);
      render();
      const again = document.querySelector(`[data-block="${b.id}"]`);
      if (again) again.scrollIntoView({ block: 'nearest' });
    };
    if (!ro) {
      const blocks = page.blocks;
      const move = (d) => {
        const i = blocks.indexOf(b);
        const j = i + d;
        if (j < 0 || j >= blocks.length) return;
        [blocks[i], blocks[j]] = [blocks[j], blocks[i]];
        saveSoon();
        render();
      };
      el.appendChild(h('div', { class: 'block-tools' },
        h('button', { onclick: toggle, title: editing ? 'Xong' : 'Sửa' }, editing ? '✔ Xong' : '✏️ Sửa'),
        h('button', { onclick: () => move(-1), title: 'Lên' }, '↑'),
        h('button', { onclick: () => move(1), title: 'Xuống' }, '↓'),
        h('button', {
          onclick: () => {
            const copy = { ...V.clone(b), id: V.newId(12) };
            blocks.splice(blocks.indexOf(b) + 1, 0, copy);
            saveSoon();
            render();
          }, title: 'Nhân bản',
        }, '⧉'),
        h('button', {
          class: 'danger', title: 'Xoá khối',
          onclick: async () => {
            const empty = !(b.text || b.url || b.title);
            if (!empty && !(await confirmBox('Xoá khối?', 'Xoá khối này khỏi trang?', 'Xoá', true))) return;
            blocks.splice(blocks.indexOf(b), 1);
            S.editing.delete(b.id);
            saveSoon();
            render();
          },
        }, '🗑')));
    }
    const change = (field, value) => { b[field] = value; saveSoon(); };
    const R = { markdown: blockMarkdown, video: blockVideo, code: blockCode, sim: blockSim }[b.type];
    if (R) R(el, b, editing, change, toggle);
    else el.appendChild(h('div', { class: 'muted' }, `Loại khối không hỗ trợ: ${b.type}`));
    return el;
  }

  function blockMarkdown(el, b, editing, change, toggle) {
    if (editing) {
      const ta = h('textarea', {
        class: 'md-edit', placeholder: 'Ghi chú Markdown: # tiêu đề, **đậm**, `code`, - danh sách, ```cpp khối code```…',
        oninput: (e) => { change('text', e.target.value); grow(e.target); },
      }, b.text || '');
      const grow = (t) => { t.style.height = 'auto'; t.style.height = Math.max(160, t.scrollHeight + 4) + 'px'; };
      requestAnimationFrame(() => grow(ta));
      el.append(ta, h('div', { class: 'muted small' }, 'Hỗ trợ Markdown. Bấm "✔ Xong" để xem kết quả.'));
    } else {
      const md = b.text ? renderMarkdown(b.text) : h('div', { class: 'muted' }, readOnly() ? '(trống)' : '(ghi chú trống — nhấp đúp để viết)');
      if (!readOnly()) md.addEventListener('dblclick', toggle);
      el.appendChild(md);
    }
  }

  function blockVideo(el, b, editing, change) {
    el.appendChild(h('div', { class: 'block-kind' }, KIND.video));
    if (editing) {
      el.append(
        h('label', { class: 'field' }, 'Link video (YouTube, playlist, hoặc file .mp4)', h('input', { value: b.url || '', placeholder: 'https://www.youtube.com/watch?v=…', oninput: (e) => change('url', e.target.value.trim()) })),
        h('label', { class: 'field' }, 'Tiêu đề / nguồn', h('input', { value: b.title || '', placeholder: 'VD: Bài 5 — Quick sort (kênh …)', oninput: (e) => change('title', e.target.value) })),
        h('label', { class: 'field' }, 'Mốc thời gian (mỗi dòng: mm:ss nội dung)', h('textarea', { class: 'mono', rows: 4, placeholder: '00:00 Giới thiệu\n03:15 Ý tưởng\n12:40 Code C++', oninput: (e) => change('timestamps', e.target.value) }, b.timestamps || '')));
      return;
    }
    if (b.title) el.appendChild(h('h3', { class: 'btitle' }, b.title));
    const v = parseVideo(b.url);
    let player = null;
    if (!v) el.appendChild(h('div', { class: 'video-missing' }, b.url ? 'Link video không hợp lệ.' : 'Chưa có link video — bấm ✏️ Sửa để dán link.'));
    else if (v.kind === 'yt' || v.kind === 'yt-list') {
      player = h('iframe', {
        src: v.kind === 'yt' ? ytEmbed(v.id, v.start) : `https://www.youtube-nocookie.com/embed/videoseries?list=${encodeURIComponent(v.list)}`,
        allow: 'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture', allowfullscreen: true, loading: 'lazy', title: b.title || 'Video',
      });
      el.appendChild(h('div', { class: 'video-wrap' }, player));
    } else if (v.kind === 'file') {
      player = h('video', { src: v.src, controls: true, preload: 'metadata' });
      el.appendChild(h('div', { class: 'video-wrap' }, player));
    } else el.appendChild(h('a', { class: 'btn', href: v.href, target: '_blank', rel: 'noopener noreferrer' }, '▶ Mở video ở trang gốc'));
    const ts = parseTimestamps(b.timestamps);
    if (ts.length)
      el.appendChild(h('div', { class: 'ts-list' }, ts.map((t) => h('button', {
        class: 'ts',
        onclick: () => {
          if (v && v.kind === 'yt') player.src = ytEmbed(v.id, t.sec, true);
          else if (player && player.tagName === 'VIDEO') { player.currentTime = t.sec; player.play(); }
        },
      }, h('span', { class: 'time' }, t.time), h('span', null, t.label)))));
  }

  function blockCode(el, b, editing, change) {
    el.appendChild(h('div', { class: 'block-kind' }, KIND.code));
    if (editing) {
      el.appendChild(h('label', { class: 'field' }, 'Tên file / tiêu đề', h('input', { value: b.title || '', placeholder: 'VD: quick_sort.cpp', oninput: (e) => change('title', e.target.value) })));
      el.appendChild(codeEditor(b.code || '', 'cpp', (v) => change('code', v)).el);
    } else {
      if (b.title) el.appendChild(h('h3', { class: 'btitle mono' }, b.title));
      const code = h('code', { class: 'language-cpp' }, b.code || '');
      if (window.hljs) try { hljs.highlightElement(code); } catch (_) { /* bỏ qua */ }
      el.appendChild(h('pre', { class: 'code-view' }, code));
    }
    const stdin = h('textarea', { class: 'mono', rows: 3, readOnly: readOnly(), placeholder: 'Dữ liệu nhập cho chương trình', oninput: (e) => change('stdin', e.target.value) }, b.stdin || '');
    const out = h('div');
    const runBtn = h('button', { class: 'primary sm', onclick: run }, '▶ Chạy');
    el.append(
      h('details', { class: 'stdin', open: !!b.stdin }, h('summary', null, 'stdin (dữ liệu vào)'), stdin),
      h('div', { class: 'row', style: { marginTop: '8px' } },
        runBtn,
        h('button', { class: 'sm', onclick: () => navigator.clipboard.writeText(b.code || '').then(() => toast('Đã sao chép code')) }, '📋 Sao chép'),
        h('button', { class: 'sm', onclick: () => Share.download((b.title || 'main').replace(/[^\w.-]+/g, '_').replace(/(\.cpp)?$/, '.cpp'), b.code || '') }, '⬇ Tải .cpp'),
        h('span', { class: 'muted small' }, `Biên dịch online: ${Settings.get('compiler')} ${Settings.get('cppFlags')}`)),
      out);

    async function run() {
      runBtn.disabled = true;
      runBtn.textContent = '⏳ Đang chạy…';
      out.innerHTML = '';
      try {
        const r = await Cpp.run(b.code || '', stdin.value);
        if (r.phase === 'compile') out.appendChild(outBox('Lỗi biên dịch', r.output, 'err'));
        else {
          if (r.warnings) out.appendChild(outBox('Cảnh báo', r.warnings, ''));
          out.appendChild(outBox(r.timedOut ? 'Quá thời gian' : `Kết quả (mã thoát ${r.code})`, r.stdout || '(không có output)', r.ok ? 'ok' : 'err'));
          if (r.stderr) out.appendChild(outBox('stderr', r.stderr, 'err'));
        }
      } catch (e) {
        out.appendChild(outBox('Không chạy được', `${e.message}\nKiểm tra kết nối mạng (cần truy cập godbolt.org).`, 'err'));
      }
      runBtn.disabled = false;
      runBtn.textContent = '▶ Chạy';
    }
  }
  const outBox = (title, text, cls) => h('div', { class: 'run-out ' + cls }, h('div', { class: 'hd' }, title), h('pre', null, text));

  function blockSim(el, b, editing, change) {
    el.appendChild(h('div', { class: 'block-kind' }, KIND.sim));
    const holder = h('div');
    let player = null;
    const run = () => {
      if (!player) {
        player = window.SIM.mount(holder);
        sims.add(player);
      }
      player.run(b.code || '', b.input || '');
    };
    const input = h('textarea', {
      class: 'sim-input', rows: Math.min(8, Math.max(1, (b.input || '').split('\n').length)), readOnly: readOnly(),
      placeholder: 'Dữ liệu vào (biến INPUT / readNumbers())',
      oninput: (e) => change('input', e.target.value),
    }, b.input || '');

    if (editing) {
      const tplSel = h('select', { style: { width: 'auto' } },
        h('option', { value: '' }, '— Chèn mẫu có sẵn —'),
        T.SIM_TEMPLATES.map((t) => h('option', { value: t.id }, t.name)));
      tplSel.onchange = async () => {
        const t = T.SIM_TEMPLATES.find((x) => x.id === tplSel.value);
        if (!t) return;
        if ((b.code || '').trim() && b.code !== T.SIM_TEMPLATES[0].code && !(await confirmBox('Thay code?', 'Code mô phỏng hiện tại sẽ bị thay bằng mẫu.', 'Thay'))) {
          tplSel.value = '';
          return;
        }
        change('code', t.code);
        change('input', t.input);
        if (!b.title) change('title', t.name);
        render();
      };
      el.append(
        h('label', { class: 'field' }, 'Tiêu đề', h('input', { value: b.title || '', placeholder: 'VD: Mô phỏng Quick sort', oninput: (e) => change('title', e.target.value) })),
        h('div', { class: 'row', style: { margin: '6px 0' } }, tplSel, h('button', { class: 'sm', onclick: apiDialog }, '📖 API'), h('span', { class: 'muted small' }, 'Viết bằng JavaScript — cú pháp vòng lặp/điều kiện giống C++.')),
        codeEditor(b.code || '', 'js', (v) => change('code', v)).el,
        h('label', { class: 'field' }, 'Dữ liệu vào', input),
        h('div', { class: 'row', style: { margin: '8px 0' } }, h('button', { class: 'primary sm', onclick: run }, '▶ Chạy thử')),
        holder);
      requestAnimationFrame(run);
      return;
    }
    if (b.title) el.appendChild(h('h3', { class: 'btitle' }, b.title));
    el.append(holder, h('div', { class: 'row', style: { marginTop: '8px', alignItems: 'flex-start' } },
      h('div', { class: 'grow' }, input), h('button', { class: 'sm', onclick: run, title: 'Chạy lại với dữ liệu vào mới' }, '↻ Chạy')));
    requestAnimationFrame(run);
  }

  function apiDialog() {
    modal({ title: 'API mô phỏng', wide: true, body: renderMarkdown(T.API_DOC), actions: [{ label: 'Đóng', primary: true }] });
  }

  // ===================== Commit =====================
  function renderChanges(changes) {
    const box = h('div', { class: 'changes' });
    if (!changes.length) box.appendChild(h('div', { class: 'muted' }, 'Không có thay đổi.'));
    const tag = (c, t) => h('span', { class: 'tag ' + c }, t);
    changes.forEach((c) => {
      if (c.kind === 'meta') box.appendChild(h('div', { class: 'change' }, tag('m', '~'), ` Thông tin notebook: ${c.field === 'title' ? 'tên' : 'mô tả'} → "${c.after || ''}"`));
      else if (c.kind === 'reorder-pages') box.appendChild(h('div', { class: 'change' }, tag('m', '↕'), ' Đổi thứ tự trang'));
      else if (c.kind === 'page-added') box.appendChild(h('div', { class: 'change' }, tag('a', '+'), ` Thêm trang "${c.page.title}" (${c.page.blocks.length} khối)`));
      else if (c.kind === 'page-removed') box.appendChild(h('div', { class: 'change' }, tag('d', '−'), ` Xoá trang "${c.page.title}"`));
      else if (c.kind === 'page-changed') {
        const d = h('details', { class: 'change' }, h('summary', null, tag('m', '~'), ` Sửa trang "${c.after.title}"`));
        c.fields.forEach((f) => d.appendChild(h('div', { class: 'small' }, `${f === 'title' ? 'Tên' : 'Chương'}: "${c.before[f] || ''}" → "${c.after[f] || ''}"`)));
        c.blocks.forEach((x) => {
          if (x.kind === 'block-added') d.appendChild(h('div', { class: 'small' }, tag('a', '+'), ' ' + V.blockName(x.block)));
          else if (x.kind === 'block-removed') d.appendChild(h('div', { class: 'small' }, tag('d', '−'), ' ' + V.blockName(x.block)));
          else if (x.kind === 'reorder-blocks') d.appendChild(h('div', { class: 'small' }, tag('m', '↕'), ' Đổi thứ tự khối'));
          else {
            d.appendChild(h('div', { class: 'small' }, tag('m', '~'), ' ' + V.blockName(x.after)));
            Object.keys({ ...x.before, ...x.after }).forEach((k) => {
              if (k === 'id' || V.same(x.before[k], x.after[k])) return;
              d.appendChild(h('div', { class: 'small muted' }, k));
              d.appendChild(lineDiff(String(x.before[k] ?? ''), String(x.after[k] ?? '')));
            });
          }
        });
        box.appendChild(d);
      }
    });
    return box;
  }

  function lineDiff(a, b) {
    const ops = V.diffLines(a, b);
    const box = h('div', { class: 'diff' });
    // Rút gọn các đoạn không đổi dài, chỉ giữ 2 dòng ngữ cảnh quanh chỗ sửa.
    let run = [];
    const add = (t) => box.appendChild(h('div', null, '  ' + t));
    const flush = (isEnd) => {
      const head = box.childNodes.length ? 2 : 0;
      const tail = isEnd ? 0 : 2;
      if (run.length > head + tail + 1) {
        run.slice(0, head).forEach(add);
        box.appendChild(h('div', { class: 'skip' }, `… ${run.length - head - tail} dòng không đổi …`));
        run.slice(run.length - tail).forEach(add);
      } else run.forEach(add);
      run = [];
    };
    ops.forEach((o) => {
      if (o.op === ' ') return run.push(o.text);
      flush(false);
      box.appendChild(h('div', { class: o.op === '+' ? 'add' : 'del' }, o.op + ' ' + o.text));
    });
    flush(true);
    return box;
  }

  async function commitDialog() {
    if (readOnly()) return toast('Đang ở chế độ xem. Quay lại nhánh để commit.', true);
    const changes = V.diffSnapshots(V.headSnapshot(S.repo), S.repo.working);
    if (!changes.length) return toast('Không có thay đổi nào để commit.');
    if (!(await ensureAuthor())) return;
    const msg = h('input', { placeholder: 'VD: Thêm ghi chú Quick sort + mô phỏng' });
    const doCommit = () => {
      V.commit(S.repo, { message: msg.value, author: author() });
      saveNow();
      render();
      toast(`Đã commit lên nhánh ${S.repo.head}`);
    };
    const m = modal({
      title: `Commit lên nhánh "${S.repo.head}"`,
      body: h('div', null,
        h('label', { class: 'field' }, 'Mô tả thay đổi', msg),
        h('div', { class: 'muted small', style: { margin: '10px 0 6px' } }, `${changes.length} thay đổi:`),
        renderChanges(changes)),
      actions: [
        { label: 'Bỏ hết thay đổi', danger: true, onClick: () => discardChanges() },
        { label: 'Huỷ' },
        { label: '✔ Commit', primary: true, onClick: doCommit },
      ],
    });
    msg.addEventListener('keydown', (e) => { if (e.key === 'Enter') { doCommit(); m.close(); } });
  }

  async function discardChanges() {
    if (!(await confirmBox('Bỏ thay đổi?', 'Mọi thay đổi chưa commit sẽ mất. Tiếp tục?', 'Bỏ thay đổi', true))) return false;
    S.repo.working = V.clone(V.headSnapshot(S.repo));
    S.editing.clear();
    saveNow();
    render();
  }

  // ===================== Nhánh =====================
  async function switchBranch(name) {
    if (name === '__new') return newBranchDialog();
    if (name === '__manage') return branchesDialog();
    if (name === S.repo.head) return;
    if (V.isDirty(S.repo)) {
      const ok = await new Promise((resolve) => {
        modal({
          title: 'Còn thay đổi chưa commit',
          body: h('p', null, `Bạn có thay đổi chưa commit trên nhánh "${S.repo.head}". Chuyển sang "${name}" sẽ làm mất chúng.`),
          actions: [
            { label: 'Huỷ', onClick: () => resolve(false) },
            { label: 'Bỏ thay đổi & chuyển', danger: true, onClick: () => resolve(true) },
            { label: 'Commit trước', primary: true, onClick: () => { resolve(false); commitDialog(); } },
          ],
          onClose: () => resolve(false),
        });
      });
      if (!ok) return render();
    }
    V.checkout(S.repo, name, { force: true });
    afterSwitch();
    toast(`Đã chuyển sang nhánh ${name}`);
  }

  function afterSwitch() {
    S.preview = null;
    S.editing.clear();
    if (!S.repo.working.pages.some((p) => p.id === S.pageId)) S.pageId = S.repo.working.pages[0] ? S.repo.working.pages[0].id : null;
    saveNow();
    render();
  }

  function newBranchDialog(fromRef) {
    const name = h('input', { placeholder: 'VD: ghi-chu-do-thi, ban-cua-an' });
    const dirty = V.isDirty(S.repo) && !fromRef;
    const create = () => {
      const n = name.value.trim();
      V.createBranch(S.repo, n, fromRef || S.repo.head);
      if (fromRef) V.checkout(S.repo, n, { force: true });
      else S.repo.head = n; // mang theo thay đổi chưa commit, giống `git checkout -b`
      afterSwitch();
      toast(`Đã tạo và chuyển sang nhánh ${n}`);
    };
    const m = modal({
      title: 'Tạo nhánh mới',
      body: h('div', null,
        h('label', { class: 'field' }, 'Tên nhánh', name),
        h('p', { class: 'muted small' }, fromRef ? `Nhánh mới bắt đầu từ ${fromRef.slice(0, 20)}.` : `Nhánh mới bắt đầu từ "${S.repo.head}".${dirty ? ' Thay đổi chưa commit sẽ được mang sang nhánh mới.' : ''}`)),
      actions: [{ label: 'Huỷ', onClick: () => render() }, { label: 'Tạo nhánh', primary: true, onClick: create }],
      onClose: () => render(),
    });
    name.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') { try { create(); m.close(); } catch (err) { toast(err.message, true); } }
    });
  }

  function branchFromRef(ref) {
    newBranchDialog(V.resolveRef(S.repo, ref));
  }

  function countAheadBehind(a, b) {
    const A = V.ancestors(S.repo, a);
    const B = V.ancestors(S.repo, b);
    let ahead = 0;
    let behind = 0;
    A.forEach((x) => !B.has(x) && ahead++);
    B.forEach((x) => !A.has(x) && behind++);
    return { ahead, behind };
  }

  function branchesDialog() {
    render();
    const body = h('div');
    const m = modal({ title: 'Quản lý nhánh', wide: true, body, actions: [{ label: '+ Nhánh mới', onClick: () => newBranchDialog() }, { label: 'Đóng', primary: true }] });
    fill();
    function fill() {
      body.innerHTML = '';
      const r = S.repo;
      const headId = V.headCommitId(r);
      body.appendChild(h('h3', null, 'Nhánh của bạn'));
      Object.entries(r.branches).sort().forEach(([name, id]) => {
        const c = r.commits[id];
        const ab = countAheadBehind(id, headId);
        body.appendChild(h('div', { class: 'change row' },
          h('span', { class: 'badge branch' }, '⎇ ' + name),
          name === r.head ? h('span', { class: 'badge' }, 'đang đứng') : h('span', { class: 'muted small' }, `${ab.ahead} commit trước · ${ab.behind} sau "${r.head}"`),
          h('span', { class: 'grow small muted' }, `${c.message} · ${c.author} · ${timeAgo(c.time)}`),
          name !== r.head ? h('button', { class: 'sm', onclick: () => { m.close(); switchBranch(name); } }, 'Chuyển') : null,
          name !== r.head ? h('button', { class: 'sm', onclick: () => { m.close(); mergeDialog(name); } }, '⑂ Merge vào ' + r.head) : null,
          h('button', {
            class: 'sm', onclick: async () => {
              const to = await promptBox('Đổi tên nhánh', 'Tên mới', name);
              if (!to || to === name) return;
              try { V.renameBranch(r, name, to); saveNow(); fill(); render(); } catch (e) { toast(e.message, true); }
            },
          }, 'Đổi tên'),
          name !== r.head ? h('button', {
            class: 'sm danger', onclick: async () => {
              const merged = V.isAncestor(r, id, headId);
              if (!(await confirmBox('Xoá nhánh?', `Xoá nhánh "${name}"?${merged ? '' : ' Nhánh này có commit CHƯA được merge — chúng sẽ chỉ còn trong lịch sử nếu nhánh khác chứa chúng.'}`, 'Xoá', true))) return;
              V.deleteBranch(r, name);
              saveNow();
              fill();
            },
          }, 'Xoá') : null));
      });
      const remotes = Object.entries(r.remotes);
      body.appendChild(h('h3', null, 'Nhánh từ người khác (đã nhập)'));
      if (!remotes.length) body.appendChild(h('p', { class: 'muted small' }, 'Chưa có. Dùng "⬆ Nhập" để lấy notebook người khác chia sẻ và gộp vào đây.'));
      remotes.sort().forEach(([name, id]) => {
        const c = r.commits[id];
        const ab = countAheadBehind(id, headId);
        body.appendChild(h('div', { class: 'change row' },
          h('span', { class: 'badge remote' }, '☁ ' + name),
          h('span', { class: 'muted small' }, `${ab.ahead} commit mới so với "${r.head}"`),
          h('span', { class: 'grow small muted' }, `${c.message} · ${c.author} · ${timeAgo(c.time)}`),
          h('button', { class: 'sm', onclick: () => { m.close(); previewRef(name); } }, '👁 Xem'),
          h('button', { class: 'sm', onclick: () => { m.close(); mergeDialog(name); } }, '⑂ Merge vào ' + r.head),
          h('button', { class: 'sm', onclick: () => { m.close(); branchFromRef(name); } }, 'Tạo nhánh'),
          h('button', { class: 'sm danger', onclick: () => { delete r.remotes[name]; saveNow(); fill(); } }, 'Xoá')));
      });
    }
  }

  function previewRef(ref, label) {
    const id = V.resolveRef(S.repo, ref);
    const c = S.repo.commits[id];
    const isRemote = !!S.repo.remotes[ref];
    S.preview = {
      ref: id,
      label: label || (isRemote ? `nhánh ${ref}` : `commit ${id.slice(0, 7)} — ${c.message}`),
      snapshot: c.snapshot,
      onMerge: isRemote || S.repo.branches[ref] ? () => { S.preview = null; render(); mergeDialog(ref); } : null,
    };
    S.editing.clear();
    if (!c.snapshot.pages.some((p) => p.id === S.pageId)) S.pageId = c.snapshot.pages[0] ? c.snapshot.pages[0].id : null;
    render();
  }

  // ===================== Lịch sử =====================
  function historyDialog() {
    const r = S.repo;
    const commits = V.log(r);
    const rows = V.graphLayout(commits);
    const labels = {};
    Object.entries(r.branches).forEach(([n, id]) => (labels[id] = (labels[id] || []).concat({ n, remote: false })));
    Object.entries(r.remotes).forEach(([n, id]) => (labels[id] = (labels[id] || []).concat({ n, remote: true })));
    const lanesMax = Math.max(1, ...rows.map((x) => Math.max(x.before.length, x.after.length, x.col + 1)));
    const LW = 16;
    const RH = 44;
    const palette = ['#2563eb', '#16a34a', '#d97706', '#db2777', '#7c3aed', '#0891b2', '#dc2626'];
    const lx = (k) => 10 + k * LW;

    const list = h('div', { class: 'hist-list' });
    const detail = h('div', { class: 'hist-detail' }, h('p', { class: 'muted' }, 'Chọn một commit để xem chi tiết.'));
    rows.forEach((row) => {
      const c = row.commit;
      let svg = `<svg width="${lanesMax * LW + 8}" height="${RH}">`;
      row.before.forEach((id, k) => {
        if (!id) return;
        const col = palette[k % palette.length];
        if (id === c.id) svg += `<line x1="${lx(k)}" y1="0" x2="${lx(row.col)}" y2="${RH / 2}" stroke="${col}" stroke-width="2"/>`;
        else {
          const to = row.after.indexOf(id);
          if (to !== -1) svg += `<line x1="${lx(k)}" y1="0" x2="${lx(to)}" y2="${RH}" stroke="${col}" stroke-width="2"/>`;
        }
      });
      c.parents.forEach((p) => {
        const to = row.after.indexOf(p);
        if (to !== -1) svg += `<line x1="${lx(row.col)}" y1="${RH / 2}" x2="${lx(to)}" y2="${RH}" stroke="${palette[to % palette.length]}" stroke-width="2"/>`;
      });
      svg += `<circle cx="${lx(row.col)}" cy="${RH / 2}" r="5" fill="${palette[row.col % palette.length]}" stroke="var(--panel)" stroke-width="2"/></svg>`;
      const el = h('div', { class: 'hist-row', onclick: () => select(c, el) },
        h('span', { html: svg }),
        h('div', { class: 'info' },
          h('div', { class: 'msg' }, (labels[c.id] || []).map((l) => h('span', { class: 'badge ' + (l.remote ? 'remote' : 'branch'), style: { marginRight: '4px' } }, (l.remote ? '☁ ' : '⎇ ') + l.n)), c.message),
          h('div', { class: 'sub' }, `${c.id.slice(0, 7)} · ${c.author} · ${timeAgo(c.time)}`)));
      list.appendChild(el);
    });

    const m = modal({
      title: `Lịch sử — ${commits.length} commit`, wide: true,
      body: h('div', { class: 'history' }, list, detail),
      actions: [{ label: 'Đóng', primary: true }],
    });

    function select(c, el) {
      list.querySelectorAll('.on').forEach((x) => x.classList.remove('on'));
      el.classList.add('on');
      const parent = c.parents[0] ? r.commits[c.parents[0]].snapshot : null;
      detail.innerHTML = '';
      detail.append(
        h('h3', { style: { marginTop: 0 } }, c.message),
        h('div', { class: 'small muted' }, `${c.author} · ${fullTime(c.time)}`),
        h('div', { class: 'small muted mono' }, `commit ${c.id}`, c.parents.length > 1 ? ` · merge của ${c.parents.map((p) => p.slice(0, 7)).join(' + ')}` : ''),
        h('div', { class: 'row', style: { margin: '10px 0' } },
          h('button', { class: 'sm', onclick: () => { m.close(); previewRef(c.id); } }, '👁 Xem bản này'),
          h('button', { class: 'sm', onclick: () => { m.close(); branchFromRef(c.id); } }, '⎇ Tạo nhánh từ đây'),
          h('button', {
            class: 'sm', onclick: async () => {
              if (!(await confirmBox('Khôi phục?', `Đưa nội dung về bản "${c.message}"? Thay đổi sẽ hiện như chưa commit để bạn xem lại rồi commit.`, 'Khôi phục'))) return;
              S.repo.working = V.clone(c.snapshot);
              m.close();
              afterSwitch();
            },
          }, '↺ Khôi phục bản này'),
          h('button', {
            class: 'sm', onclick: () => {
              detail.querySelector('.changes').replaceWith(renderChanges(V.diffSnapshots(c.snapshot, S.repo.working)));
              detail.querySelector('.cmp').textContent = 'So với bản đang làm việc hiện tại:';
            },
          }, '⇄ So với hiện tại')),
        h('div', { class: 'small muted cmp', style: { marginBottom: '6px' } }, parent ? 'Thay đổi so với commit cha:' : 'Commit đầu tiên:'),
        renderChanges(V.diffSnapshots(parent, c.snapshot)));
    }
  }

  // ===================== Merge =====================
  function mergeDialog(preset) {
    if (readOnly()) { S.preview = null; render(); }
    const r = S.repo;
    if (V.isDirty(r)) return toast('Hãy commit hoặc bỏ thay đổi trước khi merge.', true);
    const sources = [...Object.keys(r.branches).filter((b) => b !== r.head), ...Object.keys(r.remotes)];
    if (!sources.length) return toast('Chưa có nhánh nào khác để merge. Tạo nhánh mới hoặc nhập notebook người khác.', true);
    const sel = h('select', null, sources.map((s) => h('option', { value: s, selected: s === preset }, (r.remotes[s] ? '☁ ' : '⎇ ') + s)));
    const info = h('div', { class: 'small muted', style: { marginTop: '8px' } });
    const updateInfo = () => {
      const id = V.resolveRef(r, sel.value);
      const ab = countAheadBehind(id, V.headCommitId(r));
      info.textContent = `"${sel.value}" có ${ab.ahead} commit mà "${r.head}" chưa có.`;
    };
    sel.onchange = updateInfo;
    updateInfo();
    modal({
      title: `Merge vào nhánh "${r.head}"`,
      body: h('div', null, h('label', { class: 'field' }, 'Lấy thay đổi từ', sel), info),
      actions: [{ label: 'Huỷ' }, { label: 'Tiếp tục', primary: true, onClick: () => doMerge(sel.value) }],
    });
  }

  async function doMerge(from) {
    const r = S.repo;
    const prep = V.prepareMerge(r, from);
    if (prep.kind === 'up-to-date') return toast(`"${r.head}" đã có mọi thay đổi của "${from}".`);
    if (prep.kind === 'fast-forward') {
      V.finishMerge(r, prep, {});
      afterSwitch();
      return toast(`Đã cập nhật "${r.head}" tới "${from}" (fast-forward).`);
    }
    if (!(await ensureAuthor())) return;
    const msg = h('input', { value: `Merge "${from}" vào "${r.head}"` });
    if (!prep.conflicts.length) {
      return modal({
        title: 'Merge không có xung đột ✔',
        body: h('div', null,
          h('label', { class: 'field' }, 'Mô tả merge commit', msg),
          h('div', { class: 'muted small', style: { margin: '10px 0 6px' } }, 'Thay đổi sẽ được đưa vào:'),
          renderChanges(V.diffSnapshots(r.commits[prep.oursId].snapshot, prep.snapshot))),
        actions: [{ label: 'Huỷ' }, {
          label: '⑂ Merge', primary: true,
          onClick: () => { V.finishMerge(r, prep, { snapshot: prep.snapshot, author: author(), message: msg.value, from }); afterSwitch(); toast('Đã merge xong'); },
        }],
      });
    }
    // Có xung đột → cho người dùng chọn từng chỗ.
    const choices = [];
    const show = (v) => {
      if (v === null || v === undefined) return '(đã xoá / trống)';
      if (typeof v === 'object') return v.blocks ? `Trang "${v.title}" — ${v.blocks.length} khối` : `${V.blockName(v)}\n\n${v.text || v.code || v.url || ''}`;
      return String(v);
    };
    const cards = prep.conflicts.map((c, i) => {
      const name = `cf${i}`;
      const isText = typeof c.ours === 'string' && typeof c.theirs === 'string';
      const manual = isText ? h('textarea', { class: 'mono', rows: 5, oninput: (e) => (choices[i] = { value: e.target.value }) },
        `${c.ours}\n${c.theirs}`) : null;
      const opt = (val, label, content) => h('label', { class: 'opt' },
        h('input', { type: 'radio', name, onchange: () => { choices[i] = val === 'manual' ? { value: manual.value } : val; if (manual) manual.hidden = val !== 'manual'; } }),
        ' ', h('b', null, label), content !== undefined ? h('pre', null, content) : null);
      if (manual) manual.hidden = true;
      return h('div', { class: 'conflict' },
        h('div', null, h('b', null, `⚠ Xung đột ${i + 1}: `), c.label),
        h('div', { class: 'sides' }, opt('ours', `Giữ của bạn (${r.head})`, show(c.ours)), opt('theirs', `Lấy của "${from}"`, show(c.theirs))),
        isText ? h('div', { style: { marginTop: '6px' } }, opt('manual', 'Tự gộp bằng tay'), manual) : null);
    });
    modal({
      title: `Có ${prep.conflicts.length} xung đột cần giải quyết`, wide: true,
      body: h('div', null,
        h('p', { class: 'muted small' }, `Cả "${r.head}" và "${from}" đều sửa cùng một chỗ. Chọn phiên bản muốn giữ cho từng chỗ.`),
        cards,
        h('label', { class: 'field' }, 'Mô tả merge commit', msg)),
      actions: [{ label: 'Huỷ merge' }, {
        label: '⑂ Hoàn tất merge', primary: true,
        onClick: () => {
          const missing = prep.conflicts.findIndex((_, i) => choices[i] === undefined);
          if (missing !== -1) throw new Error(`Chưa chọn cho xung đột ${missing + 1}.`);
          const snapshot = V.applyResolutions(prep.snapshot, prep.conflicts, choices);
          V.finishMerge(r, prep, { snapshot, author: author(), message: msg.value, from });
          afterSwitch();
          toast('Đã merge xong');
        },
      }],
    });
  }

  // ===================== Chia sẻ =====================
  async function shareDialog() {
    if (!(await ensureAuthor())) return;
    const r = S.repo;
    const checks = Object.keys(r.branches).sort().map((b) => h('label', { class: 'row small' },
      h('input', { type: 'checkbox', checked: true, value: b, style: { width: 'auto' } }), '⎇ ' + b));
    const out = h('div');
    const picked = () => {
      const names = checks.map((l) => l.querySelector('input')).filter((x) => x.checked).map((x) => x.value);
      if (!names.length) throw new Error('Chọn ít nhất một nhánh.');
      return names;
    };
    const dirtyNote = V.isDirty(r) ? h('p', { class: 'badge warn' }, '⚠ Thay đổi chưa commit sẽ KHÔNG được chia sẻ — hãy commit trước.') : null;
    modal({
      title: 'Chia sẻ notebook',
      body: h('div', null,
        h('p', { class: 'small muted' }, 'Người nhận mở file/link bằng nút "⬆ Nhập" để có bản riêng (fork), hoặc gộp vào notebook của họ như một nhánh rồi merge — giống GitHub.'),
        dirtyNote,
        h('div', { class: 'field' }, 'Nhánh muốn chia sẻ:', checks),
        h('div', { class: 'row' },
          h('button', {
            class: 'primary', onclick: () => {
              try {
                const bundle = V.exportBundle(r, { branches: picked(), author: author() });
                const fname = (r.working.title || 'notebook').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/g, 'd').replace(/Đ/g, 'D').replace(/[^\w-]+/g, '-').toLowerCase();
                Share.download(`${fname}.dsanote.json`, JSON.stringify(bundle));
              } catch (e) { toast(e.message, true); }
            },
          }, '⬇ Tải file .dsanote.json'),
          h('button', {
            onclick: async () => {
              try {
                const bundle = V.exportBundle(r, { branches: picked(), author: author() });
                const code = await Share.encode(bundle);
                const link = `${location.origin}${location.pathname}#share=${code}`;
                out.innerHTML = '';
                const ta = h('textarea', { class: 'mono', rows: 4, readOnly: true }, link);
                out.append(
                  h('label', { class: 'field' }, `Link chia sẻ (${(link.length / 1024).toFixed(1)} KB)`, ta),
                  link.length > 30000 ? h('p', { class: 'badge warn' }, '⚠ Link khá dài — một số ứng dụng chat có thể cắt mất. Nên gửi file thay thế.') : null,
                  location.protocol === 'file:' ? h('p', { class: 'badge warn' }, '⚠ App đang mở từ file trên máy — link chỉ dùng được trên máy này. Hãy đưa app lên GitHub Pages để chia sẻ link.') : null,
                  h('button', { class: 'sm', onclick: () => navigator.clipboard.writeText(link).then(() => toast('Đã sao chép link')) }, '📋 Sao chép link'));
                ta.select();
              } catch (e) { toast(e.message, true); }
            },
          }, '🔗 Tạo link')),
        out),
      actions: [{ label: 'Đóng' }],
    });
  }

  function importDialog() {
    const file = h('input', { type: 'file', accept: '.json,.dsanote,application/json' });
    const paste = h('textarea', { class: 'mono', rows: 3, placeholder: 'Hoặc dán link chia sẻ / nội dung JSON vào đây' });
    modal({
      title: 'Nhập notebook được chia sẻ',
      body: h('div', null, h('label', { class: 'field' }, 'Chọn file .dsanote.json', file), paste),
      actions: [{ label: 'Huỷ' }, {
        label: 'Tiếp tục', primary: true,
        onClick: async () => {
          let text = paste.value.trim();
          if (file.files[0]) text = await Share.readFile(file.files[0]);
          if (!text) throw new Error('Chọn file hoặc dán link.');
          await handleIncoming(text);
        },
      }],
    });
  }

  async function parseIncoming(text) {
    const m = text.match(/#share=([\w-]+)/);
    if (m) return Share.decode(m[1]);
    if (/^[zj][\w-]+$/.test(text)) return Share.decode(text);
    try { return JSON.parse(text); } catch (_) { throw new Error('Không đọc được dữ liệu. Hãy kiểm tra lại file/link.'); }
  }

  async function handleIncoming(text) {
    const bundle = V.validateBundle(await parseIncoming(text));
    const repos = await Store.list();
    const related = repos.filter((x) => x.id === bundle.repoId || x.upstream === bundle.repoId || Object.keys(bundle.commits).some((id) => x.commits[id]));
    const target = h('select', null, repos.map((x) => h('option', { value: x.id, selected: related[0] && x.id === related[0].id }, x.working.title)));
    const remoteName = h('input', { value: (bundle.sharedBy || 'ban').replace(/\s+/g, '-') });
    const nCommits = Object.keys(bundle.commits).length;
    modal({
      title: `Nhập "${bundle.title}"`,
      body: h('div', null,
        h('p', null, `Chia sẻ bởi `, h('b', null, bundle.sharedBy || 'Ẩn danh'), ` · ${timeAgo(bundle.sharedAt || Date.now())} · ${Object.keys(bundle.branches).length} nhánh · ${nCommits} commit`),
        h('div', { class: 'change' },
          h('b', null, '① Mở thành notebook riêng (fork)'),
          h('p', { class: 'small muted' }, 'Tạo bản sao đầy đủ lịch sử để bạn tự ghi chú tiếp.')),
        repos.length ? h('div', { class: 'change', style: { marginTop: '8px' } },
          h('b', null, '② Gộp vào notebook có sẵn (như git fetch)'),
          h('p', { class: 'small muted' }, 'Các nhánh của họ xuất hiện dạng "tên/nhánh" — bạn xem rồi merge những gì muốn lấy.' + (related.length ? ' ✔ Đã tìm thấy notebook có chung lịch sử.' : '')),
          h('label', { class: 'field' }, 'Notebook đích', target),
          h('label', { class: 'field' }, 'Tên người/nguồn', remoteName)) : null),
      actions: [
        { label: 'Huỷ' },
        repos.length ? {
          label: '② Gộp vào notebook', onClick: async () => {
            const repo = S.repo && S.repo.id === target.value ? S.repo : await Store.get(target.value);
            const res = V.fetchBundle(repo, bundle, remoteName.value.trim() || 'ban');
            await Store.put(repo);
            if (!S.repo || S.repo.id !== repo.id) await openRepo(repo.id);
            else render();
            toast(`Đã nhập ${res.added} commit mới, ${res.refs.length} nhánh: ${res.refs.join(', ')}`);
            if (!V.isDirty(S.repo)) mergeDialog(res.refs.find((x) => x.endsWith('/' + S.repo.head)) || res.refs[0]);
          },
        } : null,
        {
          label: '① Mở như notebook mới', primary: true, onClick: async () => {
            const repo = V.repoFromBundle(bundle);
            await Store.put(repo);
            await openRepo(repo.id);
            toast('Đã mở notebook được chia sẻ');
          },
        },
      ].filter(Boolean),
    });
  }

  // ===================== Cài đặt =====================
  function settingsDialog() {
    const name = h('input', { value: Settings.get('author') || '' });
    const theme = h('select', null, [['auto', 'Theo hệ thống'], ['light', 'Sáng'], ['dark', 'Tối']].map(([v, t]) => h('option', { value: v, selected: Settings.get('theme') === v }, t)));
    const compiler = h('input', { value: Settings.get('compiler'), class: 'mono' });
    const flags = h('input', { value: Settings.get('cppFlags'), class: 'mono' });
    modal({
      title: 'Cài đặt',
      body: h('div', null,
        h('label', { class: 'field' }, 'Tên của bạn (hiện trong commit / chia sẻ)', name),
        h('label', { class: 'field' }, 'Giao diện', theme),
        h('label', { class: 'field' }, 'Mã trình biên dịch Compiler Explorer (VD: g132 = GCC 13.2, clang1701 = Clang 17)', compiler),
        h('label', { class: 'field' }, 'Cờ biên dịch', flags),
        h('p', { class: 'small muted' }, 'Dữ liệu lưu trong trình duyệt này (IndexedDB). Hãy xuất file định kỳ để sao lưu.')),
      actions: [{ label: 'Huỷ' }, {
        label: 'Lưu', primary: true,
        onClick: () => {
          Settings.set('author', name.value.trim());
          Settings.set('theme', theme.value);
          Settings.set('compiler', compiler.value.trim() || 'g132');
          Settings.set('cppFlags', flags.value.trim());
          applyTheme();
          render();
        },
      }],
    });
  }

  // ===================== Phím tắt =====================
  document.addEventListener('keydown', (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 's') {
      e.preventDefault();
      if (S.repo && !document.querySelector('.modal-bg')) commitDialog();
    }
  });

  // ===================== Khởi động =====================
  async function checkShareHash() {
    const m = location.hash.match(/#share=([\w-]+)/);
    if (!m) return;
    history.replaceState(null, '', location.pathname + location.search);
    try { await handleIncoming(m[0]); } catch (e) { toast(e.message, true); }
  }
  async function boot() {
    applyTheme();
    const last = Settings.get('lastRepo');
    if (last && (await Store.get(last))) await openRepo(last);
    else render();
    await checkShareHash();
    // Dán link chia sẻ vào tab đang mở app chỉ đổi phần # nên không tải lại trang.
    window.addEventListener('hashchange', checkShareHash);
  }
  boot().catch((e) => {
    $app.innerHTML = '';
    $app.appendChild(h('div', { class: 'home' }, h('h1', null, 'Không khởi động được'), h('p', null, e.message),
      h('p', { class: 'muted' }, 'Trình duyệt cần hỗ trợ IndexedDB (không dùng chế độ chặn lưu trữ).')));
  });
})();
