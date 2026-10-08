/*
 * app.js — Giao diện chính: mục lục, trang tài liệu, các khối, khu code, nhánh/commit/merge, chia sẻ.
 */
(function () {
  'use strict';

  const {
    h, icon, btn, toast, modal, confirmBox, promptBox, renderMarkdown, markdownHeadings, parseTimestamps,
    videoPlayer, codeEditor, pickFiles, timeAgo, fullTime, isDark, slugify,
  } = window.UI;
  const { Platform, Store, Assets, Settings, Share, Runner } = window.Services;
  const V = window.VCS;
  const T = window.TEMPLATES;
  const CU = window.ContestUI;
  const $app = document.getElementById('app');
  document.documentElement.dataset.platform = Platform.name;

  // ===================== Giao diện sáng/tối =====================
  function applyTheme() {
    const pref = Settings.get('theme');
    const dark = pref === 'dark' || (pref === 'auto' && matchMedia('(prefers-color-scheme: dark)').matches);
    document.documentElement.dataset.theme = dark ? 'dark' : 'light';
    const l = document.getElementById('hljs-light');
    const d = document.getElementById('hljs-dark');
    if (l && d) { l.disabled = dark; d.disabled = !dark; }
  }
  matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => { applyTheme(); render(); });

  // ===================== Trạng thái =====================
  const S = {
    repo: null,
    pageId: null,
    preview: null, // { ref, label, snapshot } khi xem một commit/nhánh (chỉ đọc)
    editing: new Set(),
    tab: 'toc',
    search: '',
    tocOpen: window.innerWidth > 900,
    codeOpen: false,
    contest: null,
  };
  const live = new Set(); // mô phỏng / Blockly đang mở, huỷ khi vẽ lại

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
    const name = await promptBox('Tên của bạn', 'Tên hiển thị trong commit, khi chia sẻ và trên bảng xếp hạng', '');
    if (!name) return false;
    Settings.set('author', name);
    return true;
  }

  CU.init({ S, repo: () => S.repo, snap, saveSoon, render, author, ensureAuthor, readOnly });

  // Bổ sung trường mới cho dữ liệu cũ.
  function normalize(repo) {
    const fix = (s) => {
      if (!s.contests) s.contests = [];
      s.pages.forEach((p) => p.blocks.forEach((b) => { if (b.type === 'sim' && !b.mode) b.mode = 'code'; }));
    };
    Object.values(repo.commits).forEach((c) => fix(c.snapshot));
    fix(repo.working);
    repo.remotes = repo.remotes || {};
    return repo;
  }

  // Mẫu kéo thả lưu dạng XML → chuyển sang JSON + code khi tạo notebook.
  function materializeBlocks(snapshot) {
    snapshot.pages.forEach((p) => p.blocks.forEach((b) => {
      if (!b.blocksXml) return;
      let r = null;
      try { r = window.BLOCKS && window.BLOCKS.fromXml(b.blocksXml); } catch (e) { console.warn(e); }
      if (r) Object.assign(b, { blocks: r.json, code: r.code });
      else Object.assign(b, { mode: 'code', code: T.SIM_TEMPLATES[1].code });
      delete b.blocksXml;
    }));
    return snapshot;
  }

  // ===================== Điều hướng =====================
  async function openRepo(id) {
    const repo = await Store.get(id);
    if (!repo) return toast('Không tìm thấy notebook.', true);
    S.repo = normalize(repo);
    S.preview = null;
    S.contest = null;
    S.editing.clear();
    S.pageId = repo.working.pages[0] ? repo.working.pages[0].id : null;
    Settings.set('lastRepo', id);
    window.scrollTo(0, 0);
    render();
  }
  function goHome() {
    saveNow();
    S.repo = null;
    S.preview = null;
    S.contest = null;
    Settings.set('lastRepo', null);
    render();
  }

  // ===================== Vẽ =====================
  function render() {
    const y = window.scrollY;
    $app.style.minHeight = $app.offsetHeight + 'px';
    live.forEach((x) => x.destroy());
    live.clear();
    CU.cleanup();
    closePopover();
    $app.innerHTML = '';
    if (!S.repo) {
      $app.style.minHeight = '';
      renderHome();
      return;
    }
    const layout = h('div', { class: 'layout' + (S.tocOpen ? ' toc-open' : '') + (S.codeOpen ? ' code-open' : '') },
      renderSidebar(), renderMain(), S.codeOpen ? renderCodePanel() : null);
    $app.append(renderTopbar(), layout);
    updateStatus();
    window.scrollTo(0, y);
    requestAnimationFrame(() => ($app.style.minHeight = ''));
    spy();
  }

  function refreshSidebar() {
    const old = document.querySelector('.toc');
    if (old) old.replaceWith(renderSidebar());
    spy();
  }

  // ---------- Trang chủ ----------
  async function renderHome() {
    const repos = (await Store.list()).sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0));
    const list = h('div', { class: 'nb-list' });
    repos.forEach((r) => {
      const w = r.working;
      list.appendChild(h('div', { class: 'nb-row' },
        h('button', { class: 'nb-open', onclick: () => openRepo(r.id) },
          h('div', { class: 'nb-title' }, w.title || '(không tên)'),
          h('div', { class: 'nb-meta' }, `${w.pages.length} trang · ${Object.keys(r.branches).length} nhánh · ${Object.keys(r.commits).length} commit · sửa ${timeAgo(r.updatedAt || Date.now())}`)),
        btn('copy', 'Nhân bản', async () => {
          const copy = V.clone(r);
          copy.id = V.newId();
          copy.working.title += ' (bản sao)';
          await Store.put(copy);
          render();
        }, { class: 'ghost sm', compact: true }),
        btn('trash', 'Xoá', async () => {
          if (await confirmBox('Xoá notebook?', `Xoá vĩnh viễn "${w.title}" khỏi máy này? Hãy xuất file trước nếu cần giữ.`, 'Xoá', true)) {
            await Store.remove(r.id);
            render();
          }
        }, { class: 'ghost sm danger', compact: true })));
    });
    $app.appendChild(h('div', { class: 'home' },
      h('div', { class: 'home-head' },
        h('div', { class: 'grow' }, h('h1', null, 'Sổ tay DSA C++'),
          h('p', { class: 'muted' }, 'Ghi chú bài giảng, video, code C++, mô phỏng thuật toán và bài tập có chấm điểm.')),
        btn('settings', 'Cài đặt', settingsDialog, { class: 'ghost' })),
      h('div', { class: 'row' },
        btn('plus', 'Notebook mới', newRepoDialog, { class: 'primary' }),
        btn('upload', 'Mở file / link', importDialog),
        btn('book', 'Notebook hướng dẫn', () => createRepo('Hướng dẫn sử dụng', materializeBlocks(T.guideSnapshot())))),
      h('h2', { class: 'home-sub' }, 'Notebook trên máy này'),
      repos.length ? list : h('div', { class: 'empty' }, 'Chưa có notebook nào. Tạo mới hoặc mở notebook hướng dẫn để xem thử.')));
  }

  async function createRepo(title, snapshot) {
    if (!(await ensureAuthor())) return;
    const repo = normalize(V.createRepo({ title, author: author(), snapshot }));
    await Store.put(repo);
    openRepo(repo.id);
  }

  function newRepoDialog() {
    const title = h('input', { placeholder: 'VD: DSA C++ của tôi' });
    const desc = h('textarea', { rows: 2, placeholder: 'Mô tả ngắn (không bắt buộc)' });
    modal({
      title: 'Notebook mới',
      body: h('div', null, h('label', { class: 'field' }, 'Tên', title), h('label', { class: 'field' }, 'Mô tả', desc)),
      actions: [{ label: 'Huỷ' }, {
        label: 'Tạo', primary: true,
        onClick: () => {
          const t = title.value.trim() || 'Notebook DSA';
          const s = V.emptySnapshot(t);
          s.description = desc.value.trim();
          s.pages.push({ id: V.newId(12), title: t, chapter: '', blocks: [{ id: V.newId(12), type: 'heading', level: 1, text: 'Mở đầu' }, { id: V.newId(12), type: 'markdown', text: '' }] });
          createRepo(t, s);
        },
      }],
    });
  }

  // ---------- Thanh công cụ ----------
  function renderTopbar() {
    const r = S.repo;
    const branchSel = h('select', { class: 'branch', title: 'Nhánh hiện tại', onchange: (e) => switchBranch(e.target.value) });
    Object.keys(r.branches).sort().forEach((b) => branchSel.appendChild(h('option', { value: b, selected: b === r.head }, b)));
    branchSel.appendChild(h('option', { value: '__new' }, '+ Nhánh mới…'));
    branchSel.appendChild(h('option', { value: '__manage' }, 'Quản lý nhánh…'));
    return h('header', { class: 'topbar' },
      h('button', { class: 'ghost icon-only', title: 'Mục lục', onclick: () => { S.tocOpen = !S.tocOpen; render(); } }, icon('toc', 18)),
      h('button', { class: 'ghost icon-only', title: 'Danh sách notebook', onclick: goHome }, icon('book', 18)),
      h('input', { class: 'tb-title', value: r.working.title, readOnly: readOnly(), title: 'Tên notebook', oninput: (e) => { r.working.title = e.target.value; saveSoon(); } }),
      h('div', { class: 'tb-branch' }, icon('branch'), branchSel),
      h('span', { id: 'status' }),
      h('span', { class: 'grow' }),
      h('div', { class: 'tb-group' },
        btn('check', 'Commit', commitDialog, { class: 'primary', compact: true, title: 'Lưu phiên bản (Ctrl+S)' }),
        btn('history', 'Lịch sử', historyDialog, { compact: true }),
        btn('merge', 'Merge', () => mergeDialog(), { compact: true })),
      h('div', { class: 'tb-group' },
        btn('trophy', 'Contest', () => CU.contestsDialog(), { compact: true, class: S.contest ? 'on' : '' }),
        btn('terminal', 'Khu code', () => { S.codeOpen = !S.codeOpen; render(); }, { compact: true, class: S.codeOpen ? 'on' : '' })),
      h('div', { class: 'tb-group' },
        btn('share', 'Chia sẻ', shareDialog, { compact: true }),
        btn('upload', 'Nhập', importDialog, { compact: true }),
        h('button', { class: 'ghost icon-only', title: 'Cài đặt', onclick: settingsDialog }, icon('settings', 18))));
  }

  function updateStatus() {
    const el = document.getElementById('status');
    if (!el || !S.repo) return;
    const n = V.diffSnapshots(V.headSnapshot(S.repo), S.repo.working).length;
    el.className = n ? 'dirty' : 'clean';
    el.textContent = n ? `${n} thay đổi chưa commit` : 'Đã commit';
  }

  // ---------- Mục lục ----------
  function tocEntries(page) {
    const out = [];
    page.blocks.forEach((b) => {
      if (b.type === 'heading' && (b.text || '').trim()) out.push({ level: b.level || 1, text: b.text, anchor: `h-${b.id}` });
      else if (b.type === 'markdown') markdownHeadings(b.text).forEach((x, i) => out.push({ level: x.level, text: x.text, anchor: `h-${b.id}-${i}` }));
      else if (b.type === 'problem') out.push({ level: 2, text: b.title || 'Bài tập', anchor: `h-${b.id}`, problem: true });
    });
    return out;
  }

  function renderSidebar() {
    const side = h('aside', { class: 'toc' });
    const tab = (k, label) => h('button', { class: 'tab' + (S.tab === k ? ' on' : ''), onclick: () => { S.tab = k; refreshSidebar(); } }, label);
    side.appendChild(h('div', { class: 'tabs-line' }, tab('toc', 'Mục lục'), tab('videos', 'Video'), tab('problems', 'Bài tập')));
    const list = h('div', { class: 'toc-list' });
    side.appendChild(h('div', { class: 'toc-search' }, icon('search'), h('input', {
      placeholder: 'Tìm trong notebook…', value: S.search, type: 'search',
      oninput: (e) => { S.search = e.target.value; fill(); },
    })));
    side.appendChild(list);
    if (S.tab === 'toc' && !readOnly())
      side.appendChild(h('div', { class: 'toc-foot' }, btn('plus', 'Trang mới', addPage, { class: 'ghost sm' })));
    fill();
    return side;

    function fill() {
      list.innerHTML = '';
      const q = S.search.trim().toLowerCase();
      const pages = snap().pages.filter((p) => !q || JSON.stringify([p.title, p.chapter, p.blocks.map((b) => [b.text, b.title, b.statement, b.caption])]).toLowerCase().includes(q));
      if (S.tab === 'toc') {
        const s = snap();
        list.appendChild(h('div', { class: 'toc-doc' }, h('div', { class: 'toc-doc-title' }, s.title || 'Notebook'), s.description ? h('div', { class: 'small muted' }, s.description) : null));
        let chapter = null;
        pages.forEach((p) => {
          if ((p.chapter || '') !== chapter) {
            chapter = p.chapter || '';
            if (chapter) list.appendChild(h('div', { class: 'toc-chapter' }, chapter));
          }
          list.appendChild(h('button', { class: 'toc-page' + (p.id === S.pageId ? ' on' : ''), onclick: () => selectPage(p.id) }, icon('file'), h('span', null, p.title || '(không tên)')));
          tocEntries(p).forEach((e) => list.appendChild(h('button', {
            class: 'toc-item' + (e.problem ? ' problem' : ''), 'data-anchor': e.anchor, style: { paddingLeft: `${14 + (e.level - 1) * 14}px` },
            onclick: () => selectPage(p.id, e.anchor),
          }, e.problem ? icon('problem', 14) : null, e.text)));
        });
        if (!pages.length) list.appendChild(h('p', { class: 'muted small pad' }, q ? 'Không có kết quả.' : 'Chưa có trang nào.'));
      } else if (S.tab === 'videos') {
        let count = 0;
        pages.forEach((p) => p.blocks.filter((b) => b.type === 'video').forEach((b) => {
          count++;
          const v = window.UI.parseVideo(b.url);
          list.appendChild(h('button', { class: 'video-item', onclick: () => selectPage(p.id, `blk-${b.id}`) },
            v && v.kind === 'youtube' ? h('img', { src: `https://i.ytimg.com/vi/${encodeURIComponent(v.id)}/mqdefault.jpg`, alt: '', loading: 'lazy' }) : h('div', { class: 'thumb' }, icon('video', 20)),
            h('div', null, h('div', { class: 't' }, b.title || (v && v.kind === 'asset' ? 'Video trên máy' : b.url) || '(chưa có video)'), h('div', { class: 'p' }, p.title))));
        }));
        if (!count) list.appendChild(h('p', { class: 'muted small pad' }, 'Chưa có video. Thêm khối Video vào trang để tổng hợp ở đây.'));
      } else {
        const probs = CU.allProblems(snap()).filter((x) => pages.includes(x.page));
        probs.forEach((x) => list.appendChild(h('button', { class: 'video-item', onclick: () => selectPage(x.page.id, `h-${x.block.id}`) },
          h('div', { class: 'thumb sm' }, icon('problem', 18)),
          h('div', null, h('div', { class: 't' }, x.block.title || 'Bài tập'), h('div', { class: 'p' }, `${(x.block.tests || []).length} test · ${x.page.title}`)))));
        list.appendChild(h('div', { class: 'pad' }, btn('trophy', 'Contest…', () => CU.contestsDialog(), { class: 'sm' })));
        if (!probs.length) list.appendChild(h('p', { class: 'muted small pad' }, 'Chưa có bài tập. Chèn khối "Bài tập" vào trang.'));
      }
    }
  }

  // Tô sáng mục đang đọc trong mục lục.
  let spyTimer = null;
  function spy() {
    clearTimeout(spyTimer);
    spyTimer = setTimeout(() => {
      const anchors = [...document.querySelectorAll('.doc [id^="h-"]')];
      let cur = null;
      anchors.forEach((a) => { if (a.getBoundingClientRect().top < 120) cur = a.id; });
      if (!cur && anchors[0]) cur = anchors[0].id;
      document.querySelectorAll('.toc-item.on').forEach((x) => x.classList.remove('on'));
      const item = cur && document.querySelector(`.toc-item[data-anchor="${cur}"]`);
      if (item) item.classList.add('on');
    }, 60);
  }
  window.addEventListener('scroll', spy, { passive: true });

  function selectPage(id, anchor) {
    const same = id === S.pageId && !S.contest;
    S.pageId = id;
    S.contest = null;
    if (window.innerWidth <= 900) S.tocOpen = false;
    if (!same) {
      window.scrollTo(0, 0);
      render();
    } else if (window.innerWidth <= 900) render();
    if (anchor) setTimeout(() => {
      const el = document.getElementById(anchor);
      if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }, 30);
  }

  function addPage() {
    const cur = curPage();
    const p = { id: V.newId(12), title: 'Trang mới', chapter: cur ? cur.chapter : '', blocks: [{ id: V.newId(12), type: 'heading', level: 1, text: '' }] };
    const pages = S.repo.working.pages;
    pages.splice(cur ? pages.indexOf(cur) + 1 : pages.length, 0, p);
    S.pageId = p.id;
    S.contest = null;
    saveSoon();
    window.scrollTo(0, 0);
    render();
    const t = document.querySelector('.page-title');
    if (t) { t.focus(); t.select(); }
  }

  // ---------- Popover (menu nhỏ) ----------
  let pop = null;
  function closePopover() {
    if (pop) { pop.remove(); pop = null; }
  }
  function popover(anchor, items) {
    closePopover();
    pop = h('div', { class: 'popover' }, items.filter(Boolean).map((it) => it === '-' ? h('div', { class: 'pop-sep' }) :
      h('button', { class: 'pop-item' + (it.danger ? ' danger' : ''), onclick: () => { closePopover(); it.onClick(); } }, it.icon ? icon(it.icon) : null, h('span', null, it.label))));
    document.body.appendChild(pop);
    const r = anchor.getBoundingClientRect();
    const pw = pop.offsetWidth;
    const ph = pop.offsetHeight;
    let left = Math.min(r.left, window.innerWidth - pw - 8);
    let top = r.bottom + 4;
    if (top + ph > window.innerHeight - 8) top = Math.max(8, r.top - ph - 4);
    pop.style.left = Math.max(8, left) + 'px';
    pop.style.top = top + window.scrollY + 'px';
  }
  document.addEventListener('mousedown', (e) => {
    if (pop && !pop.contains(e.target) && !e.target.closest('.blk-handle, .ins-btn')) closePopover();
  });
  window.addEventListener('resize', closePopover);

  // ---------- Tài liệu ----------
  function renderMain() {
    const main = h('main', { class: 'doc' });
    if (S.contest) {
      main.appendChild(CU.contestView());
      return main;
    }
    const inner = h('div', { class: 'doc-inner' });
    main.appendChild(inner);
    if (S.preview)
      inner.appendChild(h('div', { class: 'banner' },
        icon('eye'), h('span', { class: 'grow' }, 'Đang xem ', h('b', null, S.preview.label), ' — chỉ đọc'),
        S.preview.onMerge ? btn('merge', 'Merge vào nhánh hiện tại', S.preview.onMerge, { class: 'sm' }) : null,
        btn('branch', 'Tạo nhánh từ đây', () => newBranchDialog(S.preview.ref), { class: 'sm' }),
        btn('back', 'Về nhánh ' + S.repo.head, () => { S.preview = null; render(); }, { class: 'sm primary' })));

    const page = curPage();
    if (!page) {
      if (snap().pages.length) {
        S.pageId = snap().pages[0].id;
        return renderMain();
      }
      inner.appendChild(h('div', { class: 'empty' }, h('p', null, 'Notebook chưa có trang nào.'), readOnly() ? null : btn('plus', 'Tạo trang', addPage, { class: 'primary' })));
      return main;
    }
    const ro = readOnly();
    const pages = S.repo.working.pages;

    // Phần tiêu đề trang.
    const chapters = [...new Set(snap().pages.map((p) => p.chapter).filter(Boolean))];
    inner.appendChild(h('div', { class: 'page-head' },
      h('div', { class: 'crumb' }, snap().title || 'Notebook', page.chapter ? ` / ${page.chapter}` : ''),
      h('input', {
        class: 'page-title', value: page.title, readOnly: ro, placeholder: 'Tiêu đề trang',
        oninput: (e) => { page.title = e.target.value; saveSoon(); }, onchange: refreshSidebar,
      }),
      h('div', { class: 'page-meta' },
        h('label', { class: 'row small muted' }, 'Chương',
          h('input', { class: 'chapter-input', value: page.chapter || '', readOnly: ro, list: 'chapters', placeholder: 'VD: Sắp xếp', oninput: (e) => { page.chapter = e.target.value; saveSoon(); }, onchange: refreshSidebar }),
          h('datalist', { id: 'chapters' }, chapters.map((c) => h('option', { value: c })))),
        h('span', { class: 'grow' }),
        ro ? null : h('div', { class: 'row' },
          h('button', { class: 'ghost icon-only sm', title: 'Đưa trang lên', onclick: () => movePage(-1) }, icon('up')),
          h('button', { class: 'ghost icon-only sm', title: 'Đưa trang xuống', onclick: () => movePage(1) }, icon('down')),
          h('button', {
            class: 'ghost icon-only sm danger', title: 'Xoá trang',
            onclick: async () => {
              if (!(await confirmBox('Xoá trang?', `Xoá trang "${page.title}"? Có thể khôi phục từ lịch sử nếu đã commit.`, 'Xoá', true))) return;
              const i = pages.indexOf(page);
              pages.splice(i, 1);
              S.pageId = pages[Math.max(0, i - 1)] ? pages[Math.max(0, i - 1)].id : null;
              saveSoon();
              render();
            },
          }, icon('trash'))))));

    page.blocks.forEach((b, i) => {
      if (!ro) inner.appendChild(inserter(page, i));
      inner.appendChild(renderBlock(page, b));
    });
    if (!ro) {
      inner.appendChild(h('div', { class: 'add-bar' },
        h('span', { class: 'muted small' }, 'Thêm khối:'),
        TYPES.map(([kind, label, ic]) => btn(ic, label, () => addBlock(page, page.blocks.length, kind), { class: 'sm ghost' }))));
      // Kéo thả ảnh / video từ máy vào trang.
      main.addEventListener('dragover', (e) => {
        if ([...(e.dataTransfer.types || [])].includes('Files')) { e.preventDefault(); main.classList.add('drop'); }
      });
      main.addEventListener('dragleave', (e) => { if (e.target === main) main.classList.remove('drop'); });
      main.addEventListener('drop', async (e) => {
        main.classList.remove('drop');
        const files = [...e.dataTransfer.files].filter((f) => /^(image|video)\//.test(f.type));
        if (!files.length) return;
        e.preventDefault();
        for (const f of files) {
          const ref = await Assets.add(f);
          page.blocks.push(f.type.startsWith('image/')
            ? { id: V.newId(12), type: 'image', src: ref, caption: '', width: 'full' }
            : { id: V.newId(12), type: 'video', url: ref, title: f.name, timestamps: '' });
        }
        saveSoon();
        render();
        toast(`Đã thêm ${files.length} file`);
      });
    }
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

  const TYPES = [
    ['heading', 'Tiêu đề', 'heading'],
    ['markdown', 'Văn bản', 'text'],
    ['image', 'Ảnh', 'image'],
    ['video', 'Video', 'video'],
    ['code', 'Code C++', 'code'],
    ['sim-blocks', 'Mô phỏng kéo thả', 'blocks'],
    ['sim-code', 'Mô phỏng bằng code', 'sim'],
    ['problem', 'Bài tập', 'problem'],
  ];

  function inserter(page, index) {
    const b = h('button', { class: 'ins-btn', title: 'Chèn khối', onclick: () => popover(b, TYPES.map(([kind, label, ic]) => ({ icon: ic, label, onClick: () => addBlock(page, index, kind) }))) }, icon('plus', 14));
    return h('div', { class: 'ins' }, b);
  }

  async function addBlock(page, index, kind) {
    const id = V.newId(12);
    let b;
    if (kind === 'heading') b = { id, type: 'heading', level: 2, text: '' };
    else if (kind === 'markdown') b = { id, type: 'markdown', text: '' };
    else if (kind === 'image') b = { id, type: 'image', src: '', caption: '', width: 'full' };
    else if (kind === 'video') b = { id, type: 'video', title: '', url: '', timestamps: '' };
    else if (kind === 'code') b = { id, type: 'code', title: '', code: CU.CPP_TEMPLATE, stdin: '' };
    else if (kind === 'sim-blocks') b = { id, type: 'sim', mode: 'blocks', title: '', blocks: null, code: '', input: '5 1 4 2 8 3' };
    else if (kind === 'sim-code') b = { id, type: 'sim', mode: 'code', title: '', code: T.SIM_TEMPLATES[0].code, input: '5 1 4 2 8 3' };
    else if (kind === 'problem') b = { id, type: 'problem', ...CU.newProblem() };
    page.blocks.splice(index, 0, b);
    if (kind !== 'heading') S.editing.add(id);
    saveSoon();
    render();
    const el = document.querySelector(`[data-block="${id}"]`);
    if (el) {
      el.scrollIntoView({ block: 'center' });
      const f = el.querySelector('input:not([type=file]):not([type=checkbox]), textarea');
      if (f) f.focus();
    }
    if (kind === 'image') {
      const [file] = await pickFiles('image/*');
      if (file) {
        b.src = await Assets.add(file);
        S.editing.delete(id);
        saveSoon();
        render();
      }
    }
  }

  // ---------- Khối ----------
  function renderBlock(page, b) {
    const ro = readOnly();
    const editing = !ro && S.editing.has(b.id);
    const framed = ['video', 'code', 'sim', 'problem'].includes(b.type);
    const body = h('div', { class: 'blk-body' });
    const el = h('section', { class: `blk blk-${b.type}${editing ? ' editing' : ''}${framed ? ' framed' : ''}`, 'data-block': b.id, id: `blk-${b.id}` });
    const toggle = () => {
      if (S.editing.has(b.id)) S.editing.delete(b.id);
      else S.editing.add(b.id);
      render();
    };
    const change = (field, value) => {
      b[field] = value;
      saveSoon();
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
      const handle = h('button', {
        class: 'blk-handle', title: 'Tuỳ chọn khối',
        onclick: () => popover(handle, [
          b.type !== 'heading' ? { icon: editing ? 'check' : 'edit', label: editing ? 'Xong' : 'Sửa', onClick: toggle } : null,
          b.type === 'heading' ? { icon: 'heading', label: 'Tiêu đề lớn (H1)', onClick: () => { change('level', 1); render(); } } : null,
          b.type === 'heading' ? { icon: 'heading', label: 'Tiêu đề vừa (H2)', onClick: () => { change('level', 2); render(); } } : null,
          b.type === 'heading' ? { icon: 'heading', label: 'Tiêu đề nhỏ (H3)', onClick: () => { change('level', 3); render(); } } : null,
          { icon: 'up', label: 'Lên trên', onClick: () => move(-1) },
          { icon: 'down', label: 'Xuống dưới', onClick: () => move(1) },
          { icon: 'copy', label: 'Nhân bản', onClick: () => { blocks.splice(blocks.indexOf(b) + 1, 0, { ...V.clone(b), id: V.newId(12) }); saveSoon(); render(); } },
          '-',
          {
            icon: 'trash', label: 'Xoá khối', danger: true,
            onClick: async () => {
              const empty = !(b.text || b.url || b.title || b.src || (b.type === 'code' && b.code !== CU.CPP_TEMPLATE));
              if (!empty && !(await confirmBox('Xoá khối?', `Xoá ${V.blockName(b)}?`, 'Xoá', true))) return;
              blocks.splice(blocks.indexOf(b), 1);
              S.editing.delete(b.id);
              saveSoon();
              render();
            },
          },
        ]),
      }, icon('more'));
      el.appendChild(h('div', { class: 'blk-gutter' }, handle));
    }
    el.appendChild(body);
    const R = { heading: blockHeading, markdown: blockMarkdown, image: blockImage, video: blockVideo, code: blockCode, sim: blockSim, problem: blockProblem }[b.type];
    if (R) R(body, b, editing, change);
    else body.appendChild(h('div', { class: 'muted' }, `Loại khối chưa hỗ trợ: ${b.type}`));
    if (editing && b.type !== 'heading')
      body.appendChild(h('div', { class: 'done-row' }, btn('check', 'Xong', toggle, { class: 'sm' })));
    return el;
  }

  function blockHeading(el, b, editing, change) {
    const lvl = Math.min(3, Math.max(1, b.level || 1));
    if (readOnly()) {
      el.appendChild(h('h' + lvl, { class: `doc-h l${lvl}`, id: `h-${b.id}` }, b.text || ''));
      return;
    }
    el.appendChild(h('input', {
      class: `doc-h l${lvl}`, id: `h-${b.id}`, value: b.text || '', placeholder: lvl === 1 ? 'Tiêu đề' : 'Tiêu đề mục',
      oninput: (e) => change('text', e.target.value), onchange: refreshSidebar,
      onkeydown: (e) => {
        if (e.key === 'Enter') {
          e.preventDefault();
          const page = curPage();
          addBlock(page, page.blocks.indexOf(b) + 1, 'markdown');
        }
      },
    }));
  }

  function blockMarkdown(el, b, editing, change, ) {
    if (editing) {
      const ta = h('textarea', { class: 'md-edit', placeholder: 'Viết ghi chú (Markdown): # Tiêu đề, **đậm**, *nghiêng*, `code`, - danh sách, ```cpp … ``` …' }, b.text || '');
      const grow = () => { ta.style.height = 'auto'; ta.style.height = Math.max(140, ta.scrollHeight + 4) + 'px'; };
      const set = () => { change('text', ta.value); grow(); };
      ta.addEventListener('input', set);
      ta.addEventListener('change', refreshSidebar);
      // Dán ảnh trực tiếp vào ghi chú.
      ta.addEventListener('paste', async (e) => {
        const file = [...(e.clipboardData.files || [])].find((f) => f.type.startsWith('image/'));
        if (!file) return;
        e.preventDefault();
        const ref = await Assets.add(file);
        ta.setRangeText(`![](${ref})`, ta.selectionStart, ta.selectionEnd, 'end');
        set();
      });
      const wrap = (pre, post = pre) => () => {
        const s = ta.selectionStart;
        const t = ta.value.slice(s, ta.selectionEnd);
        ta.setRangeText(pre + (t || 'chữ') + post, s, ta.selectionEnd, 'select');
        ta.focus();
        set();
      };
      el.append(h('div', { class: 'md-tools' },
        h('button', { class: 'ghost sm', title: 'Đậm', onclick: wrap('**') }, h('b', null, 'B')),
        h('button', { class: 'ghost sm', title: 'Nghiêng', onclick: wrap('*') }, h('i', null, 'I')),
        h('button', { class: 'ghost sm mono', title: 'Code', onclick: wrap('`') }, '</>'),
        h('button', { class: 'ghost sm', title: 'Tiêu đề', onclick: () => { ta.setRangeText('\n## ', ta.selectionStart, ta.selectionStart, 'end'); ta.focus(); set(); } }, 'H'),
        btn('image', 'Chèn ảnh', async () => {
          const [f] = await pickFiles('image/*');
          if (!f) return;
          const ref = await Assets.add(f);
          ta.setRangeText(`\n![](${ref})\n`, ta.selectionStart, ta.selectionEnd, 'end');
          set();
        }, { class: 'ghost sm' }),
        h('span', { class: 'muted small' }, 'Có thể dán ảnh (Ctrl+V)')), ta);
      requestAnimationFrame(grow);
      return;
    }
    if (!b.text) {
      el.appendChild(h('div', { class: 'placeholder', ondblclick: () => !readOnly() && (S.editing.add(b.id), render()) }, readOnly() ? '' : 'Văn bản trống — nhấp đúp để viết.'));
      return;
    }
    const md = renderMarkdown(b.text, { headingIds: markdownHeadings(b.text).map((_, i) => `h-${b.id}-${i}`) });
    if (!readOnly()) md.addEventListener('dblclick', () => { S.editing.add(b.id); render(); });
    el.appendChild(md);
  }

  const WIDTHS = [['full', 'Toàn bộ'], ['large', 'Lớn'], ['medium', 'Vừa'], ['small', 'Nhỏ']];
  function blockImage(el, b, editing, change) {
    const fig = h('figure', { class: `img-fig w-${b.width || 'full'}` });
    if (b.src) {
      const img = h('img', { alt: b.caption || '', loading: 'lazy', onclick: () => lightbox(img.src, b.caption) });
      if (b.src.startsWith('asset:')) Assets.url(b.src).then((u) => (u ? (img.src = u) : img.replaceWith(h('div', { class: 'img-ph' }, 'Không tìm thấy ảnh trên máy này.'))));
      else img.src = b.src;
      fig.appendChild(img);
    } else fig.appendChild(h('div', { class: 'img-ph' }, 'Chưa có ảnh.'));
    if (b.caption) fig.appendChild(h('figcaption', null, b.caption));
    el.appendChild(fig);
    if (!editing) return;
    el.append(
      h('div', { class: 'row', style: { marginTop: '8px' } },
        btn('upload', b.src ? 'Đổi ảnh từ máy' : 'Chọn ảnh từ máy', async () => {
          const [f] = await pickFiles('image/*');
          if (!f) return;
          change('src', await Assets.add(f));
          render();
        }, { class: 'sm' }),
        h('span', { class: 'muted small' }, 'hoặc dán link ảnh:'),
        h('input', { class: 'grow', value: b.src && !b.src.startsWith('asset:') ? b.src : '', placeholder: 'https://…', onchange: (e) => { change('src', e.target.value.trim()); render(); } })),
      h('div', { class: 'row' },
        h('label', { class: 'field grow' }, 'Chú thích', h('input', { value: b.caption || '', oninput: (e) => change('caption', e.target.value) })),
        h('label', { class: 'field' }, 'Kích thước', h('select', { onchange: (e) => { change('width', e.target.value); render(); } },
          WIDTHS.map(([v, t]) => h('option', { value: v, selected: (b.width || 'full') === v }, t))))));
  }

  function lightbox(src, caption) {
    if (!src) return;
    const bg = h('div', { class: 'lightbox', onclick: () => bg.remove() }, h('img', { src }), caption ? h('div', { class: 'lb-cap' }, caption) : null);
    document.body.appendChild(bg);
  }

  function blockVideo(el, b, editing, change) {
    if (editing) {
      const isAsset = (b.url || '').startsWith('asset:');
      el.append(
        h('div', { class: 'blk-kind' }, icon('video'), 'Video'),
        h('label', { class: 'field' }, 'Link video (YouTube, playlist, Google Drive, Facebook, TikTok, Vimeo, file .mp4…)',
          h('input', { value: isAsset ? '' : b.url || '', placeholder: isAsset ? 'Đang dùng video từ máy' : 'https://www.youtube.com/watch?v=…', oninput: (e) => change('url', e.target.value.trim()), onchange: () => render() })),
        h('div', { class: 'row' }, btn('upload', 'Chọn file video từ máy', async () => {
          const [f] = await pickFiles('video/*');
          if (!f) return;
          if (f.size > 200 * 1024 * 1024 && !(await confirmBox('Video lớn', `File ${(f.size / 1048576).toFixed(0)} MB. Video lớn làm file chia sẻ rất nặng. Vẫn thêm?`, 'Thêm'))) return;
          change('url', await Assets.add(f));
          if (!b.title) change('title', f.name);
          render();
        }, { class: 'sm' }), isAsset ? h('span', { class: 'small muted' }, 'Đang dùng video lưu trên máy.') : null),
        h('label', { class: 'field' }, 'Tiêu đề / nguồn', h('input', { value: b.title || '', placeholder: 'VD: Bài 5 — Quick sort', oninput: (e) => change('title', e.target.value) })),
        h('label', { class: 'field' }, 'Mốc thời gian (mỗi dòng: mm:ss nội dung)', h('textarea', { class: 'mono', rows: 4, placeholder: '00:00 Giới thiệu\n03:15 Ý tưởng\n12:40 Code', oninput: (e) => change('timestamps', e.target.value) }, b.timestamps || '')));
    }
    if (b.title && !editing) el.appendChild(h('h3', { class: 'blk-title' }, b.title));
    const player = videoPlayer(b.url, b.title);
    el.appendChild(player.el);
    const ts = parseTimestamps(b.timestamps);
    if (ts.length)
      el.appendChild(h('div', { class: 'ts-list' }, ts.map((t) => h('button', {
        class: 'ts', onclick: () => (player.seek ? player.seek(t.sec) : toast('Video này không hỗ trợ nhảy tới mốc thời gian')),
      }, h('span', { class: 'time' }, t.time), h('span', null, t.label)))));
  }

  function blockCode(el, b, editing, change) {
    el.appendChild(h('div', { class: 'blk-kind' }, icon('code'), b.title ? h('span', { class: 'mono' }, b.title) : 'Code C++'));
    let getCode = () => b.code || '';
    if (editing) {
      el.appendChild(h('label', { class: 'field' }, 'Tên file', h('input', { value: b.title || '', placeholder: 'VD: quick_sort.cpp', oninput: (e) => change('title', e.target.value) })));
      const ed = codeEditor(b.code || '', 'cpp', (v) => change('code', v));
      getCode = ed.getValue;
      el.appendChild(ed.el);
    } else {
      const code = h('code', { class: 'language-cpp' }, b.code || '');
      if (window.hljs) try { hljs.highlightElement(code); } catch (_) { /* bỏ qua */ }
      el.appendChild(h('pre', { class: 'code-view' }, code));
    }
    const stdin = h('textarea', { class: 'mono', rows: 3, readOnly: readOnly(), placeholder: 'Dữ liệu nhập (stdin)', oninput: (e) => change('stdin', e.target.value) }, b.stdin || '');
    const out = h('div');
    el.append(
      h('details', { class: 'stdin', open: !!b.stdin || editing }, h('summary', null, 'stdin'), stdin),
      h('div', { class: 'row', style: { marginTop: '8px' } },
        runButton(() => getCode(), () => stdin.value, out),
        btn('copy', 'Sao chép', () => navigator.clipboard.writeText(getCode()).then(() => toast('Đã sao chép')), { class: 'sm ghost' }),
        btn('download', 'Tải .cpp', () => Share.save(slugify((b.title || 'main').replace(/\.cpp$/, '')) + '.cpp', getCode(), 'text/x-c++src'), { class: 'sm ghost' }),
        btn('terminal', 'Mở ở khu code', () => { setScratch({ code: getCode(), stdin: stdin.value }); S.codeOpen = true; render(); }, { class: 'sm ghost' })),
      out);
  }

  function runButton(getCode, getStdin, out) {
    const b = btn('play', 'Chạy', async () => {
      b.disabled = true;
      b.querySelector('.lbl').textContent = 'Đang chạy…';
      out.innerHTML = '';
      try {
        const r = await Runner.run(getCode(), getStdin());
        if (r.phase === 'compile') out.appendChild(outBox('Lỗi biên dịch', r.output, 'err', r.where));
        else {
          if (r.warnings) out.appendChild(outBox('Cảnh báo', r.warnings, '', ''));
          out.appendChild(outBox(r.timedOut ? 'Quá thời gian (5 giây)' : `Kết quả · mã thoát ${r.exitCode} · ${Math.round(r.timeMs || 0)} ms`, r.stdout || '(không có output)', r.exitCode === 0 && !r.timedOut ? 'ok' : 'err', r.where));
          if (r.stderr) out.appendChild(outBox('stderr', r.stderr, 'err', ''));
        }
      } catch (e) {
        out.appendChild(outBox('Không chạy được', `${e.message}\n${Platform.desktop ? 'Kiểm tra g++ trong Cài đặt.' : 'Cần Internet để biên dịch online (godbolt.org).'}`, 'err', ''));
      }
      b.disabled = false;
      b.querySelector('.lbl').textContent = 'Chạy';
    }, { class: 'primary sm' });
    return b;
  }
  const outBox = (title, text, cls, where) => h('div', { class: 'run-out ' + cls },
    h('div', { class: 'hd' }, h('span', { class: 'grow' }, title), where ? h('span', { class: 'muted' }, where) : null), h('pre', null, text));

  function blockSim(el, b, editing, change) {
    const mode = b.mode || 'code';
    el.appendChild(h('div', { class: 'blk-kind' }, icon(mode === 'blocks' ? 'blocks' : 'sim'), b.title || (mode === 'blocks' ? 'Mô phỏng kéo thả' : 'Mô phỏng')));
    const holder = h('div', { class: 'sim-holder' });
    let player = null;
    const run = () => {
      if (!holder.isConnected) return;
      if (!player) {
        player = window.SIM.mount(holder);
        live.add(player);
      }
      player.run(b.code || '', b.input || '');
    };
    const input = h('textarea', {
      class: 'sim-input mono', rows: Math.min(8, Math.max(1, (b.input || '').split('\n').length)), readOnly: readOnly(),
      placeholder: 'Dữ liệu vào', oninput: (e) => change('input', e.target.value),
    }, b.input || '');

    if (!editing) {
      el.append(holder, h('div', { class: 'row sim-row' }, h('div', { class: 'grow' }, input), btn('play', 'Chạy lại', run, { class: 'sm' })));
      requestAnimationFrame(run);
      return;
    }

    const seg = h('div', { class: 'seg' },
      h('button', { class: mode === 'blocks' ? 'on' : '', onclick: () => switchMode('blocks') }, icon('blocks'), 'Kéo thả'),
      h('button', { class: mode === 'code' ? 'on' : '', onclick: () => switchMode('code') }, icon('code'), 'Viết code'));
    el.append(h('div', { class: 'row' },
      h('label', { class: 'field grow' }, 'Tiêu đề', h('input', { value: b.title || '', placeholder: 'VD: Mô phỏng Quick sort', oninput: (e) => change('title', e.target.value) })),
      h('div', { class: 'field' }, 'Cách tạo', seg)));

    if (mode === 'blocks') {
      const area = h('div', { class: 'bk-area' });
      const codePre = h('pre', { class: 'code-view small' }, b.code || '');
      const tpl = h('select', { style: { width: 'auto' } }, h('option', { value: '' }, 'Chèn mẫu…'),
        window.BLOCKS.BLOCK_TEMPLATES.map((t) => h('option', { value: t.id }, t.name)));
      let ed = null;
      tpl.onchange = async () => {
        const t = window.BLOCKS.BLOCK_TEMPLATES.find((x) => x.id === tpl.value);
        tpl.value = '';
        if (!t || !ed) return;
        if (b.blocks && !(await confirmBox('Thay bằng mẫu?', 'Các khối hiện tại sẽ bị thay bằng mẫu.', 'Thay'))) return;
        ed.loadXml(t.xml);
        change('input', t.input);
        input.value = t.input;
        if (!b.title) change('title', t.name.replace(/^Kéo thả: /, ''));
        run();
      };
      el.append(
        h('div', { class: 'row', style: { margin: '4px 0 8px' } }, tpl,
          btn('maximize', 'Phóng to', () => { area.classList.toggle('fullscreen'); ed && ed.resize(); }, { class: 'sm' }),
          h('span', { class: 'muted small' }, 'Kéo khối từ bên trái. Chỉ số mảng bắt đầu từ 0 như C++.')),
        area,
        h('details', { class: 'gen-code' }, h('summary', null, 'Xem code JavaScript sinh ra'), codePre));
      const mountWhenReady = (tries = 0) => {
        if (!area.isConnected) return tries < 60 && requestAnimationFrame(() => mountWhenReady(tries + 1));
        ed = window.BLOCKS.mount(area, {
          json: b.blocks, dark: isDark(),
          onChange: (json, code) => {
            if (V.same(json, b.blocks) && code === b.code) return;
            b.blocks = json;
            b.code = code;
            codePre.textContent = code;
            saveSoon();
          },
        });
        if (ed) {
          live.add({ destroy: () => ed.dispose() });
          // Nút thoát toàn màn hình.
          area.appendChild(h('button', { class: 'bk-exit sm', onclick: () => { area.classList.remove('fullscreen'); ed.resize(); } }, icon('x'), 'Thu nhỏ'));
        }
      };
      mountWhenReady();
    } else {
      const tpl = h('select', { style: { width: 'auto' } }, h('option', { value: '' }, 'Chèn mẫu…'), T.SIM_TEMPLATES.map((t) => h('option', { value: t.id }, t.name)));
      tpl.onchange = async () => {
        const t = T.SIM_TEMPLATES.find((x) => x.id === tpl.value);
        tpl.value = '';
        if (!t) return;
        if ((b.code || '').trim() && b.code !== T.SIM_TEMPLATES[0].code && !(await confirmBox('Thay code?', 'Code mô phỏng hiện tại sẽ bị thay bằng mẫu.', 'Thay'))) return;
        change('code', t.code);
        change('input', t.input);
        if (!b.title) change('title', t.name);
        render();
      };
      el.append(h('div', { class: 'row', style: { margin: '4px 0 8px' } }, tpl, btn('book', 'Các hàm viz', apiDialog, { class: 'sm' }),
        h('span', { class: 'muted small' }, 'JavaScript — vòng lặp và điều kiện viết giống C++.')),
      codeEditor(b.code || '', 'js', (v) => change('code', v)).el);
    }
    el.append(h('label', { class: 'field' }, 'Dữ liệu vào', input),
      h('div', { class: 'row', style: { marginBottom: '8px' } }, btn('play', 'Chạy thử', run, { class: 'primary sm' })), holder);
    requestAnimationFrame(run);

    async function switchMode(m) {
      if (m === mode) return;
      if (m === 'code') {
        if (!(await confirmBox('Chuyển sang viết code?', 'Code JavaScript sinh từ các khối sẽ được giữ để bạn sửa tiếp. Các khối kéo thả sẽ không còn dùng.', 'Chuyển'))) return;
        change('mode', 'code');
      } else {
        if ((b.code || '').trim() && !(await confirmBox('Chuyển sang kéo thả?', 'Code hiện tại không chuyển được thành khối. Bạn sẽ bắt đầu với bảng khối trống (code cũ vẫn còn trong lịch sử commit).', 'Chuyển'))) return;
        change('mode', 'blocks');
        change('blocks', null);
        change('code', '');
      }
      render();
    }
  }

  function apiDialog() {
    modal({ title: 'Các hàm mô phỏng (viz)', wide: true, body: renderMarkdown(T.API_DOC), actions: [{ label: 'Đóng', primary: true }] });
  }

  function blockProblem(el, b, editing, change) {
    if (editing) {
      el.appendChild(h('div', { class: 'blk-kind' }, icon('problem'), 'Bài tập — chế độ tác giả'));
      CU.problemEdit(el, b, change);
    } else CU.problemView(el, b, { anchor: `h-${b.id}` });
  }

  // ---------- Khu code ----------
  const scratchKey = () => `scratch:${S.repo.id}`;
  function getScratch() {
    try { return JSON.parse(localStorage.getItem(scratchKey()) || '{}'); } catch (_) { return {}; }
  }
  function setScratch(v) {
    try { localStorage.setItem(scratchKey(), JSON.stringify({ ...getScratch(), ...v })); } catch (_) { /* đầy */ }
  }
  function renderCodePanel() {
    const st = getScratch();
    const ed = codeEditor(st.code || CU.CPP_TEMPLATE, 'cpp', (v) => setScratch({ code: v }));
    const stdin = h('textarea', { class: 'mono', rows: 4, placeholder: 'stdin', oninput: (e) => setScratch({ stdin: e.target.value }) }, st.stdin || '');
    const out = h('div', { class: 'cp-out' });
    return h('aside', { class: 'codepanel' },
      h('div', { class: 'cp-head' }, icon('terminal'), h('b', { class: 'grow' }, 'Khu code'),
        h('button', { class: 'ghost icon-only', title: 'Đóng', onclick: () => { S.codeOpen = false; render(); } }, icon('x'))),
      h('div', { class: 'cp-body' }, ed.el,
        h('div', { class: 'small muted', style: { margin: '8px 0 4px' } }, 'stdin'), stdin,
        h('div', { class: 'row', style: { marginTop: '8px' } },
          runButton(() => ed.getValue(), () => stdin.value, out),
          readOnly() || S.contest ? null : btn('plus', 'Chèn vào trang', () => {
            const page = curPage();
            if (!page) return;
            page.blocks.push({ id: V.newId(12), type: 'code', title: '', code: ed.getValue(), stdin: stdin.value });
            saveSoon();
            render();
            toast('Đã chèn khối code vào cuối trang');
          }, { class: 'sm' })),
        out));
  }

  // ===================== Commit =====================
  function renderChanges(changes) {
    const box = h('div', { class: 'changes' });
    if (!changes.length) box.appendChild(h('div', { class: 'muted' }, 'Không có thay đổi.'));
    const tag = (c, t) => h('span', { class: 'tag ' + c }, t);
    const row = (...k) => box.appendChild(h('div', { class: 'change' }, ...k));
    changes.forEach((c) => {
      if (c.kind === 'meta') row(tag('m', 'M'), ` Thông tin notebook: ${c.field === 'title' ? 'tên' : 'mô tả'} → "${c.after || ''}"`);
      else if (c.kind === 'reorder-pages') row(tag('m', 'M'), ' Đổi thứ tự trang');
      else if (c.kind === 'page-added') row(tag('a', 'A'), ` Thêm trang "${c.page.title}" (${c.page.blocks.length} khối)`);
      else if (c.kind === 'page-removed') row(tag('d', 'D'), ` Xoá trang "${c.page.title}"`);
      else if (c.kind === 'contest-added') row(tag('a', 'A'), ` Thêm contest "${c.contest.title}"`);
      else if (c.kind === 'contest-removed') row(tag('d', 'D'), ` Xoá contest "${c.contest.title}"`);
      else if (c.kind === 'contest-changed') row(tag('m', 'M'), ` Sửa contest "${c.after.title}"`);
      else if (c.kind === 'page-changed') {
        const d = h('details', { class: 'change' }, h('summary', null, tag('m', 'M'), ` Sửa trang "${c.after.title}"`));
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
              const str = (v) => (v === undefined || v === null ? '' : typeof v === 'object' ? JSON.stringify(v, null, 1) : String(v));
              if (k === 'blocks') d.appendChild(h('div', { class: 'small muted' }, '(các khối kéo thả đã thay đổi)'));
              else d.appendChild(lineDiff(str(x.before[k]), str(x.after[k])));
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
    if (readOnly()) return toast('Đang ở chế độ xem. Quay về nhánh để commit.', true);
    const changes = V.diffSnapshots(V.headSnapshot(S.repo), S.repo.working);
    if (!changes.length) return toast('Không có thay đổi nào để commit.');
    if (!(await ensureAuthor())) return;
    const msg = h('input', { placeholder: 'VD: Thêm ghi chú Quick sort' });
    const doCommit = () => {
      V.commit(S.repo, { message: msg.value, author: author() });
      saveNow();
      render();
      toast(`Đã commit lên nhánh ${S.repo.head}`);
    };
    const m = modal({
      title: `Commit lên nhánh "${S.repo.head}"`,
      body: h('div', null, h('label', { class: 'field' }, 'Mô tả thay đổi', msg),
        h('div', { class: 'muted small', style: { margin: '10px 0 6px' } }, `${changes.length} thay đổi`), renderChanges(changes)),
      actions: [
        { label: 'Bỏ hết thay đổi', danger: true, onClick: () => discardChanges() },
        { label: 'Huỷ' },
        { label: 'Commit', primary: true, onClick: doCommit },
      ],
    });
    msg.addEventListener('keydown', (e) => { if (e.key === 'Enter') { doCommit(); m.close(); } });
  }

  async function discardChanges() {
    if (!(await confirmBox('Bỏ thay đổi?', 'Mọi thay đổi chưa commit sẽ mất.', 'Bỏ thay đổi', true))) return false;
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
          body: h('p', null, `Nhánh "${S.repo.head}" có thay đổi chưa commit. Chuyển sang "${name}" sẽ làm mất chúng.`),
          actions: [
            { label: 'Huỷ', onClick: () => resolve(false) },
            { label: 'Bỏ thay đổi và chuyển', danger: true, onClick: () => resolve(true) },
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
    S.contest = null;
    S.editing.clear();
    normalize(S.repo);
    if (!S.repo.working.pages.some((p) => p.id === S.pageId)) S.pageId = S.repo.working.pages[0] ? S.repo.working.pages[0].id : null;
    saveNow();
    render();
  }

  function newBranchDialog(fromRef) {
    const name = h('input', { placeholder: 'VD: ghi-chu-do-thi' });
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
      title: 'Nhánh mới',
      body: h('div', null, h('label', { class: 'field' }, 'Tên nhánh', name),
        h('p', { class: 'muted small' }, fromRef ? `Bắt đầu từ commit ${fromRef.slice(0, 7)}.` : `Bắt đầu từ "${S.repo.head}".${dirty ? ' Thay đổi chưa commit được mang sang nhánh mới.' : ''}`)),
      actions: [{ label: 'Huỷ' }, { label: 'Tạo nhánh', primary: true, onClick: create }],
      onClose: () => render(),
    });
    name.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') { try { create(); m.close(); } catch (err) { toast(err.message, true); } }
    });
  }

  function aheadBehind(a, b) {
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
    const m = modal({ title: 'Nhánh', wide: true, body, actions: [{ label: 'Nhánh mới', onClick: () => newBranchDialog() }, { label: 'Đóng', primary: true }] });
    fill();
    function fill() {
      body.innerHTML = '';
      const r = S.repo;
      const headId = V.headCommitId(r);
      const rows = (entries, remote) => h('table', { class: 'tbl' }, h('tbody', null, entries.sort().map(([name, id]) => {
        const c = r.commits[id];
        const ab = aheadBehind(id, headId);
        return h('tr', null,
          h('td', null, h('span', { class: 'badge ' + (remote ? 'remote' : 'branch') }, name), name === r.head ? h('span', { class: 'small muted' }, ' (đang dùng)') : null),
          h('td', { class: 'small muted' }, name === r.head ? '' : `${ab.ahead} commit mới · thiếu ${ab.behind}`),
          h('td', { class: 'small' }, `${c.message} — ${c.author}, ${timeAgo(c.time)}`),
          h('td', { class: 'row', style: { justifyContent: 'flex-end' } },
            remote ? btn('eye', 'Xem', () => { m.close(); previewRef(name); }, { class: 'sm' }) : name !== r.head ? btn('branch', 'Chuyển', () => { m.close(); switchBranch(name); }, { class: 'sm' }) : null,
            name !== r.head ? btn('merge', 'Merge', () => { m.close(); mergeDialog(name); }, { class: 'sm' }) : null,
            remote ? btn('branch', 'Tạo nhánh', () => { m.close(); newBranchDialog(V.resolveRef(r, name)); }, { class: 'sm' }) : btn('edit', 'Đổi tên', async () => {
              const to = await promptBox('Đổi tên nhánh', 'Tên mới', name);
              if (!to || to === name) return;
              try { V.renameBranch(r, name, to); saveNow(); fill(); render(); } catch (e) { toast(e.message, true); }
            }, { class: 'sm' }),
            name !== r.head ? h('button', {
              class: 'ghost icon-only sm danger', title: 'Xoá',
              onclick: async () => {
                if (remote) delete r.remotes[name];
                else {
                  const merged = V.isAncestor(r, id, headId);
                  if (!(await confirmBox('Xoá nhánh?', `Xoá nhánh "${name}"?${merged ? '' : ' Nhánh có commit chưa được merge.'}`, 'Xoá', true))) return;
                  V.deleteBranch(r, name);
                }
                saveNow();
                fill();
              },
            }, icon('trash')) : null));
      })));
      body.appendChild(h('h3', null, 'Nhánh của bạn'));
      body.appendChild(rows(Object.entries(r.branches), false));
      body.appendChild(h('h3', null, 'Nhánh nhận từ người khác'));
      const rem = Object.entries(r.remotes);
      body.appendChild(rem.length ? rows(rem, true) : h('p', { class: 'muted small' }, 'Chưa có. Dùng "Nhập" để gộp notebook người khác gửi vào đây.'));
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
    S.contest = null;
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
    const lanes = Math.max(1, ...rows.map((x) => Math.max(x.before.length, x.after.length, x.col + 1)));
    const LW = 14;
    const RH = 42;
    const palette = ['#0969da', '#1a7f37', '#bc4c00', '#8250df', '#bf3989', '#0a7ea4', '#cf222e'];
    const lx = (k) => 9 + k * LW;
    const list = h('div', { class: 'hist-list' });
    const detail = h('div', { class: 'hist-detail' }, h('p', { class: 'muted' }, 'Chọn một commit để xem chi tiết.'));
    rows.forEach((row) => {
      const c = row.commit;
      let svg = `<svg width="${lanes * LW + 6}" height="${RH}">`;
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
      svg += `<circle cx="${lx(row.col)}" cy="${RH / 2}" r="4.5" fill="${palette[row.col % palette.length]}"/></svg>`;
      const el = h('div', { class: 'hist-row', onclick: () => select(c, el) },
        h('span', { html: svg }),
        h('div', { class: 'info' },
          h('div', { class: 'msg' }, (labels[c.id] || []).map((l) => h('span', { class: 'badge ' + (l.remote ? 'remote' : 'branch') }, l.n)), ' ', c.message),
          h('div', { class: 'sub' }, `${c.id.slice(0, 7)} · ${c.author} · ${timeAgo(c.time)}`)));
      list.appendChild(el);
    });
    const m = modal({ title: `Lịch sử (${commits.length} commit)`, wide: true, body: h('div', { class: 'history' }, list, detail), actions: [{ label: 'Đóng', primary: true }] });

    function select(c, el) {
      list.querySelectorAll('.on').forEach((x) => x.classList.remove('on'));
      el.classList.add('on');
      const parent = c.parents[0] ? r.commits[c.parents[0]].snapshot : null;
      detail.innerHTML = '';
      detail.append(
        h('h3', { style: { marginTop: 0 } }, c.message),
        h('div', { class: 'small muted' }, `${c.author} · ${fullTime(c.time)}`),
        h('div', { class: 'small muted mono' }, `commit ${c.id}`, c.parents.length > 1 ? ` · merge ${c.parents.map((p) => p.slice(0, 7)).join(' + ')}` : ''),
        h('div', { class: 'row', style: { margin: '10px 0' } },
          btn('eye', 'Xem bản này', () => { m.close(); previewRef(c.id); }, { class: 'sm' }),
          btn('branch', 'Tạo nhánh từ đây', () => { m.close(); newBranchDialog(c.id); }, { class: 'sm' }),
          btn('history', 'Khôi phục bản này', async () => {
            if (!(await confirmBox('Khôi phục?', `Đưa nội dung về bản "${c.message}"? Thay đổi hiện như chưa commit để bạn xem lại.`, 'Khôi phục'))) return;
            S.repo.working = V.clone(c.snapshot);
            m.close();
            afterSwitch();
          }, { class: 'sm' }),
          btn('eye', 'So với hiện tại', () => {
            detail.querySelector('.changes').replaceWith(renderChanges(V.diffSnapshots(c.snapshot, S.repo.working)));
            detail.querySelector('.cmp').textContent = 'So với bản đang làm việc:';
          }, { class: 'sm' })),
        h('div', { class: 'small muted cmp', style: { marginBottom: '6px' } }, parent ? 'Thay đổi so với commit trước:' : 'Commit đầu tiên:'),
        renderChanges(V.diffSnapshots(parent, c.snapshot)));
    }
  }

  // ===================== Merge =====================
  function mergeDialog(preset) {
    if (readOnly()) { S.preview = null; render(); }
    const r = S.repo;
    if (V.isDirty(r)) return toast('Hãy commit hoặc bỏ thay đổi trước khi merge.', true);
    const sources = [...Object.keys(r.branches).filter((b) => b !== r.head), ...Object.keys(r.remotes)];
    if (!sources.length) return toast('Chưa có nhánh khác để merge.', true);
    const sel = h('select', null, sources.map((s) => h('option', { value: s, selected: s === preset }, (r.remotes[s] ? '[nhận] ' : '') + s)));
    const info = h('div', { class: 'small muted', style: { marginTop: '8px' } });
    const upd = () => {
      const ab = aheadBehind(V.resolveRef(r, sel.value), V.headCommitId(r));
      info.textContent = `"${sel.value}" có ${ab.ahead} commit mà "${r.head}" chưa có.`;
    };
    sel.onchange = upd;
    upd();
    modal({
      title: `Merge vào "${r.head}"`,
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
      return toast(`Đã cập nhật "${r.head}" tới "${from}".`);
    }
    if (!(await ensureAuthor())) return;
    const msg = h('input', { value: `Merge "${from}" vào "${r.head}"` });
    if (!prep.conflicts.length) {
      return modal({
        title: 'Merge không có xung đột',
        body: h('div', null, h('label', { class: 'field' }, 'Mô tả', msg),
          h('div', { class: 'muted small', style: { margin: '10px 0 6px' } }, 'Các thay đổi sẽ được đưa vào:'),
          renderChanges(V.diffSnapshots(r.commits[prep.oursId].snapshot, prep.snapshot))),
        actions: [{ label: 'Huỷ' }, {
          label: 'Merge', primary: true,
          onClick: () => { V.finishMerge(r, prep, { snapshot: prep.snapshot, author: author(), message: msg.value, from }); afterSwitch(); toast('Đã merge'); },
        }],
      });
    }
    const choices = [];
    const show = (v) => {
      if (v === null || v === undefined) return '(đã xoá / trống)';
      if (Array.isArray(v)) return `[${v.length} mục]\n` + JSON.stringify(v, null, 1).slice(0, 600);
      if (typeof v === 'object') return v.blocks ? `Trang "${v.title}" — ${v.blocks.length} khối` : v.problems ? `Contest "${v.title}" — ${v.problems.length} bài` : `${V.blockName(v)}\n\n${v.text || v.code || v.url || v.statement || ''}`;
      return String(v);
    };
    const cards = prep.conflicts.map((c, i) => {
      const name = `cf${i}`;
      const isText = typeof c.ours === 'string' && typeof c.theirs === 'string';
      const manual = isText ? h('textarea', { class: 'mono', rows: 5, hidden: true, oninput: (e) => (choices[i] = { value: e.target.value }) }, `${c.ours}\n${c.theirs}`) : null;
      const opt = (val, label, content) => h('label', { class: 'opt' },
        h('input', { type: 'radio', name, onchange: () => { choices[i] = val === 'manual' ? { value: manual.value } : val; if (manual) manual.hidden = val !== 'manual'; } }),
        ' ', h('b', null, label), content !== undefined ? h('pre', null, content) : null);
      return h('div', { class: 'conflict' },
        h('div', null, h('b', null, `Xung đột ${i + 1}: `), c.label),
        h('div', { class: 'sides' }, opt('ours', `Giữ bản của bạn (${r.head})`, show(c.ours)), opt('theirs', `Lấy bản "${from}"`, show(c.theirs))),
        isText ? h('div', { style: { marginTop: '6px' } }, opt('manual', 'Tự gộp bằng tay'), manual) : null);
    });
    modal({
      title: `${prep.conflicts.length} xung đột cần giải quyết`, wide: true,
      body: h('div', null, h('p', { class: 'muted small' }, `"${r.head}" và "${from}" cùng sửa một chỗ. Chọn bản muốn giữ.`), cards, h('label', { class: 'field' }, 'Mô tả', msg)),
      actions: [{ label: 'Huỷ merge' }, {
        label: 'Hoàn tất merge', primary: true,
        onClick: () => {
          const missing = prep.conflicts.findIndex((_, i) => choices[i] === undefined);
          if (missing !== -1) throw new Error(`Chưa chọn cho xung đột ${missing + 1}.`);
          const snapshot = V.applyResolutions(prep.snapshot, prep.conflicts, choices);
          V.finishMerge(r, prep, { snapshot, author: author(), message: msg.value, from });
          afterSwitch();
          toast('Đã merge');
        },
      }],
    });
  }

  // ===================== Chia sẻ / nhập =====================
  async function makeBundle(branches) {
    const bundle = V.exportBundle(S.repo, { branches, author: author() });
    const refs = Assets.refs(bundle.commits);
    if (refs.length) bundle.assets = await Assets.pack(refs);
    return bundle;
  }

  async function shareDialog() {
    if (!(await ensureAuthor())) return;
    const r = S.repo;
    const checks = Object.keys(r.branches).sort().map((b) => h('label', { class: 'row small check-row' }, h('input', { type: 'checkbox', checked: true, value: b }), b));
    const out = h('div');
    const picked = () => {
      const names = checks.map((l) => l.querySelector('input')).filter((x) => x.checked).map((x) => x.value);
      if (!names.length) throw new Error('Chọn ít nhất một nhánh.');
      return names;
    };
    modal({
      title: 'Chia sẻ notebook',
      body: h('div', null,
        h('p', { class: 'small muted' }, 'Người nhận bấm "Nhập" để mở thành bản riêng, hoặc gộp vào notebook của họ như một nhánh rồi merge.'),
        V.isDirty(r) ? h('p', { class: 'badge warn' }, 'Thay đổi chưa commit sẽ không được chia sẻ.') : null,
        h('div', { class: 'field' }, 'Nhánh muốn chia sẻ', h('div', { class: 'check-list' }, checks)),
        h('div', { class: 'row' },
          btn('download', Platform.android ? 'Gửi file' : 'Lưu file .dsanote.json', async () => {
            const bundle = await makeBundle(picked());
            await Share.save(`${slugify(r.working.title)}.dsanote.json`, JSON.stringify(bundle));
          }, { class: 'primary' }),
          btn('link', 'Tạo link', async () => {
            const bundle = await makeBundle(picked());
            const code = await Share.encode(bundle);
            const base = Platform.name === 'web' ? location.origin + location.pathname : 'https://quocdat16610-web.github.io/tong-hop-kthuc/';
            const link = `${base}#share=${code}`;
            out.innerHTML = '';
            const ta = h('textarea', { class: 'mono', rows: 4, readOnly: true }, link);
            out.append(h('label', { class: 'field' }, `Link (${(link.length / 1024).toFixed(1)} KB)`, ta),
              link.length > 30000 ? h('p', { class: 'badge warn' }, 'Link khá dài (có ảnh/video?) — nên gửi file thay thế.') : null,
              btn('copy', 'Sao chép link', () => navigator.clipboard.writeText(link).then(() => toast('Đã sao chép')), { class: 'sm' }));
            ta.select();
          })),
        out),
      actions: [{ label: 'Đóng' }],
    });
  }

  function importDialog() {
    const file = h('input', { type: 'file', accept: '.json,.dsanote,application/json' });
    const paste = h('textarea', { class: 'mono', rows: 3, placeholder: 'Hoặc dán link chia sẻ vào đây' });
    modal({
      title: 'Nhập notebook',
      body: h('div', null, h('label', { class: 'field' }, 'File .dsanote.json', file), paste),
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
    try { return JSON.parse(text); } catch (_) { throw new Error('Không đọc được dữ liệu. Kiểm tra lại file/link.'); }
  }

  async function handleIncoming(text) {
    const bundle = V.validateBundle(await parseIncoming(text));
    const repos = await Store.list();
    const related = repos.filter((x) => x.id === bundle.repoId || x.upstream === bundle.repoId || Object.keys(bundle.commits).some((id) => x.commits[id]));
    const target = h('select', null, repos.map((x) => h('option', { value: x.id, selected: related[0] && x.id === related[0].id }, x.working.title)));
    const remoteName = h('input', { value: (bundle.sharedBy || 'ban').replace(/\s+/g, '-') });
    modal({
      title: `Nhập "${bundle.title}"`,
      body: h('div', null,
        h('p', null, 'Gửi bởi ', h('b', null, bundle.sharedBy || 'Ẩn danh'), ` · ${timeAgo(bundle.sharedAt || Date.now())} · ${Object.keys(bundle.branches).length} nhánh · ${Object.keys(bundle.commits).length} commit`),
        h('div', { class: 'change' }, h('b', null, 'Mở thành notebook riêng'), h('p', { class: 'small muted' }, 'Tạo bản sao đầy đủ lịch sử để bạn ghi chú tiếp hoặc làm bài.')),
        repos.length ? h('div', { class: 'change', style: { marginTop: '8px' } },
          h('b', null, 'Gộp vào notebook có sẵn'),
          h('p', { class: 'small muted' }, 'Các nhánh của họ hiện dạng "tên/nhánh" để bạn xem rồi merge.' + (related.length ? ' Đã tìm thấy notebook có chung lịch sử.' : '')),
          h('label', { class: 'field' }, 'Notebook', target), h('label', { class: 'field' }, 'Tên người gửi', remoteName)) : null),
      actions: [
        { label: 'Huỷ' },
        repos.length ? {
          label: 'Gộp vào notebook', onClick: async () => {
            await Assets.unpack(bundle.assets);
            const repo = S.repo && S.repo.id === target.value ? S.repo : await Store.get(target.value);
            const res = V.fetchBundle(repo, bundle, remoteName.value.trim() || 'ban');
            normalize(repo);
            await Store.put(repo);
            if (!S.repo || S.repo.id !== repo.id) await openRepo(repo.id);
            else render();
            toast(`Đã nhận ${res.added} commit mới: ${res.refs.join(', ')}`);
            if (!V.isDirty(S.repo)) mergeDialog(res.refs.find((x) => x.endsWith('/' + S.repo.head)) || res.refs[0]);
          },
        } : null,
        {
          label: 'Mở thành notebook riêng', primary: true, onClick: async () => {
            await Assets.unpack(bundle.assets);
            const repo = normalize(V.repoFromBundle(bundle));
            await Store.put(repo);
            await openRepo(repo.id);
            toast('Đã mở notebook');
          },
        },
      ],
    });
  }

  // ===================== Cài đặt =====================
  async function settingsDialog() {
    const name = h('input', { value: Settings.get('author') || '' });
    const theme = h('select', null, [['auto', 'Theo hệ thống'], ['light', 'Sáng'], ['dark', 'Tối']].map(([v, t]) => h('option', { value: v, selected: Settings.get('theme') === v }, t)));
    const mode = h('select', null, [['auto', Platform.desktop ? 'g++ trên máy (nếu có), không thì online' : 'Online'], ['online', 'Luôn chạy online (Compiler Explorer)']].map(([v, t]) => h('option', { value: v, selected: Settings.get('judgeMode') === v }, t)));
    const compiler = h('input', { value: Settings.get('compiler'), class: 'mono' });
    const flags = h('input', { value: Settings.get('cppFlags'), class: 'mono' });
    const gpp = h('input', { value: Settings.get('gppPath') || '', class: 'mono', placeholder: 'Để trống để tự tìm' });
    const info = h('div', { class: 'small' });
    const detect = async () => {
      Settings.set('gppPath', gpp.value.trim());
      info.textContent = 'Đang tìm g++…';
      const r = await Runner.detect(true);
      info.className = 'small ' + (r ? 'ok-text' : 'warn-text');
      info.textContent = r ? `Đã tìm thấy: ${r.version} (${r.path})` : 'Không tìm thấy g++. Code sẽ chạy online. Cài MinGW-w64 / MSYS2 (Windows), Xcode Command Line Tools (macOS) hoặc g++ (Linux), hoặc chọn file g++ bên dưới.';
    };
    const desktopBox = Platform.desktop ? h('div', { class: 'settings-sec' },
      h('h3', null, 'Trình biên dịch trên máy'), info,
      h('label', { class: 'field' }, 'Đường dẫn g++', gpp),
      h('div', { class: 'row' },
        btn('search', 'Tìm lại', detect, { class: 'sm' }),
        btn('file', 'Chọn file g++…', async () => { const p = await Platform.desktop.pickCompiler(); if (p) { gpp.value = p; detect(); } }, { class: 'sm' }))) : null;
    if (Platform.desktop) detect();
    modal({
      title: 'Cài đặt',
      body: h('div', null,
        h('label', { class: 'field' }, 'Tên của bạn', name),
        h('label', { class: 'field' }, 'Giao diện', theme),
        h('div', { class: 'settings-sec' }, h('h3', null, 'Chạy & chấm code C++'),
          h('label', { class: 'field' }, 'Nơi chạy code', mode),
          h('label', { class: 'field' }, 'Cờ biên dịch', flags),
          h('label', { class: 'field' }, 'Mã trình biên dịch online (Compiler Explorer, VD: g132, clang1701)', compiler)),
        desktopBox,
        h('p', { class: 'small muted' }, `Phiên bản: ${Platform.name === 'desktop' ? 'máy tính' : Platform.name === 'android' ? 'Android' : 'trình duyệt'}. Dữ liệu lưu trên máy này — hãy xuất file định kỳ để sao lưu.`)),
      actions: [{ label: 'Huỷ' }, {
        label: 'Lưu', primary: true,
        onClick: () => {
          Settings.set('author', name.value.trim());
          Settings.set('theme', theme.value);
          Settings.set('judgeMode', mode.value);
          Settings.set('compiler', compiler.value.trim() || 'g132');
          Settings.set('cppFlags', flags.value.trim());
          if (Platform.desktop) Settings.set('gppPath', gpp.value.trim());
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
    window.addEventListener('hashchange', checkShareHash);
  }
  boot().catch((e) => {
    $app.innerHTML = '';
    $app.appendChild(h('div', { class: 'home' }, h('h1', null, 'Không khởi động được'), h('p', null, e.message)));
  });
})();
