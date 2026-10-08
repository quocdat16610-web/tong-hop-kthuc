/*
 * sim.js — Bộ chạy mô phỏng thuật toán do người dùng tự viết.
 *
 * An toàn: code mô phỏng (có thể đến từ notebook người khác chia sẻ) chạy trong
 *   <iframe sandbox="allow-scripts"> (origin rỗng → không đọc được dữ liệu của app)
 *   và bên trong đó là một Web Worker có giới hạn thời gian (chống vòng lặp vô hạn).
 *
 * Mô hình: script chạy hết một lượt, mọi thao tác trên cấu trúc dữ liệu được "ghi hình"
 * thành các khung (frame); sau đó trình phát cho phép tua tới/lui từng bước.
 */
(function (root) {
  'use strict';

  // =====================================================================
  // 1) Phần chạy trong Worker: API `viz` ghi lại các bước.
  // =====================================================================
  function simWorkerMain(self) {
    const MAX_FRAMES = 5000;
    const structs = [];
    const frames = [];
    const logs = [];
    let vars = {};
    let auto = true;
    let dirty = false;

    const fmt = (x) => {
      if (x === Infinity) return '∞';
      if (x === -Infinity) return '-∞';
      if (x === null || x === undefined) return '';
      if (typeof x === 'object') return JSON.stringify(x);
      return String(x);
    };
    const clone = (x) => JSON.parse(JSON.stringify(x, (k, v) => (v === Infinity ? '∞' : v === -Infinity ? '-∞' : v)));

    function frame(note) {
      if (frames.length >= MAX_FRAMES)
        throw new Error(`Quá ${MAX_FRAMES} bước mô phỏng. Hãy giảm kích thước dữ liệu hoặc dùng viz.auto(false) + viz.step().`);
      frames.push({ s: structs.map((x) => x._snap()), vars: clone(vars), note: note || '', logN: logs.length });
      structs.forEach((x) => (x.hl = {}));
      dirty = false;
    }
    const tick = (note) => {
      dirty = true;
      if (auto) frame(note);
    };
    const list = (x) => (Array.isArray(x) ? x.flat(Infinity) : [x]);

    class ArrayViz {
      constructor(values, opts = {}) {
        this.name = opts.name || 'a';
        this.v = Array.from(values || []);
        this.st = {};
        this.hl = {};
        this.ptr = {};
        this.bars = !!opts.bars;
        structs.push(this);
      }
      get length() { return this.v.length; }
      get(i) { return this.v[i]; }
      values() { return this.v.slice(); }
      set(i, x) { this.v[i] = x; this.hl[i] = 'set'; tick(`${this.name}[${i}] = ${fmt(x)}`); }
      swap(i, j) {
        [this.v[i], this.v[j]] = [this.v[j], this.v[i]];
        this.hl[i] = this.hl[j] = 'swap';
        tick(`Đổi chỗ ${this.name}[${i}] ↔ ${this.name}[${j}]`);
      }
      compare(i, j) {
        const a = this.v[i];
        const b = this.v[j];
        this.hl[i] = this.hl[j] = 'compare';
        tick(`So sánh ${this.name}[${i}]=${fmt(a)} với ${this.name}[${j}]=${fmt(b)}`);
        return a < b ? -1 : a > b ? 1 : 0;
      }
      highlight(idx, state = 'active', note) { list(idx).forEach((i) => (this.hl[i] = state)); tick(note); }
      mark(idx, state = 'done', note) {
        list(idx).forEach((i) => (state ? (this.st[i] = state) : delete this.st[i]));
        tick(note);
      }
      markRange(l, r, state = 'done', note) {
        for (let i = l; i <= r; i++) state ? (this.st[i] = state) : delete this.st[i];
        tick(note);
      }
      unmark(idx) { this.mark(idx, null); }
      pointer(name, i) { if (i === null || i === undefined) delete this.ptr[name]; else this.ptr[name] = i; dirty = true; }
      push(x) { this.v.push(x); this.hl[this.v.length - 1] = 'set'; tick(`Thêm ${fmt(x)} vào cuối ${this.name}`); }
      pop() { const x = this.v.pop(); delete this.st[this.v.length]; tick(`Lấy ${fmt(x)} ra khỏi cuối ${this.name}`); return x; }
      _snap() { return { kind: 'array', name: this.name, v: clone(this.v), st: { ...this.st }, hl: { ...this.hl }, ptr: { ...this.ptr }, bars: this.bars }; }
    }

    class GridViz {
      constructor(a, b, c, opts) {
        if (Array.isArray(a)) {
          this.v = a.map((r) => Array.from(r));
          opts = b || {};
        } else {
          this.v = Array.from({ length: a }, () => Array.from({ length: b }, () => (c === undefined ? '' : c)));
          opts = opts || {};
        }
        this.name = opts.name || 'grid';
        this.showValues = opts.showValues !== false;
        this.st = {};
        this.hl = {};
        structs.push(this);
      }
      get rows() { return this.v.length; }
      get cols() { return this.v[0] ? this.v[0].length : 0; }
      inside(r, c) { return r >= 0 && c >= 0 && r < this.rows && c < this.cols; }
      get(r, c) { return this.v[r][c]; }
      set(r, c, x, note) { this.v[r][c] = x; this.hl[`${r},${c}`] = 'set'; tick(note || `${this.name}[${r}][${c}] = ${fmt(x)}`); }
      mark(r, c, state = 'visited', note) {
        if (state) this.st[`${r},${c}`] = state;
        else delete this.st[`${r},${c}`];
        tick(note);
      }
      state(r, c) { return this.st[`${r},${c}`] || null; }
      highlight(r, c, state = 'current', note) { this.hl[`${r},${c}`] = state; tick(note); }
      _snap() { return { kind: 'grid', name: this.name, v: clone(this.v), st: { ...this.st }, hl: { ...this.hl }, showValues: this.showValues }; }
    }

    class GraphViz {
      constructor(opts = {}) {
        this.name = opts.name || 'G';
        this.directed = !!opts.directed;
        this.layout = opts.layout || 'circle';
        this.root = opts.root;
        let nodes = opts.nodes === undefined ? [] : opts.nodes;
        if (typeof nodes === 'number') nodes = Array.from({ length: nodes }, (_, i) => i);
        this.nodes = new Map();
        nodes.forEach((n) => this._add(n));
        this.edges = [];
        (opts.edges || []).forEach((e) => this._edge(e));
        this.hl = {};
        structs.push(this);
      }
      _add(n) {
        const o = typeof n === 'object' && n !== null ? n : { id: n };
        this.nodes.set(String(o.id), { id: o.id, label: fmt(o.label !== undefined ? o.label : o.id), x: o.x, y: o.y, st: null, sub: '' });
      }
      _edge(e) {
        const [u, v, w] = Array.isArray(e) ? e : [e.u, e.v, e.w];
        [u, v].forEach((x) => !this.nodes.has(String(x)) && this._add(x));
        this.edges.push({ u, v, w: w === undefined ? '' : fmt(w), st: null });
      }
      _findEdge(u, v) {
        return this.edges.find((e) => (String(e.u) === String(u) && String(e.v) === String(v)) ||
          (!this.directed && String(e.u) === String(v) && String(e.v) === String(u)));
      }
      neighbors(u) {
        const out = [];
        this.edges.forEach((e) => {
          if (String(e.u) === String(u)) out.push(e.v);
          else if (!this.directed && String(e.v) === String(u)) out.push(e.u);
        });
        return out;
      }
      weight(u, v) { const e = this._findEdge(u, v); return e ? Number(e.w) : undefined; }
      addNode(n, note) { this._add(n); tick(note || `Thêm đỉnh ${fmt(typeof n === 'object' ? n.id : n)}`); }
      addEdge(u, v, w, note) { this._edge([u, v, w]); tick(note || `Thêm cạnh ${fmt(u)} → ${fmt(v)}`); }
      removeEdge(u, v, note) {
        const e = this._findEdge(u, v);
        if (e) this.edges.splice(this.edges.indexOf(e), 1);
        tick(note || `Xoá cạnh ${fmt(u)} — ${fmt(v)}`);
      }
      visit(n, state = 'visited', note) {
        const node = this.nodes.get(String(n));
        if (node) node.st = state;
        tick(note || (state ? `Thăm đỉnh ${fmt(n)}` : ''));
      }
      highlight(n, state = 'current', note) { this.hl[String(n)] = state; tick(note); }
      edge(u, v, state = 'active', note) {
        const e = this._findEdge(u, v);
        if (e) e.st = state;
        tick(note || `Cạnh ${fmt(u)} — ${fmt(v)}`);
      }
      label(n, text) { const node = this.nodes.get(String(n)); if (node) node.sub = fmt(text); dirty = true; }
      _positions() {
        const nodes = [...this.nodes.values()];
        const pos = {};
        if (this.layout === 'tree' && nodes.length) {
          const kids = {};
          const hasParent = new Set();
          this.edges.forEach((e) => {
            (kids[String(e.u)] = kids[String(e.u)] || []).push(String(e.v));
            hasParent.add(String(e.v));
          });
          const rootId = this.root !== undefined ? String(this.root) : String((nodes.find((n) => !hasParent.has(String(n.id))) || nodes[0]).id);
          const seen = new Set();
          let leaf = 0;
          let maxDepth = 0;
          const place = (id, d) => {
            seen.add(id);
            maxDepth = Math.max(maxDepth, d);
            const ch = (kids[id] || []).filter((c) => !seen.has(c) && this.nodes.has(c));
            let x;
            if (!ch.length) x = leaf++;
            else {
              const xs = ch.map((c) => place(c, d + 1));
              x = (xs[0] + xs[xs.length - 1]) / 2;
            }
            pos[id] = { x, y: d };
            return x;
          };
          place(rootId, 0);
          nodes.forEach((n) => !seen.has(String(n.id)) && place(String(n.id), 0));
          const W = Math.max(1, leaf - 1);
          Object.values(pos).forEach((p) => {
            p.x = leaf <= 1 ? 0.5 : p.x / W;
            p.y = maxDepth ? p.y / maxDepth : 0;
          });
          return { pos, depth: maxDepth };
        }
        nodes.forEach((n, i) => {
          pos[String(n.id)] = n.x !== undefined
            ? { x: n.x, y: n.y }
            : { x: 0.5 + 0.5 * Math.cos((2 * Math.PI * i) / nodes.length - Math.PI / 2), y: 0.5 + 0.5 * Math.sin((2 * Math.PI * i) / nodes.length - Math.PI / 2) };
        });
        return { pos, depth: -1 };
      }
      _snap() {
        const { pos, depth } = this._positions();
        return {
          kind: 'graph', name: this.name, directed: this.directed, depth,
          nodes: [...this.nodes.values()].map((n) => ({ ...n, id: fmt(n.id), ...pos[String(n.id)], hl: this.hl[String(n.id)] || null })),
          edges: this.edges.map((e) => ({ ...e, u: fmt(e.u), v: fmt(e.v) })),
        };
      }
    }

    class ListViz {
      constructor(mode, values, opts = {}) {
        this.mode = mode;
        this.name = opts.name || (mode === 'stack' ? 'stack' : 'queue');
        this.v = Array.from(values || []);
        this.hl = {};
        structs.push(this);
      }
      get length() { return this.v.length; }
      size() { return this.v.length; }
      empty() { return this.v.length === 0; }
      values() { return this.v.slice(); }
      push(x) {
        this.v.push(x);
        this.hl[this.v.length - 1] = 'set';
        tick(this.mode === 'stack' ? `push(${fmt(x)})` : `Đưa ${fmt(x)} vào cuối hàng đợi`);
      }
      pop() {
        if (!this.v.length) throw new Error(`${this.name} rỗng, không thể lấy ra`);
        const x = this.mode === 'stack' ? this.v.pop() : this.v.shift();
        tick(this.mode === 'stack' ? `pop() → ${fmt(x)}` : `Lấy ${fmt(x)} ra khỏi đầu hàng đợi`);
        return x;
      }
      top() { return this.v[this.v.length - 1]; }
      front() { return this.v[0]; }
      _snap() { return { kind: 'list', mode: this.mode, name: this.name, v: clone(this.v), hl: { ...this.hl } }; }
    }

    const viz = {
      array: (values, opts) => new ArrayViz(values, opts),
      grid: (a, b, c, d) => new GridViz(a, b, c, d),
      graph: (opts) => new GraphViz(opts),
      tree: (opts) => new GraphViz({ ...opts, layout: 'tree', directed: true }),
      stack: (values, opts) => new ListViz('stack', values, opts),
      queue: (values, opts) => new ListViz('queue', values, opts),
      step: (note) => frame(note),
      auto: (on) => { auto = on !== false; },
      var: (name, value) => {
        if (value === undefined) delete vars[name];
        else vars[name] = value;
        dirty = true;
      },
      log: (...args) => {
        logs.push(args.map(fmt).join(' '));
        dirty = true;
      },
    };

    self.onmessage = (ev) => {
      const { code, input } = ev.data;
      const readNumbers = () => (String(input || '').match(/-?\d+(\.\d+)?/g) || []).map(Number);
      const fakeConsole = { log: viz.log, info: viz.log, warn: viz.log, error: viz.log };
      let error = null;
      try {
        // eslint-disable-next-line no-new-func
        const fn = new Function('viz', 'INPUT', 'readNumbers', 'console', '"use strict";\n' + code);
        frame('Bắt đầu');
        fn(viz, String(input || ''), readNumbers, fakeConsole);
        if (dirty || frames.length === 1) frame('Kết thúc');
        else if (!frames[frames.length - 1].note) frames[frames.length - 1].note = 'Kết thúc';
      } catch (e) {
        error = String((e && e.message) || e);
        const m = /<anonymous>:(\d+):(\d+)/.exec((e && e.stack) || '');
        if (m) error += ` (dòng ${Number(m[1]) - 3})`;
        try { frame('Lỗi: ' + error); } catch (_) { /* vượt giới hạn khung */ }
      }
      self.postMessage({ frames, logs, error });
    };
  }

  // =====================================================================
  // 2) Phần chạy trong iframe: khởi tạo Worker và vẽ các khung bằng SVG.
  // =====================================================================
  function simFrameMain(WORKER_SRC) {
    const COLORS = {
      compare: '#f59e0b', swap: '#ef4444', set: '#a855f7', active: '#3b82f6', current: '#ef4444',
      done: '#22c55e', sorted: '#22c55e', found: '#16a34a', visited: '#8b5cf6', path: '#f97316',
      wall: 'var(--wall)', start: '#10b981', end: '#e11d48', frontier: '#06b6d4', dim: '#94a3b8',
    };
    const color = (st) => {
      if (!st) return null;
      if (COLORS[st]) return COLORS[st];
      if (/^(#|rgb|hsl)/.test(st)) return st;
      let h = 0;
      for (const ch of st) h = (h * 31 + ch.charCodeAt(0)) % 360;
      return `hsl(${h} 65% 50%)`;
    };
    const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

    const $ = (id) => document.getElementById(id);
    let frames = [];
    let logs = [];
    let cur = 0;
    let timer = null;
    let speed = 1;

    function postHeight() {
      parent.postMessage({ __sim: 'height', h: document.documentElement.scrollHeight }, '*');
    }
    new ResizeObserver(postHeight).observe(document.body);

    window.addEventListener('message', (ev) => {
      const d = ev.data || {};
      if (d.__sim !== 'run') return;
      document.documentElement.dataset.theme = d.theme || 'light';
      run(d.code, d.input);
    });

    function run(code, input) {
      stop();
      $('status').textContent = 'Đang chạy…';
      $('stage').innerHTML = '';
      let done = false;
      const finish = (res) => {
        if (done) return;
        done = true;
        frames = res.frames || [];
        logs = res.logs || [];
        $('err').textContent = res.error ? '⚠ ' + res.error : '';
        $('err').hidden = !res.error;
        $('slider').max = Math.max(0, frames.length - 1);
        cur = 0;
        $('status').textContent = '';
        render();
      };
      try {
        const url = URL.createObjectURL(new Blob([`(${WORKER_SRC})(self)`], { type: 'text/javascript' }));
        const w = new Worker(url);
        const t = setTimeout(() => {
          w.terminate();
          finish({ frames: [], logs: [], error: 'Quá thời gian chạy 4 giây — có thể có vòng lặp vô hạn.' });
        }, 4000);
        w.onmessage = (ev) => { clearTimeout(t); w.terminate(); finish(ev.data); };
        w.onerror = (ev) => { clearTimeout(t); w.terminate(); finish({ frames: [], logs: [], error: ev.message || 'Lỗi không xác định' }); ev.preventDefault(); };
        w.postMessage({ code, input });
      } catch (e) {
        // Trình duyệt không cho tạo Worker trong sandbox → chạy trực tiếp (không có giới hạn thời gian).
        const fake = { postMessage: finish };
        // eslint-disable-next-line no-new-func
        new Function('self', `(${WORKER_SRC})(self)`)(fake);
        fake.onmessage({ data: { code, input } });
      }
    }

    function stop() {
      clearInterval(timer);
      timer = null;
      $('play').textContent = '▶';
    }
    function play() {
      if (timer) return stop();
      if (cur >= frames.length - 1) cur = 0;
      $('play').textContent = '⏸';
      timer = setInterval(() => {
        if (cur >= frames.length - 1) return stop();
        cur++;
        render();
      }, 700 / speed);
    }
    const go = (i) => { cur = Math.max(0, Math.min(frames.length - 1, i)); render(); };
    $('first').onclick = () => { stop(); go(0); };
    $('prev').onclick = () => { stop(); go(cur - 1); };
    $('next').onclick = () => { stop(); go(cur + 1); };
    $('last').onclick = () => { stop(); go(frames.length - 1); };
    $('play').onclick = play;
    $('slider').oninput = (e) => { stop(); go(Number(e.target.value)); };
    $('speed').onchange = (e) => { speed = Number(e.target.value); if (timer) { stop(); play(); } };
    document.addEventListener('keydown', (e) => {
      if (e.key === 'ArrowRight') { stop(); go(cur + 1); }
      else if (e.key === 'ArrowLeft') { stop(); go(cur - 1); }
      else if (e.key === ' ') { e.preventDefault(); play(); }
    });

    function render() {
      const f = frames[cur];
      $('slider').value = cur;
      $('count').textContent = frames.length ? `Bước ${cur + 1}/${frames.length}` : '';
      $('note').textContent = f ? f.note : '';
      if (!f) { $('stage').innerHTML = ''; $('vars').innerHTML = ''; $('log').hidden = true; postHeight(); return; }
      $('stage').innerHTML = f.s.map(drawStruct).join('');
      const vs = Object.entries(f.vars);
      $('vars').innerHTML = vs.map(([k, v]) => `<span class="var"><b>${esc(k)}</b> = ${esc(typeof v === 'object' ? JSON.stringify(v) : v)}</span>`).join('');
      const shown = logs.slice(0, f.logN);
      $('log').hidden = !shown.length;
      $('log').textContent = shown.slice(-200).join('\n');
      $('log').scrollTop = 1e9;
      postHeight();
    }

    function drawStruct(s) {
      const title = `<div class="sname">${esc(s.name)}${s.kind === 'list' ? (s.mode === 'stack' ? ' (stack)' : ' (queue)') : ''}</div>`;
      if (s.kind === 'array') return title + drawArray(s);
      if (s.kind === 'grid') return title + drawGrid(s);
      if (s.kind === 'graph') return title + drawGraph(s);
      if (s.kind === 'list') return title + drawList(s);
      return '';
    }

    function drawArray(s) {
      const n = s.v.length;
      const W = Math.max(24, Math.min(52, Math.floor(680 / Math.max(1, n))));
      const ptrAt = {};
      Object.entries(s.ptr).forEach(([k, i]) => (ptrAt[i] = (ptrAt[i] || []).concat(k)));
      const maxPtr = Math.max(0, ...Object.values(ptrAt).map((x) => x.length));
      const nums = s.v.map(Number).filter((x) => !isNaN(x));
      const maxV = Math.max(1, ...nums.map(Math.abs));
      const barH = s.bars ? 140 : 0;
      const boxH = s.bars ? 0 : W;
      const H = barH + boxH + 18 + maxPtr * 15 + 6;
      let out = `<svg width="${n * W + 2}" height="${H}" class="arr">`;
      s.v.forEach((val, i) => {
        const x = i * W + 1;
        const fill = color(s.hl[i]) || color(s.st[i]);
        if (s.bars) {
          const h = Math.max(4, (Math.abs(Number(val)) / maxV) * (barH - 18));
          out += `<rect x="${x + 2}" y="${barH - h}" width="${W - 4}" height="${h}" rx="3" class="bar" ${fill ? `style="fill:${fill}"` : ''}/>`;
          if (W >= 22) out += `<text x="${x + W / 2}" y="${barH - h - 4}" class="val sm">${esc(val)}</text>`;
        } else {
          out += `<rect x="${x}" y="1" width="${W - 2}" height="${W - 2}" rx="5" class="box" ${fill ? `style="fill:${fill};stroke:${fill}"` : ''}/>`;
          out += `<text x="${x + W / 2 - 1}" y="${W / 2 + 5}" class="val ${fill ? 'on' : ''}" style="font-size:${Math.min(16, W / Math.max(1.6, String(val).length * 0.62))}px">${esc(val)}</text>`;
        }
        out += `<text x="${x + W / 2}" y="${barH + boxH + 13}" class="idx">${i}</text>`;
        (ptrAt[i] || []).forEach((p, k) => (out += `<text x="${x + W / 2}" y="${barH + boxH + 30 + k * 15}" class="ptr">↑${esc(p)}</text>`));
      });
      return out + '</svg>';
    }

    function drawGrid(s) {
      const R = s.v.length;
      const C = R ? s.v[0].length : 0;
      const S = Math.max(10, Math.min(36, Math.floor(680 / Math.max(1, C))));
      let out = `<svg width="${C * S + 2}" height="${R * S + 2}">`;
      for (let r = 0; r < R; r++)
        for (let c = 0; c < C; c++) {
          const key = `${r},${c}`;
          const fill = color(s.hl[key]) || color(s.st[key]);
          out += `<rect x="${c * S + 1}" y="${r * S + 1}" width="${S}" height="${S}" class="cell" ${fill ? `style="fill:${fill}"` : ''}/>`;
          const val = s.v[r][c];
          if (s.showValues && val !== '' && val !== null && S >= 18)
            out += `<text x="${c * S + 1 + S / 2}" y="${r * S + S / 2 + 5}" class="val sm ${fill ? 'on' : ''}">${esc(val)}</text>`;
        }
      return out + '</svg>';
    }

    function drawGraph(s) {
      const W = 680;
      const H = s.depth >= 0 ? Math.max(120, (s.depth + 1) * 80) : 340;
      const P = 32;
      const pos = {};
      s.nodes.forEach((n) => (pos[n.id] = { x: P + n.x * (W - 2 * P), y: P + 8 + n.y * (H - 2 * P - 8) }));
      let out = `<svg width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" style="max-width:100%"><defs>
        <marker id="ah" viewBox="0 0 10 10" refX="10" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0L10,5L0,10z" class="arrowhead"/></marker></defs>`;
      s.edges.forEach((e) => {
        const a = pos[e.u];
        const b = pos[e.v];
        if (!a || !b) return;
        const dx = b.x - a.x;
        const dy = b.y - a.y;
        const L = Math.hypot(dx, dy) || 1;
        const r = 18;
        const c = color(e.st);
        out += `<line x1="${a.x + (dx / L) * r}" y1="${a.y + (dy / L) * r}" x2="${b.x - (dx / L) * r}" y2="${b.y - (dy / L) * r}" class="edge" ${c ? `style="stroke:${c};stroke-width:3"` : ''} ${s.directed ? 'marker-end="url(#ah)"' : ''}/>`;
        if (e.w !== '') out += `<text x="${(a.x + b.x) / 2 - (dy / L) * 10}" y="${(a.y + b.y) / 2 + (dx / L) * 10 + 4}" class="w">${esc(e.w)}</text>`;
      });
      s.nodes.forEach((n) => {
        const p = pos[n.id];
        const c = color(n.hl) || color(n.st);
        out += `<circle cx="${p.x}" cy="${p.y}" r="18" class="node" ${c ? `style="fill:${c};stroke:${c}"` : ''}/>`;
        out += `<text x="${p.x}" y="${p.y + 5}" class="val ${c ? 'on' : ''}" style="font-size:${n.label.length > 3 ? 11 : 14}px">${esc(n.label)}</text>`;
        if (n.sub) out += `<text x="${p.x}" y="${p.y - 23}" class="sub">${esc(n.sub)}</text>`;
      });
      return out + '</svg>';
    }

    function drawList(s) {
      const W = 46;
      const n = s.v.length;
      const H = W + 22;
      let out = `<svg width="${Math.max(120, n * W + 60)}" height="${H}">`;
      if (!n) out += `<text x="4" y="${W / 2 + 5}" class="idx" style="text-anchor:start">(rỗng)</text>`;
      s.v.forEach((val, i) => {
        const x = i * W + 1;
        const fill = color(s.hl[i]);
        out += `<rect x="${x}" y="1" width="${W - 2}" height="${W - 2}" rx="5" class="box" ${fill ? `style="fill:${fill};stroke:${fill}"` : ''}/>`;
        out += `<text x="${x + W / 2 - 1}" y="${W / 2 + 5}" class="val ${fill ? 'on' : ''}" style="font-size:${Math.min(15, W / Math.max(1.6, String(val).length * 0.62))}px">${esc(val)}</text>`;
      });
      if (n) {
        if (s.mode === 'stack') out += `<text x="${(n - 1) * W + W / 2}" y="${W + 16}" class="ptr">↑ đỉnh</text>`;
        else {
          out += `<text x="${W / 2}" y="${W + 16}" class="ptr">↑ đầu</text>`;
          if (n > 1) out += `<text x="${(n - 1) * W + W / 2}" y="${W + 16}" class="ptr">↑ cuối</text>`;
        }
      }
      return out + '</svg>';
    }

    parent.postMessage({ __sim: 'ready' }, '*');
  }

  // =====================================================================
  // 3) Phía app: tạo iframe sandbox.
  // =====================================================================
  const FRAME_CSS = `
    :root{--bg:#ffffff;--fg:#1e293b;--mut:#64748b;--box:#f1f5f9;--line:#cbd5e1;--acc:#2563eb;--wall:#334155}
    :root[data-theme=dark]{--bg:#0f172a;--fg:#e2e8f0;--mut:#94a3b8;--box:#1e293b;--line:#334155;--acc:#60a5fa;--wall:#64748b}
    *{box-sizing:border-box}
    body{margin:0;padding:10px;background:var(--bg);color:var(--fg);font:14px/1.45 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
    .bar-ctl{display:flex;gap:6px;align-items:center;flex-wrap:wrap}
    button,select{background:var(--box);color:var(--fg);border:1px solid var(--line);border-radius:6px;padding:4px 10px;font:inherit;cursor:pointer;min-width:34px}
    button:hover{border-color:var(--acc)}
    input[type=range]{flex:1;min-width:120px;accent-color:var(--acc)}
    #count{color:var(--mut);font-variant-numeric:tabular-nums;min-width:90px;text-align:right}
    #note{min-height:1.5em;margin:8px 0;font-weight:600}
    #err{color:#ef4444;margin:6px 0;white-space:pre-wrap}
    #stage{display:flex;flex-direction:column;gap:6px;overflow-x:auto}
    .sname{color:var(--mut);font-size:12px;font-family:ui-monospace,Consolas,monospace;margin-top:4px}
    svg{display:block;overflow:visible}
    .box,.node,.cell{fill:var(--box);stroke:var(--line);stroke-width:1.5}
    .cell{stroke-width:1}
    .bar{fill:#94a3b8}
    .edge{stroke:var(--line);stroke-width:2}
    .arrowhead{fill:var(--mut)}
    text{text-anchor:middle;fill:var(--fg);font-family:ui-monospace,Consolas,monospace}
    .val{font-size:15px;font-weight:600}.val.sm{font-size:11px}.val.on{fill:#fff}
    .idx{font-size:11px;fill:var(--mut)}.ptr{font-size:12px;fill:var(--acc);font-weight:700}
    .w{font-size:12px;fill:var(--mut)}.sub{font-size:11px;fill:var(--acc);font-weight:700}
    #vars{display:flex;flex-wrap:wrap;gap:6px;margin-top:8px}
    .var{background:var(--box);border:1px solid var(--line);border-radius:6px;padding:1px 8px;font-family:ui-monospace,Consolas,monospace;font-size:13px}
    #log{margin-top:8px;max-height:140px;overflow:auto;background:var(--box);border-radius:6px;padding:6px 8px;font:12px/1.4 ui-monospace,Consolas,monospace;white-space:pre-wrap}
    #status{color:var(--mut)}`;

  const FRAME_BODY = `
    <div class="bar-ctl">
      <button id="first" title="Về đầu">⏮</button><button id="prev" title="Lùi (←)">◀</button>
      <button id="play" title="Chạy/dừng (Space)">▶</button><button id="next" title="Tới (→)">▶|</button>
      <button id="last" title="Về cuối">⏭</button>
      <input id="slider" type="range" min="0" max="0" value="0">
      <select id="speed" title="Tốc độ"><option value="0.5">0.5x</option><option value="1" selected>1x</option><option value="2">2x</option><option value="4">4x</option><option value="10">10x</option></select>
      <span id="count"></span>
    </div>
    <div id="status"></div><div id="err" hidden></div>
    <div id="note"></div><div id="stage"></div><div id="vars"></div><pre id="log" hidden></pre>`;

  let srcdocCache = null;
  function srcdoc() {
    if (srcdocCache) return srcdocCache;
    const workerSrc = JSON.stringify(simWorkerMain.toString()).replace(/<\//g, '<\\/');
    const frameSrc = simFrameMain.toString().replace(/<\/script/gi, '<\\/script');
    srcdocCache = `<!doctype html><html><head><meta charset="utf-8"><style>${FRAME_CSS}</style></head><body>${FRAME_BODY}<script>(${frameSrc})(${workerSrc});<\/script></body></html>`;
    return srcdocCache;
  }

  const frames = new Map(); // contentWindow → { iframe, pending }
  root.addEventListener && root.addEventListener('message', (ev) => {
    const d = ev.data;
    if (!d || !d.__sim) return;
    const entry = frames.get(ev.source);
    if (!entry) return;
    if (d.__sim === 'height') entry.iframe.style.height = Math.min(2000, d.h + 2) + 'px';
    if (d.__sim === 'ready') {
      entry.ready = true;
      if (entry.pending) ev.source.postMessage(entry.pending, '*');
    }
  });

  // Gắn trình mô phỏng vào `container`, trả về hàm run(code, input) để chạy lại.
  function mount(container, { theme } = {}) {
    const iframe = document.createElement('iframe');
    iframe.className = 'sim-frame';
    iframe.setAttribute('sandbox', 'allow-scripts');
    iframe.setAttribute('title', 'Mô phỏng thuật toán');
    iframe.srcdoc = srcdoc();
    container.appendChild(iframe);
    const entry = { iframe, ready: false, pending: null };
    // contentWindow chỉ có sau khi gắn vào DOM.
    frames.set(iframe.contentWindow, entry);
    return {
      run(code, input) {
        const msg = { __sim: 'run', code, input, theme: theme || document.documentElement.dataset.theme || 'light' };
        entry.pending = msg;
        if (entry.ready) iframe.contentWindow.postMessage(msg, '*');
      },
      destroy() {
        frames.delete(iframe.contentWindow);
        iframe.remove();
      },
    };
  }

  root.SIM = { mount, simWorkerMain };
  if (typeof module !== 'undefined' && module.exports) module.exports = { simWorkerMain };
})(typeof globalThis !== 'undefined' ? globalThis : this);
