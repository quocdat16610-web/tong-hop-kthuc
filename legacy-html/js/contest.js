/*
 * contest.js — Khối "Bài tập" (đề + test + code chuẩn + sinh test), nộp bài, chấm, và chế độ Contest.
 */
(function (root) {
  'use strict';

  const { h, icon, btn, toast, modal, confirmBox, renderMarkdown, codeEditor, timeAgo, pickFiles, slugify } = root.UI;
  const { Subs, Runs, Share, Runner, Assets } = root.Services;
  const J = root.Judge;
  const V = root.VCS;
  let ctx = null; // do app.js cung cấp: { S, repo, snap, saveSoon, render, author, ensureAuthor, readOnly }

  const CPP_TEMPLATE = `#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);

    return 0;
}
`;
  const GEN_TEMPLATE = `// Generator: đọc số seed từ bàn phím, in ra MỘT bộ test (input).
// App chạy generator với seed = 1, 2, 3, … rồi dùng code chuẩn để tạo output.
#include <bits/stdc++.h>
using namespace std;

int main() {
    long long seed;
    cin >> seed;
    mt19937_64 rng(seed);
    auto rnd = [&](long long l, long long r) {
        return uniform_int_distribution<long long>(l, r)(rng);
    };
    int n = rnd(1, 10);
    cout << n << '\\n';
    for (int i = 0; i < n; i++) cout << rnd(1, 100) << ' ';
    cout << '\\n';
}
`;
  const STATEMENT_TEMPLATE = `Mô tả đề bài ở đây.

### Dữ liệu vào
- ...

### Kết quả
- ...

### Giới hạn
- ...`;
  const CHECKERS = [
    ['tokens', 'So từng từ (bỏ qua khoảng trắng thừa)'],
    ['exact', 'Khớp chính xác từng dòng'],
    ['float:1e-6', 'Số thực, sai số 1e-6'],
    ['float:1e-9', 'Số thực, sai số 1e-9'],
  ];

  function newProblem() {
    return { title: 'Bài mới', statement: STATEMENT_TEMPLATE, timeLimit: 1000, memoryLimit: 256, checker: 'tokens', reference: CPP_TEMPLATE, generator: GEN_TEMPLATE, genCount: 10, tests: [] };
  }

  function allProblems(snap) {
    const out = [];
    snap.pages.forEach((p) => p.blocks.forEach((b) => b.type === 'problem' && out.push({ page: p, block: b })));
    return out;
  }
  const findProblem = (snap, id) => allProblems(snap).find((x) => x.block.id === id);

  // ---------- Bản nháp bài làm ----------
  const draftKey = (pid) => `draft:${ctx.repo().id}:${pid}`;
  const getDraft = (pid) => { try { return localStorage.getItem(draftKey(pid)); } catch (_) { return null; } };
  const setDraft = (pid, v) => { try { localStorage.setItem(draftKey(pid), v); } catch (_) { /* đầy bộ nhớ */ } };

  // ---------- Hiển thị kết quả ----------
  function verdictEl(r) {
    const ok = r.verdict === 'AC';
    return h('span', { class: 'verdict ' + (ok ? 'ok' : r.verdict === 'NT' ? '' : 'bad') }, J.verdictText(r));
  }
  const pre = (label, text) => h('div', { class: 'io' }, h('div', { class: 'io-h' }, label), h('pre', null, text === undefined || text === '' ? '(trống)' : String(text).slice(0, 4000)));

  function resultBox(r, { showData, where }) {
    const box = h('div', { class: 'judge-result' },
      h('div', { class: 'row' }, verdictEl(r),
        r.timeMs !== undefined && r.verdict !== 'CE' ? h('span', { class: 'muted small' }, `${Math.round(r.timeMs)} ms`) : null,
        r.verdict === 'AC' && r.tests ? h('span', { class: 'muted small' }, `${r.tests} test`) : null,
        where ? h('span', { class: 'muted small grow', style: { textAlign: 'right' } }, where) : null));
    if (r.verdict === 'CE') box.appendChild(pre('Thông báo của trình biên dịch', r.message));
    else if (r.verdict === 'NT') box.appendChild(h('div', { class: 'muted small' }, 'Bài này chưa có test. Tác giả cần thêm test trong chế độ sửa.'));
    else if (r.verdict !== 'AC' && showData)
      box.appendChild(h('div', { class: 'io-grid' }, pre('Input', r.input), pre('Output đúng', r.expected), pre('Output của bạn', r.got),
        r.stderr ? pre('stderr', r.stderr) : null));
    return box;
  }

  async function submit(b, code, { contestId, samplesOnly, onProgress }) {
    const be = await Runner.backend();
    const tests = samplesOnly ? b.tests.filter((t) => t.sample) : b.tests;
    const r = await J.judge({ source: code, tests, timeLimit: Number(b.timeLimit) || 1000, checker: b.checker }, be, onProgress);
    if (!samplesOnly && r.verdict !== 'NT') {
      await Subs.put({
        id: V.newId(), repoId: ctx.repo().id, contestId: contestId || null, problemId: b.id, user: ctx.author(),
        time: Date.now(), verdict: r.verdict, test: r.test || null, timeMs: Math.round(r.timeMs || 0), code,
      });
    }
    // Chỉ cho xem dữ liệu khi sai ở test mẫu (giống Codeforces).
    const failedIdx = r.test ? r.test - 1 : -1;
    const showData = samplesOnly || (failedIdx >= 0 && tests[failedIdx] && tests[failedIdx].sample);
    return { r, showData, where: be.name };
  }

  async function mySubs({ problemId, contestId }) {
    const user = ctx.author();
    const all = await Subs.all();
    return all
      .filter((s) => s.repoId === ctx.repo().id && s.user === user && (problemId ? s.problemId === problemId : true) && (contestId === undefined || s.contestId === contestId))
      .sort((a, b) => b.time - a.time);
  }

  // ---------- Khối bài tập: chế độ làm bài ----------
  function problemView(el, b, opts = {}) {
    const { contestId = null, letter, onSubmitted } = opts;
    el.appendChild(h('div', { class: 'prob-head' },
      h('h3', { class: 'prob-title', id: opts.anchor }, letter ? `${letter}. ` : '', b.title || 'Bài tập'),
      h('div', { class: 'prob-limits' }, `Giới hạn thời gian: ${(Number(b.timeLimit) || 1000) / 1000} giây`, h('br'), `Giới hạn bộ nhớ: ${b.memoryLimit || 256} MB`)));
    el.appendChild(renderMarkdown(b.statement || ''));
    const samples = (b.tests || []).filter((t) => t.sample);
    if (samples.length) {
      el.appendChild(h('div', { class: 'prob-sec' }, 'Ví dụ'));
      samples.forEach((t) => el.appendChild(h('div', { class: 'sample' },
        sampleCell('Input', t.input), sampleCell('Output', t.output))));
    }

    const solve = h('div', { class: 'solve' });
    el.appendChild(solve);
    const editor = codeEditor(getDraft(b.id) || CPP_TEMPLATE, 'cpp', (v) => setDraft(b.id, v));
    const out = h('div');
    const where = h('span', { class: 'muted small' });
    Runner.backend().then((be) => (where.textContent = 'Chấm bằng: ' + be.name)).catch(() => {});
    const progress = h('span', { class: 'muted small' });
    const runBtn = btn('play', 'Chạy test mẫu', () => go(true));
    const subBtn = btn('upload', 'Nộp bài', () => go(false), { class: 'primary' });
    const list = h('div', { class: 'sub-list' });
    solve.append(h('div', { class: 'prob-sec' }, 'Bài làm (C++)'), editor.el,
      h('div', { class: 'row', style: { marginTop: '8px' } }, runBtn, subBtn, progress, h('span', { class: 'grow' }), where), out, list);
    refreshList();

    async function go(samplesOnly) {
      if (!samplesOnly && !(await ctx.ensureAuthor())) return;
      runBtn.disabled = subBtn.disabled = true;
      out.innerHTML = '';
      progress.textContent = 'Đang biên dịch…';
      try {
        const res = await submit(b, editor.getValue(), {
          contestId, samplesOnly,
          onProgress: (i, n) => (progress.textContent = `Đang chấm test ${i}/${n}…`),
        });
        out.appendChild(resultBox(res.r, res));
        if (!samplesOnly) {
          refreshList();
          onSubmitted && onSubmitted(res.r);
        }
      } catch (e) {
        out.appendChild(h('div', { class: 'judge-result' }, h('span', { class: 'verdict bad' }, 'Không chấm được'), h('pre', null, e.message)));
      }
      progress.textContent = '';
      runBtn.disabled = subBtn.disabled = false;
    }

    async function refreshList() {
      const subs = (await mySubs({ problemId: b.id, contestId: contestId || null })).slice(0, 8);
      list.innerHTML = '';
      if (!subs.length) return;
      list.appendChild(h('table', { class: 'tbl' },
        h('thead', null, h('tr', null, h('th', null, 'Lúc nộp'), h('th', null, 'Kết quả'), h('th', null, 'Thời gian'), h('th'))),
        h('tbody', null, subs.map((s) => h('tr', null,
          h('td', null, timeAgo(s.time)), h('td', null, verdictEl(s)), h('td', null, s.verdict === 'CE' ? '' : `${s.timeMs} ms`),
          h('td', null, h('button', { class: 'link', onclick: () => { editor.setValue(s.code); setDraft(b.id, s.code); } }, 'Mở lại code')))))));
    }
  }

  function sampleCell(label, text) {
    return h('div', { class: 'sample-cell' },
      h('div', { class: 'sample-h' }, label, h('button', { class: 'link', onclick: () => navigator.clipboard.writeText(text || '').then(() => toast('Đã sao chép')) }, 'Sao chép')),
      h('pre', null, text || ''));
  }

  // ---------- Khối bài tập: chế độ tác giả ----------
  const editTab = {};
  function problemEdit(el, b, change) {
    b.tests = b.tests || [];
    const tab = editTab[b.id] || 'statement';
    const tabs = [['statement', 'Đề bài'], ['tests', `Test (${b.tests.length})`], ['reference', 'Code chuẩn'], ['generator', 'Sinh test']];
    const body = h('div', { class: 'tab-body' });
    el.appendChild(h('div', { class: 'tabs-line' }, tabs.map(([k, label]) =>
      h('button', { class: 'tab' + (k === tab ? ' on' : ''), onclick: () => { editTab[b.id] = k; ctx.render(); } }, label))));
    el.appendChild(body);
    const status = h('div', { class: 'small muted', style: { marginTop: '6px' } });
    const busy = async (label, fn) => {
      status.textContent = label;
      try { await fn(); } catch (e) { status.textContent = ''; toast(e.message, true); return; }
    };

    if (tab === 'statement') {
      const ta = h('textarea', { class: 'mono', rows: 14, oninput: (e) => change('statement', e.target.value) }, b.statement || '');
      body.append(
        h('label', { class: 'field' }, 'Tên bài', h('input', { value: b.title || '', oninput: (e) => change('title', e.target.value) })),
        h('div', { class: 'row' },
          h('label', { class: 'field' }, 'Giới hạn thời gian (ms)', h('input', { type: 'number', min: 100, step: 100, value: b.timeLimit || 1000, oninput: (e) => change('timeLimit', Number(e.target.value) || 1000) })),
          h('label', { class: 'field' }, 'Giới hạn bộ nhớ (MB)', h('input', { type: 'number', min: 16, value: b.memoryLimit || 256, oninput: (e) => change('memoryLimit', Number(e.target.value) || 256) })),
          h('label', { class: 'field grow' }, 'Cách so output', h('select', { onchange: (e) => change('checker', e.target.value) },
            CHECKERS.map(([v, t]) => h('option', { value: v, selected: (b.checker || 'tokens') === v }, t))))),
        h('div', { class: 'row', style: { justifyContent: 'space-between' } }, h('span', { class: 'small muted' }, 'Đề bài (Markdown)'),
          btn('image', 'Chèn ảnh', async () => {
            const [f] = await pickFiles('image/*');
            if (!f) return;
            const ref = await Assets.add(f);
            ta.setRangeText(`\n![](${ref})\n`, ta.selectionStart, ta.selectionEnd, 'end');
            change('statement', ta.value);
          }, { class: 'sm' })),
        ta);
    }

    if (tab === 'tests') {
      const samples = b.tests.filter((t) => t.sample).length;
      body.appendChild(h('div', { class: 'row' },
        h('span', { class: 'small muted grow' }, `${b.tests.length} test, ${samples} test mẫu hiện trong đề. Test không phải mẫu được giữ kín khi chấm.`),
        btn('plus', 'Thêm test', () => { b.tests.push({ input: '', output: '', sample: b.tests.length < 2 }); ctx.saveSoon(); ctx.render(); }, { class: 'sm' }),
        btn('play', 'Tạo output bằng code chuẩn', () => busy('Đang chạy code chuẩn…', async () => {
          if (!b.tests.length) throw new Error('Chưa có test nào.');
          const be = await Runner.backend();
          const outs = await J.runAll(b.reference || '', b.tests.map((t) => t.input), be, { onProgress: (i, n) => (status.textContent = `Code chuẩn: ${i}/${n}`) });
          outs.forEach((o, i) => (b.tests[i].output = o));
          ctx.saveSoon();
          ctx.render();
          toast(`Đã tạo output cho ${outs.length} test`);
        }), { class: 'sm' }),
        b.tests.length ? btn('trash', 'Xoá hết', async () => {
          if (await confirmBox('Xoá hết test?', `Xoá ${b.tests.length} test của bài này?`, 'Xoá', true)) { b.tests = []; ctx.saveSoon(); ctx.render(); }
        }, { class: 'sm danger' }) : null));
      body.appendChild(status);
      b.tests.forEach((t, i) => {
        const big = (t.input || '').length + (t.output || '').length > 20000;
        const area = (field) => big
          ? h('pre', { class: 'test-big' }, (t[field] || '').slice(0, 2000) + ((t[field] || '').length > 2000 ? `\n… (${t[field].length} ký tự)` : ''))
          : h('textarea', { class: 'mono', rows: Math.min(8, Math.max(2, (t[field] || '').split('\n').length)), oninput: (e) => { t[field] = e.target.value; ctx.saveSoon(); } }, t[field] || '');
        body.appendChild(h('div', { class: 'test-item' },
          h('div', { class: 'row' }, h('b', null, `Test ${i + 1}`),
            h('label', { class: 'row small' }, h('input', { type: 'checkbox', checked: !!t.sample, onchange: (e) => { t.sample = e.target.checked; ctx.saveSoon(); } }), 'Test mẫu'),
            h('span', { class: 'grow' }),
            h('button', { class: 'ghost icon-only sm', title: 'Xoá test', onclick: () => { b.tests.splice(i, 1); ctx.saveSoon(); ctx.render(); } }, icon('trash'))),
          h('div', { class: 'io-grid two' },
            h('div', null, h('div', { class: 'io-h' }, 'Input'), area('input')),
            h('div', null, h('div', { class: 'io-h' }, 'Output'), area('output')))));
      });
    }

    if (tab === 'reference') {
      const out = h('div');
      body.append(
        h('p', { class: 'small muted' }, 'Code chuẩn dùng để tạo output cho test. Khi xuất đề cho thí sinh, code chuẩn được bỏ đi.'),
        codeEditor(b.reference || CPP_TEMPLATE, 'cpp', (v) => change('reference', v)).el,
        h('div', { class: 'row', style: { marginTop: '8px' } },
          btn('play', 'Chấm thử code chuẩn với các test', () => busy('Đang chấm…', async () => {
            const be = await Runner.backend();
            const r = await J.judge({ source: b.reference || '', tests: b.tests, timeLimit: Number(b.timeLimit) || 1000, checker: b.checker }, be, (i, n) => (status.textContent = `Test ${i}/${n}`));
            status.textContent = '';
            out.innerHTML = '';
            out.appendChild(resultBox(r, { showData: true, where: be.name }));
          })), status),
        out);
    }

    if (tab === 'generator') {
      const count = h('input', { type: 'number', min: 1, max: 200, value: b.genCount || 10, style: { width: '90px' }, oninput: (e) => change('genCount', Number(e.target.value) || 10) });
      body.append(
        h('p', { class: 'small muted' }, 'Viết chương trình C++ in ra một bộ input ngẫu nhiên từ seed. App chạy generator với seed 1…N, rồi chạy code chuẩn để có output. Test mới được thêm vào cuối danh sách.'),
        codeEditor(b.generator || GEN_TEMPLATE, 'cpp', (v) => change('generator', v)).el,
        h('div', { class: 'row', style: { marginTop: '8px' } }, 'Số test:', count,
          btn('play', 'Sinh test', () => busy('Đang sinh input…', async () => {
            const n = Math.max(1, Math.min(200, Number(count.value) || 10));
            const be = await Runner.backend();
            const start = b.tests.length + 1;
            const seeds = Array.from({ length: n }, (_, i) => String(start + i));
            const inputs = await J.runAll(b.generator || '', seeds, be, { onProgress: (i, k) => (status.textContent = `Generator: ${i}/${k}`) });
            const outs = await J.runAll(b.reference || '', inputs, be, { onProgress: (i, k) => (status.textContent = `Code chuẩn: ${i}/${k}`) });
            inputs.forEach((input, i) => b.tests.push({ input, output: outs[i], sample: false }));
            ctx.saveSoon();
            editTab[b.id] = 'tests';
            ctx.render();
            toast(`Đã sinh ${n} test`);
          }), { class: 'primary' }), status));
    }
  }

  // ---------- Danh sách contest ----------
  function contestsDialog() {
    const snap = ctx.snap();
    snap.contests = snap.contests || [];
    const ro = ctx.readOnly();
    const body = h('div');
    const m = modal({ title: 'Contest', wide: true, body, actions: [{ label: 'Đóng', primary: true }] });
    fill();

    function fill() {
      body.innerHTML = '';
      const problems = allProblems(snap);
      if (!snap.contests.length) body.appendChild(h('p', { class: 'muted' }, 'Chưa có contest nào.'));
      else body.appendChild(h('table', { class: 'tbl' },
        h('thead', null, h('tr', null, h('th', null, 'Contest'), h('th', null, 'Số bài'), h('th', null, 'Thời gian'), h('th'))),
        h('tbody', null, snap.contests.map((c) => h('tr', null,
          h('td', null, h('b', null, c.title)),
          h('td', null, c.problems.filter((id) => findProblem(snap, id)).length),
          h('td', null, `${c.durationMin} phút`),
          h('td', { class: 'row', style: { justifyContent: 'flex-end' } },
            btn('play', 'Vào thi', () => { m.close(); openContest(c.id); }, { class: 'sm primary' }),
            ro ? null : btn('edit', 'Sửa', () => form(c), { class: 'sm' }),
            btn('download', 'Xuất đề cho thí sinh', () => exportForStudents(c), { class: 'sm', title: 'File đề không kèm code chuẩn' }),
            ro ? null : btn('trash', '', async () => {
              if (!(await confirmBox('Xoá contest?', `Xoá contest "${c.title}"? (Bài tập vẫn còn trong trang.)`, 'Xoá', true))) return;
              snap.contests.splice(snap.contests.indexOf(c), 1);
              ctx.saveSoon();
              fill();
            }, { class: 'sm ghost', title: 'Xoá' })))))));
      if (ro) return;
      body.appendChild(h('div', { class: 'row', style: { marginTop: '14px' } },
        btn('plus', 'Tạo contest mới', () => form(null), { class: 'primary' }),
        problems.length ? btn('trophy', `Tạo nhanh từ tất cả ${problems.length} bài`, () => {
          snap.contests.push({ id: V.newId(12), title: `${snap.title || 'Contest'} — luyện tập`, durationMin: 120, problems: problems.map((p) => p.block.id) });
          ctx.saveSoon();
          fill();
          toast('Đã tạo contest');
        }) : null));
      if (!problems.length) body.appendChild(h('p', { class: 'small muted' }, 'Notebook chưa có khối "Bài tập". Thêm bài tập vào trang trước rồi tạo contest.'));
    }

    function form(c) {
      const problems = allProblems(snap);
      const title = h('input', { value: c ? c.title : 'Contest mới' });
      const dur = h('input', { type: 'number', min: 5, value: c ? c.durationMin : 120 });
      const picks = problems.map((p) => h('label', { class: 'row small check-row' },
        h('input', { type: 'checkbox', value: p.block.id, checked: c ? c.problems.includes(p.block.id) : true }),
        h('span', null, p.block.title || 'Bài tập'), h('span', { class: 'muted' }, `— trang "${p.page.title}"`)));
      modal({
        title: c ? 'Sửa contest' : 'Tạo contest',
        body: h('div', null, h('label', { class: 'field' }, 'Tên contest', title), h('label', { class: 'field' }, 'Thời gian làm bài (phút)', dur),
          h('div', { class: 'field' }, 'Các bài (đánh chữ A, B, C… theo thứ tự trong notebook)', h('div', { class: 'check-list' }, picks))),
        actions: [{ label: 'Huỷ' }, {
          label: c ? 'Lưu' : 'Tạo', primary: true,
          onClick: () => {
            const ids = picks.map((l) => l.querySelector('input')).filter((x) => x.checked).map((x) => x.value);
            if (!ids.length) throw new Error('Chọn ít nhất một bài.');
            const data = { title: title.value.trim() || 'Contest', durationMin: Math.max(5, Number(dur.value) || 120), problems: ids };
            if (c) Object.assign(c, data);
            else snap.contests.push({ id: V.newId(12), ...data });
            ctx.saveSoon();
            fill();
          },
        }],
      });
    }
  }

  async function exportForStudents(c) {
    if (!(await ctx.ensureAuthor())) return;
    const snap = ctx.snap();
    const blocks = c.problems.map((id) => findProblem(snap, id)).filter(Boolean).map((p) => ({ ...V.clone(p.block), reference: '', generator: '' }));
    const snapshot = {
      title: c.title,
      description: `Đề thi gồm ${blocks.length} bài, làm trong ${c.durationMin} phút.`,
      pages: [{
        id: V.newId(12), title: c.title, chapter: 'Contest',
        blocks: [
          { id: V.newId(12), type: 'heading', level: 1, text: c.title },
          { id: V.newId(12), type: 'markdown', text: `Bấm nút **Contest** trên thanh công cụ → **Vào thi** → **Bắt đầu làm bài**. Thời gian: ${c.durationMin} phút.\n\nLàm xong, mở contest và bấm **Xuất kết quả** để gửi lại cho người ra đề.` },
          ...blocks,
        ],
      }],
      contests: [V.clone(c)],
    };
    const bundle = V.bundleFromSnapshot(snapshot, { author: ctx.author() });
    const refs = Assets.refs(snapshot);
    if (refs.length) bundle.assets = await Assets.pack(refs);
    await Share.save(`de-thi-${slugify(c.title)}.dsanote.json`, JSON.stringify(bundle));
    toast('Đã xuất đề thi (không kèm code chuẩn)');
  }

  // ---------- Màn hình thi ----------
  let timer = null;
  function cleanup() { clearInterval(timer); timer = null; }

  function openContest(id) {
    ctx.S.contest = { id, tab: 'problems', idx: 0 };
    ctx.render();
  }

  const runId = (cid, user) => `${cid}|${user}`;
  const fmtDur = (ms) => {
    const s = Math.max(0, Math.floor(ms / 1000));
    return `${String(Math.floor(s / 3600)).padStart(2, '0')}:${String(Math.floor((s % 3600) / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
  };

  function contestView() {
    cleanup();
    const wrap = h('div', { class: 'contest' });
    build(wrap);
    return wrap;
  }

  async function build(wrap) {
    const st = ctx.S.contest;
    const snap = ctx.snap();
    const c = (snap.contests || []).find((x) => x.id === st.id);
    const exit = () => { cleanup(); ctx.S.contest = null; ctx.render(); };
    if (!c) { exit(); return; }
    const probs = c.problems.map((id) => findProblem(snap, id)).filter(Boolean).map((p) => p.block);
    const user = ctx.author();
    const run = await Runs.get(runId(c.id, user));
    const dur = c.durationMin * 60000;
    const subs = run ? (await mySubs({ contestId: c.id })).filter((s) => s.problemId) : [];

    const clock = h('span', { class: 'clock' });
    const tick = () => {
      if (!run) { clock.textContent = `${c.durationMin} phút`; return; }
      const left = run.startedAt + dur - Date.now();
      clock.textContent = left > 0 ? `Còn lại ${fmtDur(left)}` : 'Đã kết thúc';
      clock.classList.toggle('ended', left <= 0);
    };
    tick();
    timer = setInterval(tick, 1000);

    const tab = (k, label) => h('button', { class: 'tab' + (st.tab === k ? ' on' : ''), onclick: () => { st.tab = k; ctx.render(); } }, label);
    wrap.innerHTML = '';
    wrap.appendChild(h('div', { class: 'contest-bar' },
      btn('back', 'Thoát', exit, { class: 'ghost' }),
      h('div', { class: 'contest-title' }, c.title), clock, h('span', { class: 'grow' }),
      btn('download', 'Xuất kết quả', () => exportResult(c, run, subs), { disabled: !run, title: 'Gửi file này cho người ra đề' }),
      btn('upload', 'Nhập kết quả', () => importResults(c), { title: 'Nhập file kết quả của thí sinh để xếp hạng' })));
    wrap.appendChild(h('div', { class: 'tabs-line' }, tab('problems', 'Đề bài'), tab('subs', `Bài nộp (${subs.length})`), tab('standings', 'Bảng xếp hạng')));

    const body = h('div', { class: 'contest-body' });
    wrap.appendChild(body);

    if (st.tab === 'problems') {
      if (!run) {
        body.appendChild(h('div', { class: 'contest-start' },
          h('h2', null, c.title),
          h('p', null, `${probs.length} bài · ${c.durationMin} phút · thí sinh: `, h('b', null, user || '(chưa đặt tên)')),
          h('p', { class: 'muted small' }, 'Đồng hồ bắt đầu chạy khi bạn bấm nút bên dưới. Xếp hạng theo luật ICPC: số bài giải được, sau đó tổng thời gian + 20 phút cho mỗi lần nộp sai.'),
          btn('play', 'Bắt đầu làm bài', async () => {
            if (!(await ctx.ensureAuthor())) return;
            await Runs.put({ id: runId(c.id, ctx.author()), contestId: c.id, repoId: ctx.repo().id, user: ctx.author(), startedAt: Date.now(), imported: false });
            ctx.render();
          }, { class: 'primary' })));
        return;
      }
      const status = (pid) => {
        const s = subs.filter((x) => x.problemId === pid);
        return s.some((x) => x.verdict === 'AC') ? 'ok' : s.length ? 'bad' : '';
      };
      const side = h('div', { class: 'prob-nav' }, probs.map((p, i) => h('button', {
        class: 'prob-nav-item' + (i === st.idx ? ' on' : '') + ' ' + status(p.id),
        onclick: () => { st.idx = i; ctx.render(); },
      }, h('span', { class: 'letter' }, J.letter(i)), h('span', { class: 'grow' }, p.title || 'Bài tập'),
      status(p.id) === 'ok' ? icon('check') : status(p.id) === 'bad' ? icon('x') : null)));
      const main = h('div', { class: 'prob-main block' });
      const p = probs[Math.min(st.idx, probs.length - 1)];
      if (p) problemView(main, p, { contestId: c.id, letter: J.letter(probs.indexOf(p)), onSubmitted: () => ctx.render() });
      body.appendChild(h('div', { class: 'contest-grid' }, side, main));
    }

    if (st.tab === 'subs') {
      if (!subs.length) body.appendChild(h('p', { class: 'muted' }, 'Chưa có bài nộp.'));
      else body.appendChild(h('table', { class: 'tbl' },
        h('thead', null, h('tr', null, h('th', null, '#'), h('th', null, 'Thời điểm'), h('th', null, 'Bài'), h('th', null, 'Kết quả'), h('th', null, 'Thời gian chạy'))),
        h('tbody', null, subs.map((s, i) => {
          const idx = c.problems.indexOf(s.problemId);
          const inTime = s.time <= run.startedAt + dur;
          return h('tr', null, h('td', null, subs.length - i),
            h('td', null, inTime ? fmtDur(s.time - run.startedAt) : 'ngoài giờ'),
            h('td', null, idx >= 0 ? `${J.letter(idx)}. ${(probs.find((p) => p.id === s.problemId) || {}).title || ''}` : '?'),
            h('td', null, verdictEl(s)), h('td', null, s.verdict === 'CE' ? '' : `${s.timeMs} ms`));
        }))));
    }

    if (st.tab === 'standings') {
      const imported = (await Runs.all()).filter((r) => r.contestId === c.id && r.imported && !(run && r.user === user));
      const participants = [...(run ? [{ user, startedAt: run.startedAt, subs }] : []), ...imported];
      if (!participants.length) {
        body.appendChild(h('p', { class: 'muted' }, 'Chưa có ai tham gia. Thí sinh làm bài xong bấm "Xuất kết quả" và gửi file cho bạn; bạn bấm "Nhập kết quả" để xếp hạng.'));
        return;
      }
      const rows = J.standings(c, participants);
      body.appendChild(h('div', { class: 'tbl-wrap' }, h('table', { class: 'tbl standings' },
        h('thead', null, h('tr', null, h('th', null, 'Hạng'), h('th', null, 'Thí sinh'), h('th', null, 'Giải'), h('th', null, 'Penalty'),
          c.problems.map((_, i) => h('th', { class: 'c' }, J.letter(i))))),
        h('tbody', null, rows.map((r) => h('tr', { class: r.user === user ? 'me' : '' },
          h('td', null, r.rank), h('td', null, r.user), h('td', null, h('b', null, r.solved)), h('td', null, r.penalty),
          c.problems.map((pid) => {
            const cell = r.cells[pid];
            if (cell.solved) return h('td', { class: 'c ok' }, cell.tries ? `+${cell.tries}` : '+', h('div', { class: 'small' }, fmtDur(cell.minutes * 60000).slice(0, 5)));
            return h('td', { class: 'c bad' }, cell.tries ? `−${cell.tries}` : '');
          })))))));
    }
  }

  async function exportResult(c, run, subs) {
    if (!run) return;
    const data = {
      format: 'dsa-contest-result', version: 1, contestId: c.id, contestTitle: c.title, user: run.user, startedAt: run.startedAt,
      subs: subs.map((s) => ({ problemId: s.problemId, time: s.time, verdict: s.verdict, test: s.test, timeMs: s.timeMs })),
    };
    await Share.save(`ket-qua-${slugify(run.user)}.json`, JSON.stringify(data));
  }

  async function importResults(c) {
    const files = await pickFiles('.json,application/json', true);
    let n = 0;
    for (const f of files) {
      try {
        const d = JSON.parse(await Share.readFile(f));
        if (d.format !== 'dsa-contest-result') throw new Error(`${f.name}: không phải file kết quả`);
        if (d.contestId !== c.id) throw new Error(`${f.name}: kết quả của contest khác ("${d.contestTitle}")`);
        if (!d.user || !Array.isArray(d.subs) || typeof d.startedAt !== 'number') throw new Error(`${f.name}: dữ liệu hỏng`);
        await Runs.put({ id: `${c.id}|${d.user}|imported`, contestId: c.id, user: String(d.user), startedAt: d.startedAt, subs: d.subs, imported: true });
        n++;
      } catch (e) {
        toast(e.message, true);
      }
    }
    if (n) {
      toast(`Đã nhập ${n} kết quả`);
      ctx.S.contest.tab = 'standings';
      ctx.render();
    }
  }

  root.ContestUI = {
    init: (c) => (ctx = c), newProblem, allProblems, problemView, problemEdit, contestsDialog, contestView, openContest, cleanup, CPP_TEMPLATE,
  };
})(typeof globalThis !== 'undefined' ? globalThis : this);
