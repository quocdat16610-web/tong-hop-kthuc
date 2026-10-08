/*
 * ide.js — Chế độ IDE C++ (lấy cảm hứng từ Code::Blocks và Thonny):
 * nhiều tab file, cây thư mục, Build/Chạy (F9, Ctrl+F9, Ctrl+F10), console tương tác,
 * thông báo lỗi bấm để nhảy tới dòng, gỡ lỗi từng dòng bằng gdb với bảng biến và ngăn xếp gọi.
 */
(function (root) {
  'use strict';

  const { h, icon, btn, toast, confirmBox, promptBox, isDark, pickFiles } = root.UI;
  const { Platform, Files, Kv, Settings, Runner, Share } = root.Services;
  const D = Platform.desktop ? Platform.desktop.ide : null;
  const V = root.VCS;

  const NEW_CODE = `#include <bits/stdc++.h>
using namespace std;

int main() {
    int n;
    cout << "Nhap n: ";
    cin >> n;
    cout << "n * n = " << n * n << endl;
    return 0;
}
`;
  const MODE = 'text/x-c++src';

  const st = {
    tabs: [],
    active: null,
    folder: null,
    bottom: 'build',
    bottomOpen: true,
    explorer: window.innerWidth > 900,
    input: '',
    build: { status: '', messages: [], log: '' },
    out: [], // dòng console: { text, cls }
    proc: null, // { id } chương trình đang chạy tương tác
    debug: null, // { state, tabId, line, func, locals, frames }
    compiled: null, // { key, progId }
    loaded: false,
    appFiles: [],
  };
  let ctx = { render: () => {}, insertCode: null };
  let cm = null;
  let cmHost = null;
  const els = {};
  let dbgMark = null;
  let errMarks = [];

  // ---------- Tab & tài liệu ----------
  const activeTab = () => st.tabs.find((t) => t.id === st.active) || null;
  const isDirty = (t) => t.cleanGen === null || !t.doc.isClean(t.cleanGen);
  const dirname = (p) => (p || '').replace(/[\\/][^\\/]*$/, '');
  const newDoc = (text) => new CodeMirror.Doc(text, MODE);

  function addTab({ name, path = null, fileId = null, content = '', dirty = false, bps = [] }) {
    const doc = newDoc(content);
    const t = { id: V.newId(8), name, path, fileId, doc, cleanGen: dirty ? null : doc.changeGeneration(), bpLines: bps };
    st.tabs.push(t);
    return t;
  }

  function activate(id) {
    st.active = id;
    const t = activeTab();
    if (cm && t) {
      cm.swapDoc(t.doc);
      applyBps(t);
      cm.focus();
    }
    refreshTabs();
    refreshExplorer();
    saveSessionSoon();
  }

  function openText(name, content) {
    ensureLoaded().then(() => {
      const t = addTab({ name: name || 'main.cpp', content, dirty: true });
      activate(t.id);
    });
  }

  async function newFile() {
    const n = st.tabs.filter((t) => /^chua-dat-ten/.test(t.name)).length + 1;
    const t = addTab({ name: `chua-dat-ten-${n}.cpp`, content: NEW_CODE, dirty: true });
    activate(t.id);
  }

  async function openFiles() {
    if (D) {
      const files = await D.openFiles();
      files.forEach((f) => openPath(f.path, f.name, f.content));
    } else {
      const files = await pickFiles('.cpp,.cc,.c,.h,.hpp,.txt,.in,.out', true);
      for (const f of files) {
        const content = await Share.readFile(f);
        const id = V.newId(12);
        await Files.put({ id, name: f.name, content, updatedAt: Date.now() });
        const t = addTab({ name: f.name, fileId: id, content });
        activate(t.id);
      }
      loadAppFiles();
    }
  }

  function openPath(path, name, content) {
    const exist = st.tabs.find((t) => t.path === path);
    if (exist) return activate(exist.id);
    const t = addTab({ name, path, content });
    activate(t.id);
  }

  async function openFromTree(node) {
    try {
      const content = await D.read(node.path);
      openPath(node.path, node.name, content);
      if (window.innerWidth <= 900) { st.explorer = false; ctx.render(); }
    } catch (e) {
      toast(e.message, true);
    }
  }

  async function openAppFile(f) {
    const exist = st.tabs.find((t) => t.fileId === f.id);
    if (exist) return activate(exist.id);
    const t = addTab({ name: f.name, fileId: f.id, content: f.content });
    activate(t.id);
  }

  async function openFolder() {
    const f = await D.openFolder();
    if (!f) return;
    st.folder = f;
    st.explorer = true;
    saveSessionSoon();
    ctx.render();
  }

  async function save(t = activeTab()) {
    if (!t) return false;
    const content = t.doc.getValue();
    try {
      if (t.path) await D.write(t.path, content);
      else if (t.fileId) await Files.put({ id: t.fileId, name: t.name, content, updatedAt: Date.now() });
      else if (D) {
        const r = await D.saveAs(t.name, content);
        if (!r) return false;
        Object.assign(t, { path: r.path, name: r.name });
      } else {
        const name = await promptBox('Lưu file', 'Tên file', t.name);
        if (!name) return false;
        t.name = name;
        t.fileId = V.newId(12);
        await Files.put({ id: t.fileId, name, content, updatedAt: Date.now() });
        loadAppFiles();
      }
      t.cleanGen = t.doc.changeGeneration();
      refreshTabs();
      saveSessionSoon();
      toast(`Đã lưu ${t.name}`);
      return true;
    } catch (e) {
      toast(e.message, true);
      return false;
    }
  }

  async function saveAll() {
    for (const t of st.tabs) if (isDirty(t) && (t.path || t.fileId)) await save(t);
  }

  async function closeTab(id) {
    const t = st.tabs.find((x) => x.id === id);
    if (!t) return;
    if (isDirty(t) && !(await confirmBox('Đóng tab?', `"${t.name}" chưa được lưu. Đóng và bỏ thay đổi?`, 'Đóng', true))) return;
    const i = st.tabs.indexOf(t);
    st.tabs.splice(i, 1);
    if (st.active === id) {
      const next = st.tabs[Math.min(i, st.tabs.length - 1)];
      st.active = next ? next.id : null;
      if (next && cm) cm.swapDoc(next.doc);
      else if (cm) cm.swapDoc(newDoc(''));
    }
    ctx.render();
    saveSessionSoon();
  }

  async function renameTab(t) {
    if (t.path) return toast('File trên máy: dùng Lưu thành… để đổi tên.');
    const name = await promptBox('Đổi tên', 'Tên file', t.name);
    if (!name) return;
    t.name = name;
    if (t.fileId) await Files.put({ id: t.fileId, name, content: t.doc.getValue(), updatedAt: Date.now() });
    refreshTabs();
    loadAppFiles();
    saveSessionSoon();
  }

  async function loadAppFiles() {
    st.appFiles = (await Files.all()).sort((a, b) => b.updatedAt - a.updatedAt);
    refreshExplorer();
  }

  // ---------- Lưu phiên làm việc ----------
  let sessTimer = null;
  function saveSessionSoon() {
    clearTimeout(sessTimer);
    sessTimer = setTimeout(() => {
      Kv.set('ide-session', {
        tabs: st.tabs.map((t) => ({ name: t.name, path: t.path, fileId: t.fileId, content: t.doc.getValue(), dirty: isDirty(t), bps: bpLines(t) })),
        active: st.tabs.findIndex((t) => t.id === st.active),
        folder: st.folder ? st.folder.path : null,
        input: st.input,
      }).catch(() => {});
    }, 500);
  }

  let loading = null;
  function ensureLoaded() {
    if (!loading)
      loading = (async () => {
        const s = await Kv.get('ide-session', null).catch(() => null);
        if (s && s.tabs && s.tabs.length) {
          for (const t of s.tabs) {
            let content = t.content;
            if (t.path && !t.dirty && D) content = await D.read(t.path).catch(() => t.content);
            addTab({ ...t, content });
          }
          st.active = (st.tabs[s.active] || st.tabs[0]).id;
          st.input = s.input || '';
          if (s.folder && D) st.folder = await D.refreshFolder(s.folder).catch(() => null);
        } else {
          const t = addTab({ name: 'main.cpp', content: NEW_CODE, dirty: true });
          st.active = t.id;
        }
        await loadAppFiles();
        st.loaded = true;
      })();
    return loading;
  }

  // ---------- Điểm dừng (breakpoint) ----------
  const bpMarker = () => h('div', { class: 'bp-dot', title: 'Điểm dừng' });
  function bpLines(t) {
    // Tab chưa từng hiển thị: điểm dừng vẫn nằm trong danh sách đã lưu.
    if (!t.bpApplied) return t.bpLines || [];
    const out = [];
    t.doc.eachLine((lh) => { if (lh.gutterMarkers && lh.gutterMarkers['bp-gutter']) out.push(t.doc.getLineNumber(lh) + 1); });
    return out;
  }
  function applyBps(t) {
    if (t.bpApplied || !cm) return;
    (t.bpLines || []).forEach((l) => l - 1 < t.doc.lineCount() && cm.setGutterMarker(l - 1, 'bp-gutter', bpMarker()));
    t.bpApplied = true;
  }
  function toggleBp(line) {
    const t = activeTab();
    if (!t) return;
    const info = cm.lineInfo(line);
    const on = !(info.gutterMarkers && info.gutterMarkers['bp-gutter']);
    cm.setGutterMarker(line, 'bp-gutter', on ? bpMarker() : null);
    if (st.debug && st.debug.tabId === t.id) D.debugBreakpoint(line + 1, on);
    saveSessionSoon();
  }

  // ---------- Biên dịch ----------
  const ERR_RE = /^(.*?):(\d+):(?:(\d+):)?\s+(fatal error|error|warning|note|lỗi|cảnh báo):\s+(.*)$/;
  function parseMessages(text, tabName) {
    return String(text || '').split('\n').map((line) => {
      const m = ERR_RE.exec(line);
      if (!m) return null;
      const file = m[1].replace(/^.*[\\/]/, '');
      const kind = /error|lỗi/.test(m[4]) ? 'error' : m[4] === 'note' ? 'note' : 'warning';
      return { file: file === 'main.cpp' ? tabName : file, mine: file === 'main.cpp', line: Number(m[2]), col: Number(m[3] || 1), kind, text: m[5] };
    }).filter(Boolean);
  }

  function clearErrMarks() {
    errMarks.forEach(({ doc, lh }) => doc.removeLineClass(lh, 'background', 'ide-err-line'));
    errMarks = [];
  }

  async function localCompiler() {
    if (!Platform.desktop || Settings.get('judgeMode') === 'online') return null;
    return Runner.detect();
  }

  // Trả về progId (máy tính) hoặc 'online' hoặc null nếu lỗi.
  async function compile({ debug = false } = {}) {
    const t = activeTab();
    if (!t) return null;
    const info = await localCompiler();
    if (!info) return 'online';
    const source = t.doc.getValue();
    const flags = Settings.get('cppFlags') || '-O2 -std=c++17';
    const key = [source, flags, t.path].join('\u0000');
    if (!debug && st.compiled && st.compiled.key === key) return st.compiled.progId;
    st.build = { status: 'Đang biên dịch…', messages: [], log: '' };
    showBottom('build');
    clearErrMarks();
    const t0 = performance.now();
    const r = await Platform.desktop.compile({ source, gpp: info.path, flags, includeDir: t.path ? dirname(t.path) : undefined, debug, unbuffered: true });
    const ms = Math.round(performance.now() - t0);
    const log = String(r.ok ? r.warnings || '' : r.error || '').split('main.cpp').join(t.name);
    const messages = parseMessages(r.ok ? r.warnings : r.error, t.name);
    const nErr = messages.filter((m) => m.kind === 'error').length;
    const nWarn = messages.filter((m) => m.kind === 'warning').length;
    st.build = {
      ok: r.ok, log, messages,
      status: r.ok ? `Biên dịch xong: 0 lỗi, ${nWarn} cảnh báo (${ms} ms)` : `Biên dịch thất bại: ${nErr || 1} lỗi, ${nWarn} cảnh báo`,
    };
    messages.filter((m) => m.mine && m.kind === 'error').forEach((m) => {
      const lh = t.doc.addLineClass(m.line - 1, 'background', 'ide-err-line');
      if (lh) errMarks.push({ doc: t.doc, lh });
    });
    refreshBottom();
    if (!r.ok) {
      showBottom('build');
      return null;
    }
    if (!debug) {
      if (st.compiled) Platform.desktop.dispose(st.compiled.progId);
      st.compiled = { key, progId: r.id };
    }
    return r.id;
  }

  async function build() {
    const r = await compile();
    if (r === 'online') {
      st.build = { status: 'Bản này biên dịch online khi bấm Chạy (không có g++ trên máy).', messages: [], log: '' };
      refreshBottom();
      showBottom('build');
    }
  }

  // ---------- Chạy ----------
  function print(text, cls = '') {
    st.out.push({ text, cls });
    if (st.out.length > 4000) st.out.splice(0, st.out.length - 4000);
    refreshConsole();
  }
  function clearConsole() {
    st.out = [];
    refreshConsole();
  }

  async function run() {
    if (st.proc || st.debug) return toast('Đang có chương trình chạy. Bấm Dừng trước.');
    const t = activeTab();
    if (!t) return;
    const progId = await compile();
    if (!progId) return;
    clearConsole();
    showBottom('console');
    if (progId === 'online') {
      print(`Chạy ${t.name} (online, dùng dữ liệu ở tab Input)…\n`, 'sys');
      try {
        const r = await Runner.run(t.doc.getValue(), st.input);
        if (r.phase === 'compile') {
          st.build = { ok: false, status: 'Biên dịch thất bại', log: r.output, messages: parseMessages(r.output, t.name) };
          refreshBottom();
          showBottom('build');
          return;
        }
        if (r.stdout) print(r.stdout);
        if (r.stderr) print(r.stderr, 'err');
        print(`\nKết thúc · mã thoát ${r.exitCode} · ${Math.round(r.timeMs || 0)} ms${r.timedOut ? ' · quá thời gian' : ''}\n`, 'sys');
      } catch (e) {
        print(`Không chạy được: ${e.message}\nCần Internet để chạy online.\n`, 'err');
      }
      return;
    }
    print(`▶ ${t.name}\n`, 'sys');
    const id = await D.start(progId);
    st.proc = { id };
    refreshToolbar();
    refreshBottom();
    setTimeout(() => els.stdin && els.stdin.focus(), 50);
  }

  async function stop() {
    if (st.proc) await D.kill(st.proc.id);
    if (st.debug) await D.debugStop();
  }

  // ---------- Gỡ lỗi ----------
  async function debugGo() {
    if (st.debug) {
      if (st.debug.state === 'stopped') D.debugControl('continue');
      return;
    }
    if (st.proc) return toast('Đang có chương trình chạy. Bấm Dừng trước.');
    if (!D) return toast('Gỡ lỗi từng dòng chỉ có ở bản máy tính.', true);
    const info = await localCompiler();
    if (!info) return toast('Cần g++ trên máy để gỡ lỗi (xem Cài đặt).', true);
    const gdb = await D.findGdb(info.path);
    if (!gdb) return toast('Không tìm thấy gdb. Cài gdb (MinGW/MSYS2 trên Windows, "sudo apt install gdb" trên Linux).', true);
    const t = activeTab();
    const progId = await compile({ debug: true });
    if (!progId || progId === 'online') return;
    st.debug = { state: 'starting', tabId: t.id, locals: [], frames: [], line: null, func: '' };
    clearConsole();
    print(`Gỡ lỗi ${t.name} — input lấy từ tab Input${bpLines(t).length ? '' : ', dừng ở đầu hàm main'}.\n`, 'sys');
    showBottom('console');
    ctx.render();
    try {
      await D.debugStart({ progId, input: st.input, breakpoints: bpLines(t), gppPath: info.path });
    } catch (e) {
      st.debug = null;
      toast(e.message, true);
      ctx.render();
    }
  }
  const debugStep = (action) => st.debug && st.debug.state === 'stopped' && D.debugControl(action);

  function setDebugLine(line) {
    if (dbgMark) { dbgMark.doc.removeLineClass(dbgMark.lh, 'background', 'ide-dbg-line'); dbgMark = null; }
    const t = st.debug && st.tabs.find((x) => x.id === st.debug.tabId);
    if (!t || !line) return;
    if (st.active !== t.id) activate(t.id);
    const lh = t.doc.addLineClass(line - 1, 'background', 'ide-dbg-line');
    dbgMark = { doc: t.doc, lh };
    cm.scrollIntoView({ line: line - 1, ch: 0 }, 120);
  }

  function onEvent(ev) {
    if (ev.type === 'out' || ev.type === 'err') {
      if (st.proc && ev.id === st.proc.id) print(ev.text, ev.type === 'err' ? 'err' : '');
      return;
    }
    if (ev.type === 'exit') {
      if (st.proc && ev.id === st.proc.id) {
        print(`\nKết thúc · mã thoát ${ev.code}${ev.signal ? ` (${ev.signal})` : ''} · ${ev.timeMs} ms\n`, ev.code === 0 ? 'sys' : 'err');
        st.proc = null;
        refreshToolbar();
        refreshBottom();
      }
      return;
    }
    if (!st.debug) return;
    if (ev.type === 'running') {
      st.debug.state = 'running';
      refreshDebug();
      refreshToolbar();
    } else if (ev.type === 'stopped') {
      Object.assign(st.debug, ev, { state: 'stopped' });
      setOutput(ev.output);
      if (ev.signal) print(`\nChương trình bị lỗi: ${ev.signal} tại dòng ${ev.line || '?'}\n`, 'err');
      setDebugLine(ev.line);
      refreshDebug();
      refreshToolbar();
    } else if (ev.type === 'exited') {
      setOutput(ev.output);
      print(`\nChương trình kết thúc · mã thoát ${ev.code}\n`, 'sys');
    } else if (ev.type === 'ended') {
      if (ev.error) print(`\n${ev.error}\n`, 'err');
      st.debug = null;
      setDebugLine(null);
      ctx.render();
    } else if (ev.type === 'log') print(ev.text + '\n', 'err');
  }
  if (D) D.onEvent(onEvent);

  // Khi gỡ lỗi, output của chương trình được ghi ra file và đọc lại sau mỗi bước.
  function setOutput(text) {
    const head = st.out.filter((x) => x.cls === 'sys' || x.cls === 'err');
    st.out = [head[0] || { text: '', cls: 'sys' }, { text: text || '', cls: '' }];
    refreshConsole();
  }

  // ---------- Giao diện ----------
  function ensureEditor() {
    if (cm) return;
    cmHost = h('div', { class: 'ide-editor' });
    cm = CodeMirror(cmHost, {
      value: '', mode: MODE, theme: isDark() ? 'material-darker' : 'default',
      lineNumbers: true, gutters: ['bp-gutter', 'CodeMirror-linenumbers'], indentUnit: 4, tabSize: 4, indentWithTabs: false,
      matchBrackets: true, autoCloseBrackets: true,
      extraKeys: { Tab: (c) => (c.somethingSelected() ? c.indentSelection('add') : c.replaceSelection('    ')), 'Shift-Tab': (c) => c.indentSelection('subtract') },
    });
    cm.on('gutterClick', (_c, line) => toggleBp(line));
    cm.on('changes', () => {
      refreshTabs();
      saveSessionSoon();
    });
  }

  function setTheme() {
    if (cm) cm.setOption('theme', isDark() ? 'material-darker' : 'default');
  }

  function showBottom(tab) {
    st.bottom = tab;
    st.bottomOpen = true;
    refreshBottom();
  }

  function view() {
    ensureEditor();
    const wrap = h('div', { class: 'ide' + (st.explorer ? ' explorer-open' : '') + (st.debug ? ' debugging' : '') });
    els.toolbar = h('div', { class: 'ide-toolbar' });
    els.explorer = h('aside', { class: 'ide-explorer' });
    els.tabs = h('div', { class: 'ide-tabs' });
    els.bottom = h('div', { class: 'ide-bottom' + (st.bottomOpen ? '' : ' closed') });
    els.debug = h('aside', { class: 'ide-debug' });
    wrap.append(els.toolbar, h('div', { class: 'ide-main' },
      els.explorer,
      h('div', { class: 'ide-center' }, els.tabs, cmHost, els.bottom),
      st.debug ? els.debug : null));
    if (!st.loaded) {
      cmHost.classList.add('loading');
      ensureLoaded().then(() => { cmHost.classList.remove('loading'); ctx.render(); });
    } else {
      const t = activeTab();
      if (t && cm.getDoc() !== t.doc) { cm.swapDoc(t.doc); applyBps(t); }
    }
    refreshToolbar();
    refreshExplorer();
    refreshTabs();
    refreshBottom();
    refreshDebug();
    requestAnimationFrame(() => cm.refresh());
    return wrap;
  }

  function refreshToolbar() {
    const el = els.toolbar;
    if (!el) return;
    const running = !!st.proc;
    const dbg = st.debug;
    const stopped = dbg && dbg.state === 'stopped';
    el.innerHTML = '';
    const g = (...kids) => h('div', { class: 'tb-group' }, kids.filter(Boolean));
    const parts = [
      h('button', { class: 'ghost icon-only', title: 'Cây thư mục', onclick: () => { st.explorer = !st.explorer; ctx.render(); } }, icon('toc', 18)),
      g(btn('plus', 'Mới', newFile, { compact: true, title: 'File mới (Ctrl+N)' }),
        btn('file', 'Mở', openFiles, { compact: true, title: 'Mở file (Ctrl+O)' }),
        D ? btn('book', 'Thư mục', openFolder, { compact: true, title: 'Mở thư mục' }) : null,
        btn('download', 'Lưu', () => save(), { compact: true, title: 'Lưu (Ctrl+S)' })),
      g(btn('check', 'Build', build, { compact: true, title: 'Biên dịch (Ctrl+F9)', disabled: running || !!dbg }),
        btn('play', 'Chạy', run, { compact: true, class: 'primary', title: 'Build và chạy (F9)', disabled: running || !!dbg }),
        btn('x', 'Dừng', stop, { compact: true, title: 'Dừng chương trình', disabled: !running && !dbg })),
      D ? g(btn('sim', dbg ? 'Tiếp tục' : 'Gỡ lỗi', debugGo, { compact: true, title: dbg ? 'Chạy tới điểm dừng kế tiếp (F8)' : 'Bắt đầu gỡ lỗi (F8)', disabled: running || (dbg && !stopped), class: dbg ? 'on' : '' }),
        btn('down', 'Dòng kế', () => debugStep('next'), { compact: true, title: 'Chạy dòng kế tiếp (F7)', disabled: !stopped }),
        btn('chevron', 'Vào hàm', () => debugStep('step'), { compact: true, title: 'Bước vào hàm (Shift+F7)', disabled: !stopped }),
        btn('up', 'Ra khỏi hàm', () => debugStep('finish'), { compact: true, title: 'Chạy hết hàm hiện tại (Ctrl+F7)', disabled: !stopped })) : null,
      h('span', { class: 'grow' }),
      h('span', { class: 'ide-status small muted' }, dbg ? (stopped ? `Dừng ở dòng ${dbg.line || '?'} (${dbg.func})` : 'Đang chạy…') : running ? 'Chương trình đang chạy' : ''),
      ctx.insertCode && activeTab() ? btn('plus', 'Đưa vào sổ tay', () => ctx.insertCode(activeTab().name, activeTab().doc.getValue()), { compact: true, class: 'ghost', title: 'Chèn code này thành khối Code trong trang đang mở' }) : null,
    ];
    el.append(...parts.filter(Boolean));
  }

  function refreshTabs() {
    const el = els.tabs;
    if (!el) return;
    el.innerHTML = '';
    st.tabs.forEach((t) => {
      const tab = h('div', {
        class: 'ide-tab' + (t.id === st.active ? ' on' : ''), title: t.path || t.name,
        onclick: () => activate(t.id), ondblclick: () => renameTab(t),
        onauxclick: (e) => { if (e.button === 1) closeTab(t.id); },
      }, h('span', { class: 'nm' }, t.name), isDirty(t) ? h('span', { class: 'dirty-dot', title: 'Chưa lưu' }, '●') : null,
      h('button', { class: 'tab-x', title: 'Đóng (Ctrl+W)', onclick: (e) => { e.stopPropagation(); closeTab(t.id); } }, icon('x', 12)));
      el.appendChild(tab);
    });
    el.appendChild(h('button', { class: 'ghost icon-only tab-new', title: 'Tab mới (Ctrl+N)', onclick: newFile }, icon('plus', 14)));
    const on = el.querySelector('.ide-tab.on');
    if (on) on.scrollIntoView({ block: 'nearest', inline: 'nearest' });
  }

  function treeNode(node, depth) {
    if (node.dir) {
      const open = node.open !== false;
      const kids = h('div', { hidden: !open }, node.children.map((c) => treeNode(c, depth + 1)));
      return h('div', null,
        h('button', { class: 'tree-item dir', style: { paddingLeft: `${8 + depth * 12}px` }, onclick: (e) => { node.open = !open; kids.hidden = open; node.open = !open; e.currentTarget.classList.toggle('closed', open); } }, icon('chevron', 12), node.name),
        kids);
    }
    const isOpen = st.tabs.some((t) => t.path === node.path && t.id === st.active);
    return h('button', { class: 'tree-item' + (isOpen ? ' on' : ''), style: { paddingLeft: `${20 + depth * 12}px` }, title: node.path, onclick: () => openFromTree(node) }, icon('code', 12), node.name);
  }

  function refreshExplorer() {
    const el = els.explorer;
    if (!el) return;
    el.innerHTML = '';
    el.appendChild(h('div', { class: 'ex-sec' }, 'Đang mở'));
    st.tabs.forEach((t) => el.appendChild(h('button', { class: 'tree-item' + (t.id === st.active ? ' on' : ''), onclick: () => activate(t.id) }, icon('file', 12), t.name, isDirty(t) ? ' ●' : '')));
    if (D) {
      el.appendChild(h('div', { class: 'ex-sec row' }, h('span', { class: 'grow' }, st.folder ? st.folder.name : 'Thư mục'),
        st.folder ? h('button', { class: 'ghost icon-only sm', title: 'Làm mới', onclick: async () => { st.folder = await D.refreshFolder(st.folder.path); refreshExplorer(); } }, icon('history', 12)) : null));
      if (st.folder) st.folder.children.forEach((n) => el.appendChild(treeNode(n, 0)));
      else el.appendChild(h('div', { class: 'pad' }, btn('book', 'Mở thư mục…', openFolder, { class: 'sm' })));
    }
    el.appendChild(h('div', { class: 'ex-sec' }, 'Tệp trong app'));
    if (!st.appFiles.length) el.appendChild(h('div', { class: 'small muted pad' }, D ? 'File bạn lưu trong app (không ra ổ đĩa) sẽ hiện ở đây.' : 'Bấm Lưu để giữ file trong app.'));
    st.appFiles.forEach((f) => el.appendChild(h('div', { class: 'tree-row' },
      h('button', { class: 'tree-item grow', onclick: () => openAppFile(f) }, icon('code', 12), f.name),
      h('button', { class: 'ghost icon-only sm', title: 'Xuất file', onclick: () => Share.save(f.name, f.content, 'text/plain') }, icon('download', 12)),
      h('button', {
        class: 'ghost icon-only sm danger', title: 'Xoá',
        onclick: async () => {
          if (!(await confirmBox('Xoá file?', `Xoá "${f.name}" khỏi app?`, 'Xoá', true))) return;
          await Files.remove(f.id);
          st.tabs.filter((t) => t.fileId === f.id).forEach((t) => (t.fileId = null));
          loadAppFiles();
        },
      }, icon('trash', 12)))));
  }

  function refreshBottom() {
    const el = els.bottom;
    if (!el) return;
    el.className = 'ide-bottom' + (st.bottomOpen ? '' : ' closed');
    el.innerHTML = '';
    const tab = (k, label) => h('button', { class: 'tab' + (st.bottom === k ? ' on' : ''), onclick: () => showBottom(k) }, label);
    const nErr = (st.build.messages || []).filter((m) => m.kind === 'error').length;
    el.appendChild(h('div', { class: 'tabs-line' },
      tab('build', `Thông báo build${nErr ? ` (${nErr})` : ''}`), tab('console', st.proc ? 'Console ●' : 'Console'), tab('input', 'Input'),
      h('span', { class: 'grow' }),
      st.bottom === 'console' ? h('button', { class: 'ghost sm', onclick: clearConsole }, 'Xoá') : null,
      h('button', { class: 'ghost icon-only sm', title: st.bottomOpen ? 'Thu gọn' : 'Mở rộng', onclick: () => { st.bottomOpen = !st.bottomOpen; refreshBottom(); requestAnimationFrame(() => cm.refresh()); } }, icon(st.bottomOpen ? 'down' : 'up', 14))));
    if (!st.bottomOpen) return;
    const body = h('div', { class: 'ide-bottom-body' });
    el.appendChild(body);
    if (st.bottom === 'build') {
      const b = st.build;
      body.appendChild(h('div', { class: 'build-status ' + (b.ok === false ? 'bad' : b.ok ? 'ok' : '') }, b.status || 'Bấm Build (Ctrl+F9) hoặc Chạy (F9).'));
      (b.messages || []).forEach((m) => body.appendChild(h('button', {
        class: 'msg-row ' + m.kind,
        onclick: () => {
          if (!m.mine) return;
          cm.focus();
          cm.setCursor({ line: m.line - 1, ch: m.col - 1 });
          cm.scrollIntoView(null, 80);
        },
      }, h('span', { class: 'msg-kind' }, m.kind === 'error' ? 'lỗi' : m.kind === 'warning' ? 'cảnh báo' : 'ghi chú'), h('span', { class: 'msg-loc' }, `${m.file}:${m.line}`), h('span', { class: 'msg-text' }, m.text))));
      if (b.log) body.appendChild(h('details', null, h('summary', { class: 'small muted' }, 'Log đầy đủ'), h('pre', { class: 'build-log' }, b.log)));
    } else if (st.bottom === 'console') {
      els.console = h('pre', { class: 'console' });
      body.appendChild(els.console);
      els.stdin = null;
      if (st.proc) {
        els.stdin = h('input', {
          class: 'stdin-line mono', placeholder: 'Gõ input rồi Enter…',
          onkeydown: (e) => {
            if (e.key === 'Enter') {
              const text = e.target.value + '\n';
              print(text, 'in');
              D.input(st.proc.id, text);
              e.target.value = '';
            } else if (e.key === 'd' && e.ctrlKey) {
              e.preventDefault();
              D.eof(st.proc.id);
              print('^D\n', 'sys');
            }
          },
        });
        body.appendChild(h('div', { class: 'row stdin-row' }, h('span', { class: 'small muted' }, '>'), els.stdin));
      }
      refreshConsole();
    } else {
      body.appendChild(h('div', { class: 'small muted' }, D ? 'Dữ liệu vào dùng khi gỡ lỗi (và khi chạy online). Khi chạy thường, gõ trực tiếp trong Console.' : 'Dữ liệu vào (stdin) cho chương trình.'));
      body.appendChild(h('textarea', { class: 'mono ide-input', placeholder: 'VD:\n5\n1 2 3 4 5', oninput: (e) => { st.input = e.target.value; saveSessionSoon(); } }, st.input));
    }
  }

  function refreshConsole() {
    const el = els.console;
    if (!el) return;
    el.innerHTML = '';
    if (!st.out.length) el.appendChild(h('span', { class: 'muted' }, 'Output của chương trình hiện ở đây.'));
    st.out.forEach((o) => el.appendChild(o.cls ? h('span', { class: 'c-' + o.cls }, o.text) : document.createTextNode(o.text)));
    el.scrollTop = el.scrollHeight;
  }

  function refreshDebug() {
    const el = els.debug;
    if (!el || !st.debug) return;
    const d = st.debug;
    el.innerHTML = '';
    el.append(
      h('div', { class: 'ex-sec' }, 'Biến'),
      d.locals && d.locals.length
        ? h('table', { class: 'tbl vars' }, h('tbody', null, d.locals.map((v) => h('tr', null, h('td', { class: 'mono' }, v.name, v.arg ? h('span', { class: 'muted' }, ' (tham số)') : null), h('td', { class: 'mono val' }, v.value)))))
        : h('div', { class: 'small muted pad' }, d.state === 'stopped' ? 'Không có biến cục bộ.' : 'Đang chạy…'),
      h('div', { class: 'ex-sec' }, 'Ngăn xếp gọi'),
      h('div', null, (d.frames || []).map((f, i) => h('div', { class: 'frame' + (i === 0 ? ' on' : '') }, h('span', { class: 'mono' }, f.func), h('span', { class: 'muted small' }, ` dòng ${f.line || '?'}`)))),
      h('div', { class: 'small muted pad' }, 'F7: dòng kế · Shift+F7: vào hàm · Ctrl+F7: ra khỏi hàm · F8: tiếp tục · bấm lề trái để đặt điểm dừng'));
  }

  // ---------- Phím tắt (giống Code::Blocks) ----------
  document.addEventListener('keydown', (e) => {
    if (!document.querySelector('.ide') || document.querySelector('.modal-bg')) return;
    const k = e.key;
    const c = e.ctrlKey || e.metaKey;
    let fn = null;
    if (k === 'F9' && !c) fn = run;
    else if (k === 'F9' && c) fn = build;
    else if (k === 'F10' && c) fn = run;
    else if (k === 'F8' && e.shiftKey) fn = stop;
    else if (k === 'F8') fn = debugGo;
    else if (k === 'F7' && e.shiftKey) fn = () => debugStep('step');
    else if (k === 'F7' && c) fn = () => debugStep('finish');
    else if (k === 'F7') fn = () => debugStep('next');
    else if (k === 'F5') fn = () => cm && toggleBp(cm.getCursor().line);
    else if (c && k.toLowerCase() === 's') fn = e.shiftKey ? saveAll : () => save();
    else if (c && k.toLowerCase() === 'n') fn = newFile;
    else if (c && k.toLowerCase() === 'o') fn = openFiles;
    else if (c && k.toLowerCase() === 'w') fn = () => st.active && closeTab(st.active);
    if (!fn) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    fn();
  }, true);

  root.IDE = {
    init: (c) => (ctx = { ...ctx, ...c }),
    view, openText, setTheme,
    busy: () => !!(st.proc || st.debug),
  };
})(typeof globalThis !== 'undefined' ? globalThis : this);
