// Bộ ghi bước mô phỏng (thư viện viz) — chạy trong QuickJS.
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
      insert(i, x) {
        this.v.splice(i, 0, x);
        const st = {};
        Object.keys(this.st).forEach((k) => (st[Number(k) >= i ? Number(k) + 1 : k] = this.st[k]));
        this.st = st;
        this.hl[i] = 'set';
        tick(`Chèn ${fmt(x)} vào ${this.name}[${i}]`);
      }
      removeAt(i) {
        const [x] = this.v.splice(i, 1);
        const st = {};
        Object.keys(this.st).forEach((k) => { if (Number(k) !== i) st[Number(k) > i ? Number(k) - 1 : k] = this.st[k]; });
        this.st = st;
        tick(`Xoá ${this.name}[${i}] = ${fmt(x)}`);
        return x;
      }
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
        if (e === '__stop') {
          if (dirty) frame('Dừng chương trình');
          self.postMessage({ frames, logs, error });
          return;
        }
        error = String((e && e.message) || e);
        const m = /<anonymous>:(\d+):(\d+)/.exec((e && e.stack) || '');
        if (m) error += ` (dòng ${Number(m[1]) - 3})`;
        try { frame('Lỗi: ' + error); } catch (_) { /* vượt giới hạn khung */ }
      }
      self.postMessage({ frames, logs, error });
    };
  }
function __runSim(code, input) {
  var result = null;
  var self = { postMessage: function (r) { result = r; } };
  simWorkerMain(self);
  self.onmessage({ data: { code: code, input: input } });
  return JSON.stringify(result);
}
