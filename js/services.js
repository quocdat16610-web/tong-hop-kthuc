/*
 * services.js — Lưu trữ (IndexedDB), cài đặt, chia sẻ qua link/file, chạy C++ online.
 */
(function (root) {
  'use strict';

  // ---------------- Lưu trữ notebook trong IndexedDB ----------------
  const DB_NAME = 'dsa-notebook';
  let dbPromise = null;
  function db() {
    if (!dbPromise)
      dbPromise = new Promise((resolve, reject) => {
        const req = indexedDB.open(DB_NAME, 1);
        req.onupgradeneeded = () => req.result.createObjectStore('repos', { keyPath: 'id' });
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
      });
    return dbPromise;
  }
  async function tx(mode, fn) {
    const d = await db();
    return new Promise((resolve, reject) => {
      const t = d.transaction('repos', mode);
      const req = fn(t.objectStore('repos'));
      t.oncomplete = () => resolve(req && req.result);
      t.onerror = () => reject(t.error);
    });
  }
  const Store = {
    list: () => tx('readonly', (s) => s.getAll()),
    get: (id) => tx('readonly', (s) => s.get(id)),
    put: (repo) => tx('readwrite', (s) => s.put({ ...repo, updatedAt: Date.now() })),
    remove: (id) => tx('readwrite', (s) => s.delete(id)),
  };

  // ---------------- Cài đặt (localStorage) ----------------
  const DEFAULTS = { author: '', compiler: 'g132', cppFlags: '-O2 -std=c++17', theme: 'auto', lastRepo: null };
  const Settings = {
    get(key) {
      try {
        const all = JSON.parse(localStorage.getItem('dsa-settings') || '{}');
        return key in all ? all[key] : DEFAULTS[key];
      } catch (_) {
        return DEFAULTS[key];
      }
    },
    set(key, value) {
      try {
        const all = JSON.parse(localStorage.getItem('dsa-settings') || '{}');
        all[key] = value;
        localStorage.setItem('dsa-settings', JSON.stringify(all));
      } catch (_) { /* chế độ riêng tư: bỏ qua */ }
    },
  };

  // ---------------- Chia sẻ: nén JSON thành chuỗi base64url ----------------
  const b64url = {
    enc(bytes) {
      let s = '';
      for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
      return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
    },
    dec(str) {
      const s = atob(str.replace(/-/g, '+').replace(/_/g, '/'));
      return Uint8Array.from(s, (c) => c.charCodeAt(0));
    },
  };
  async function pipe(bytes, stream) {
    const out = new Response(new Blob([bytes]).stream().pipeThrough(stream));
    return new Uint8Array(await out.arrayBuffer());
  }
  const Share = {
    async encode(obj) {
      const bytes = new TextEncoder().encode(JSON.stringify(obj));
      if (root.CompressionStream) return 'z' + b64url.enc(await pipe(bytes, new CompressionStream('deflate-raw')));
      return 'j' + b64url.enc(bytes);
    },
    async decode(str) {
      const kind = str[0];
      let bytes = b64url.dec(str.slice(1));
      if (kind === 'z') bytes = await pipe(bytes, new DecompressionStream('deflate-raw'));
      else if (kind !== 'j') throw new Error('Link chia sẻ không hợp lệ.');
      return JSON.parse(new TextDecoder().decode(bytes));
    },
    download(filename, text) {
      const a = document.createElement('a');
      a.href = URL.createObjectURL(new Blob([text], { type: 'application/json' }));
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
    },
    readFile(file) {
      return new Promise((resolve, reject) => {
        const r = new FileReader();
        r.onload = () => resolve(r.result);
        r.onerror = () => reject(r.error);
        r.readAsText(file);
      });
    },
  };

  // ---------------- Chạy C++ qua API Compiler Explorer (godbolt.org) ----------------
  const Cpp = {
    async run(source, stdin) {
      const compiler = Settings.get('compiler') || 'g132';
      const res = await fetch(`https://godbolt.org/api/compiler/${encodeURIComponent(compiler)}/compile`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({
          source,
          options: {
            userArguments: Settings.get('cppFlags') || '',
            executeParameters: { args: [], stdin: stdin || '' },
            compilerOptions: { executorRequest: true },
            filters: { execute: true },
            tools: [],
            libraries: [],
          },
          lang: 'c++',
          allowStoreCodeDebug: false,
        }),
      });
      if (!res.ok) throw new Error(`Máy chủ biên dịch trả lỗi ${res.status}`);
      const data = await res.json();
      const exec = data.execResult || data;
      const build = exec.buildResult || data.buildResult || {};
      const text = (arr) => (arr || []).map((x) => x.text).join('\n');
      const buildErr = text(build.stderr);
      if (build.code && build.code !== 0) return { ok: false, phase: 'compile', output: buildErr || 'Biên dịch thất bại' };
      return {
        ok: exec.code === 0,
        phase: 'run',
        code: exec.code,
        stdout: text(exec.stdout),
        stderr: text(exec.stderr),
        warnings: buildErr,
        timedOut: !!exec.timedOut,
      };
    },
  };

  root.Services = { Store, Settings, Share, Cpp };
})(typeof globalThis !== 'undefined' ? globalThis : this);
