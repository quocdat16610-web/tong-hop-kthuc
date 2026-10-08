/*
 * services.js — Lưu trữ (IndexedDB), ảnh/video, bài nộp, cài đặt, chia sẻ, nền tảng (máy tính / Android / web).
 */
(function (root) {
  'use strict';

  // ---------------- Nền tảng ----------------
  const desktop = root.desktop || null; // do electron/preload.js cung cấp
  const cap = root.Capacitor && root.Capacitor.isNativePlatform && root.Capacitor.isNativePlatform() ? root.Capacitor : null;
  const Platform = {
    desktop,
    android: !!cap,
    name: desktop ? 'desktop' : cap ? 'android' : 'web',
  };

  // ---------------- IndexedDB ----------------
  const DB_NAME = 'dsa-notebook';
  const STORES = ['repos', 'assets', 'subs', 'runs'];
  let dbPromise = null;
  function db() {
    if (!dbPromise)
      dbPromise = new Promise((resolve, reject) => {
        const req = indexedDB.open(DB_NAME, 2);
        req.onupgradeneeded = () => {
          const d = req.result;
          if (!d.objectStoreNames.contains('repos')) d.createObjectStore('repos', { keyPath: 'id' });
          if (!d.objectStoreNames.contains('assets')) d.createObjectStore('assets', { keyPath: 'hash' });
          if (!d.objectStoreNames.contains('subs')) d.createObjectStore('subs', { keyPath: 'id' });
          if (!d.objectStoreNames.contains('runs')) d.createObjectStore('runs', { keyPath: 'id' });
        };
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
      });
    return dbPromise;
  }
  async function tx(store, mode, fn) {
    const d = await db();
    return new Promise((resolve, reject) => {
      const t = d.transaction(store, mode);
      const req = fn(t.objectStore(store));
      t.oncomplete = () => resolve(req && req.result);
      t.onerror = () => reject(t.error);
    });
  }
  const table = (name) => ({
    all: () => tx(name, 'readonly', (s) => s.getAll()),
    get: (id) => tx(name, 'readonly', (s) => s.get(id)),
    put: (x) => tx(name, 'readwrite', (s) => s.put(x)),
    remove: (id) => tx(name, 'readwrite', (s) => s.delete(id)),
  });
  const reposT = table('repos');
  const Store = {
    list: reposT.all,
    get: reposT.get,
    put: (repo) => reposT.put({ ...repo, updatedAt: Date.now() }),
    remove: reposT.remove,
  };
  const Subs = table('subs');
  const Runs = table('runs');

  // ---------------- Ảnh / video (lưu riêng, tham chiếu bằng "asset:<hash>") ----------------
  const assetsT = table('assets');
  const urlCache = new Map();
  const ASSET_RE = /asset:([0-9a-f]{16,64})/g;

  async function hashBlob(blob) {
    const buf = await blob.arrayBuffer();
    if (root.crypto && crypto.subtle) {
      const d = await crypto.subtle.digest('SHA-256', buf);
      return Array.from(new Uint8Array(d), (b) => b.toString(16).padStart(2, '0')).join('');
    }
    return root.VCS.newId(32);
  }

  // Thu nhỏ ảnh lớn để notebook không quá nặng khi chia sẻ.
  async function shrinkImage(file, maxSide = 1600) {
    if (!/^image\/(png|jpeg|webp|bmp)$/.test(file.type)) return file;
    let bmp;
    try { bmp = await createImageBitmap(file); } catch (_) { return file; }
    const scale = Math.min(1, maxSide / Math.max(bmp.width, bmp.height));
    if (scale === 1 && file.size < 600 * 1024) return file;
    const canvas = document.createElement('canvas');
    canvas.width = Math.round(bmp.width * scale);
    canvas.height = Math.round(bmp.height * scale);
    canvas.getContext('2d').drawImage(bmp, 0, 0, canvas.width, canvas.height);
    const type = file.type === 'image/png' && file.size < 2e6 ? 'image/png' : 'image/webp';
    const out = await new Promise((resolve) => canvas.toBlob(resolve, type, 0.85));
    return out && out.size < file.size ? out : file;
  }

  const Assets = {
    async add(file) {
      const blob = file.type && file.type.startsWith('image/') ? await shrinkImage(file) : file;
      const hash = await hashBlob(blob);
      await assetsT.put({ hash, type: blob.type || file.type || 'application/octet-stream', size: blob.size, blob, name: file.name || '' });
      return 'asset:' + hash;
    },
    async url(ref) {
      const hash = String(ref).replace(/^asset:/, '');
      if (urlCache.has(hash)) return urlCache.get(hash);
      const rec = await assetsT.get(hash);
      if (!rec) return null;
      const u = URL.createObjectURL(rec.blob);
      urlCache.set(hash, u);
      return u;
    },
    refs(obj) {
      const s = typeof obj === 'string' ? obj : JSON.stringify(obj);
      return [...new Set([...s.matchAll(ASSET_RE)].map((m) => m[1]))];
    },
    async pack(hashes) {
      const out = {};
      for (const h of hashes) {
        const rec = await assetsT.get(h);
        if (!rec) continue;
        out[h] = { type: rec.type, name: rec.name, data: await blobToB64(rec.blob) };
      }
      return out;
    },
    async unpack(map) {
      for (const [hash, a] of Object.entries(map || {})) {
        if (!/^[0-9a-f]{16,64}$/.test(hash)) continue;
        const bytes = b64.dec(a.data);
        await assetsT.put({ hash, type: a.type, name: a.name || '', size: bytes.length, blob: new Blob([bytes], { type: a.type }) });
      }
    },
  };
  async function blobToB64(blob) {
    return b64.enc(new Uint8Array(await blob.arrayBuffer()));
  }

  // ---------------- Cài đặt ----------------
  const DEFAULTS = {
    author: '', compiler: 'g132', cppFlags: '-O2 -std=c++17', theme: 'auto', lastRepo: null, gppPath: '', judgeMode: 'auto',
  };
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
      } catch (_) { /* chế độ riêng tư */ }
    },
  };

  // ---------------- Mã hoá / chia sẻ ----------------
  const b64 = {
    enc(bytes) {
      let s = '';
      for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
      return btoa(s);
    },
    dec(str) {
      const s = atob(str);
      const out = new Uint8Array(s.length);
      for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
      return out;
    },
  };
  const toUrl = (s) => s.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  const fromUrl = (s) => s.replace(/-/g, '+').replace(/_/g, '/');
  async function pipe(bytes, stream) {
    const out = new Response(new Blob([bytes]).stream().pipeThrough(stream));
    return new Uint8Array(await out.arrayBuffer());
  }
  const Share = {
    async encode(obj) {
      const bytes = new TextEncoder().encode(JSON.stringify(obj));
      if (root.CompressionStream) return 'z' + toUrl(b64.enc(await pipe(bytes, new CompressionStream('deflate-raw'))));
      return 'j' + toUrl(b64.enc(bytes));
    },
    async decode(str) {
      const kind = str[0];
      let bytes = b64.dec(fromUrl(str.slice(1)));
      if (kind === 'z') bytes = await pipe(bytes, new DecompressionStream('deflate-raw'));
      else if (kind !== 'j') throw new Error('Link chia sẻ không hợp lệ.');
      return JSON.parse(new TextDecoder().decode(bytes));
    },
    // Lưu file: máy tính/web tải xuống; Android mở bảng chia sẻ (Zalo, Messenger, Drive…).
    async save(filename, text, mime = 'application/json') {
      if (cap && cap.Plugins.Filesystem) {
        const { Filesystem, Share: CapShare } = cap.Plugins;
        const res = await Filesystem.writeFile({ path: filename, data: text, directory: 'CACHE', encoding: 'utf8' });
        if (CapShare) await CapShare.share({ title: filename, files: [res.uri] });
        return;
      }
      const a = document.createElement('a');
      a.href = URL.createObjectURL(new Blob([text], { type: mime }));
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

  // ---------------- Biên dịch & chạy C++ ----------------
  async function postJson(url, body) {
    if (desktop) return desktop.postJson(url, body);
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify(body),
    });
    if (!res.ok) throw new Error(`Máy chủ biên dịch trả lỗi ${res.status}`);
    return res.json();
  }

  let compilerInfo = null; // { path, version } khi máy tính có g++
  const Runner = {
    async detect(force) {
      if (!desktop) return null;
      if (compilerInfo && !force) return compilerInfo;
      compilerInfo = await desktop.findCompiler(Settings.get('gppPath') || '');
      return compilerInfo;
    },
    // Chọn nơi chạy code: g++ trên máy (nếu có) hoặc Compiler Explorer online.
    async backend() {
      const mode = Settings.get('judgeMode');
      if (desktop && mode !== 'online') {
        const info = await Runner.detect();
        if (info) {
          const flags = Settings.get('cppFlags') || '-O2 -std=c++17';
          return {
            name: 'g++ trên máy', local: true, parallel: 2,
            compile: (source) => desktop.compile({ source, gpp: info.path, flags }),
            run: (id, input, tl) => desktop.run(id, input, tl),
            dispose: (id) => desktop.dispose(id),
          };
        }
      }
      return root.Judge.onlineBackend(postJson, { compiler: Settings.get('compiler') || 'g132', flags: Settings.get('cppFlags') || '' });
    },
    // Chạy một lần với stdin (nút "Chạy" của khối code / khu code).
    async run(source, stdin, timeLimit = 5000) {
      const be = await Runner.backend();
      const comp = await be.compile(source);
      if (!comp.ok) return { phase: 'compile', output: comp.error, where: be.name };
      try {
        const r = await be.run(comp.id, stdin, timeLimit);
        if (r.compileError !== undefined) return { phase: 'compile', output: r.compileError, where: be.name };
        return { phase: 'run', ...r, warnings: comp.warnings || r.warnings, where: be.name };
      } finally {
        be.dispose && be.dispose(comp.id);
      }
    },
  };

  root.Services = { Platform, Store, Subs, Runs, Assets, Settings, Share, Runner };
})(typeof globalThis !== 'undefined' ? globalThis : this);
