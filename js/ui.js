/*
 * ui.js — Tiện ích giao diện dùng chung: tạo DOM, biểu tượng, hộp thoại, Markdown, video, trình soạn code.
 */
(function (root) {
  'use strict';

  // ---------- DOM ----------
  function h(tag, attrs, ...kids) {
    const el = document.createElement(tag);
    if (attrs)
      Object.entries(attrs).forEach(([k, v]) => {
        if (v === undefined || v === null || v === false) return;
        if (k === 'class') el.className = v;
        else if (k === 'style' && typeof v === 'object') Object.assign(el.style, v);
        else if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2).toLowerCase(), v);
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

  // ---------- Biểu tượng (nét mảnh, 24x24) ----------
  const P = {
    menu: 'M4 6h16M4 12h16M4 18h16',
    plus: 'M12 5v14M5 12h14',
    book: 'M5 4h11a3 3 0 0 1 3 3v13H8a3 3 0 0 1-3-3zM5 17a3 3 0 0 1 3-3h11',
    branch: 'M6 3v12M18 9a3 3 0 1 0 0-.01M6 21a3 3 0 1 0 0-.01M18 9c0 5-6 5-12 9',
    commit: 'M12 9a3 3 0 1 0 0 6 3 3 0 1 0 0-6M3 12h6M15 12h6',
    history: 'M3 12a9 9 0 1 0 3-6.7L3 8M3 3v5h5M12 7v5l3 2',
    merge: 'M6 3a3 3 0 1 0 0 6 3 3 0 1 0 0-6M6 9v12M18 15a3 3 0 1 0 0 6 3 3 0 1 0 0-6M6 9c0 5 5 9 9 9',
    share: 'M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1',
    upload: 'M12 16V4M7 9l5-5 5 5M4 20h16',
    download: 'M12 4v12M7 11l5 5 5-5M4 20h16',
    settings: 'M4 7h10M18 7h2M4 17h4M12 17h8M16 5v4M10 15v4',
    play: 'M7 4.5v15l12-7.5z',
    trash: 'M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 11v6M14 11v6',
    up: 'M12 19V5M6 11l6-6 6 6',
    down: 'M12 5v14M6 13l6 6 6-6',
    copy: 'M9 9h11v11H9zM5 15V4h11',
    edit: 'M4 20h4L19 9l-4-4L4 16zM13 7l4 4',
    check: 'M5 12.5l4.5 4.5L19 7',
    x: 'M6 6l12 12M18 6L6 18',
    image: 'M3 5h18v14H3zM8.5 10a1.5 1.5 0 1 0 0-.01M21 16l-5-5-9 8',
    video: 'M3 6h13v12H3zM16 10l5-3v10l-5-3',
    code: 'M8 7l-5 5 5 5M16 7l5 5-5 5M14 4l-4 16',
    heading: 'M6 4v16M18 4v16M6 12h12',
    text: 'M4 6h16M4 11h16M4 16h10',
    blocks: 'M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 17h6M17 14v6',
    sim: 'M3 12h4l3-7 4 14 3-7h4',
    trophy: 'M8 4h8v5a4 4 0 0 1-8 0zM8 6H4.5a3.5 3.5 0 0 0 4 4M16 6h3.5a3.5 3.5 0 0 1-4 4M12 13v4M8 21h8M10 17h4',
    problem: 'M5 3h10l4 4v14H5zM14 3v5h5M8 13h8M8 17h5',
    terminal: 'M3 4h18v16H3zM7 9l3 3-3 3M13 15h4',
    toc: 'M9 6h12M9 12h12M9 18h12M4 6h.01M4 12h.01M4 18h.01',
    eye: 'M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12zM12 9a3 3 0 1 0 0 6 3 3 0 1 0 0-6',
    more: 'M12 6h.01M12 12h.01M12 18h.01',
    maximize: 'M4 9V4h5M15 4h5v5M20 15v5h-5M9 20H4v-5',
    search: 'M11 4a7 7 0 1 0 0 14 7 7 0 1 0 0-14M20 20l-4-4',
    clock: 'M12 3a9 9 0 1 0 0 18 9 9 0 1 0 0-18M12 7v5l3 2',
    link: 'M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1',
    file: 'M6 3h9l4 4v14H6zM14 3v5h5',
    chevron: 'M9 6l6 6-6 6',
    back: 'M15 6l-6 6 6 6',
  };
  function icon(name, size = 16) {
    const span = document.createElement('span');
    span.className = 'ic';
    span.innerHTML = `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${P[name] || ''}"/></svg>`;
    return span;
  }
  // Nút có biểu tượng + chữ (chữ ẩn trên màn hình nhỏ nếu `compact`).
  function btn(iconName, label, onclick, opts = {}) {
    return h('button', { class: (opts.class || '') + (opts.compact ? ' compact' : ''), title: opts.title || label, onclick, disabled: opts.disabled, type: 'button' },
      iconName ? icon(iconName) : null, label ? h('span', { class: 'lbl' }, label) : null);
  }

  function toast(msg, isErr) {
    const box = document.getElementById('toasts');
    const el = h('div', { class: 'toast' + (isErr ? ' err' : '') }, msg);
    box.appendChild(el);
    while (box.children.length > 4) box.firstChild.remove();
    setTimeout(() => el.remove(), isErr ? 6000 : 2800);
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
  const isDark = () => document.documentElement.dataset.theme === 'dark';

  // ---------- Hộp thoại ----------
  function modal({ title, body, actions = [], wide = false, onClose }) {
    const bg = h('div', { class: 'modal-bg' });
    const close = () => {
      bg.remove();
      document.removeEventListener('keydown', onKey);
      onClose && onClose();
    };
    const onKey = (e) => e.key === 'Escape' && document.querySelector('.modal-bg:last-child') === bg && close();
    document.addEventListener('keydown', onKey);
    bg.addEventListener('mousedown', (e) => e.target === bg && close());
    const box = h('div', { class: 'modal' + (wide ? ' wide' : ''), role: 'dialog', 'aria-modal': 'true' },
      h('div', { class: 'modal-head' }, h('h2', null, title), h('button', { class: 'ghost icon-only', title: 'Đóng', onclick: close }, icon('x'))),
      h('div', { class: 'modal-body' }, body),
      actions.length ? h('div', { class: 'actions' }, actions.filter(Boolean).map((a) =>
        h('button', {
          class: a.primary ? 'primary' : a.danger ? 'danger' : '',
          onclick: async (ev) => {
            const b = ev.currentTarget;
            b.disabled = true;
            try {
              const keep = a.onClick ? await a.onClick() : undefined;
              if (keep !== false) close();
            } catch (err) {
              toast(err.message, true);
            } finally {
              b.disabled = false;
            }
          },
        }, a.label)
      )) : null
    );
    bg.appendChild(box);
    document.body.appendChild(bg);
    const f = box.querySelector('.modal-body input:not([type=checkbox]):not([type=radio]):not([type=file]), .modal-body textarea');
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
        actions: [{ label: 'Huỷ' }, { label: 'OK', primary: true, onClick: () => { done = true; resolve(input.value.trim()); } }],
        onClose: () => !done && resolve(null),
      });
      input.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') { done = true; resolve(input.value.trim()); m.close(); }
      });
    });
  }

  // ---------- Markdown (ảnh "asset:" được nạp từ kho ảnh) ----------
  function slug(i) { return 'sec-' + i; }
  function renderMarkdown(text, { headingIds } = {}) {
    const src = String(text || '').replace(/\(asset:([0-9a-f]{16,64})\)/g, '(#asset-$1)');
    let div;
    if (root.marked && root.DOMPurify) {
      div = h('div', { class: 'md', html: DOMPurify.sanitize(marked.parse(src, { gfm: true, breaks: true })) });
      if (root.hljs) div.querySelectorAll('pre code').forEach((c) => { try { hljs.highlightElement(c); } catch (_) { /* bỏ qua */ } });
      div.querySelectorAll('a').forEach((a) => {
        if (a.getAttribute('href') && !a.getAttribute('href').startsWith('#')) { a.target = '_blank'; a.rel = 'noopener noreferrer'; }
      });
      div.querySelectorAll('img[src^="#asset-"]').forEach((img) => {
        const hash = img.getAttribute('src').slice(7);
        img.removeAttribute('src');
        root.Services.Assets.url(hash).then((u) => u && (img.src = u));
      });
      if (headingIds) div.querySelectorAll('h1, h2, h3').forEach((el, i) => headingIds[i] && (el.id = headingIds[i]));
    } else div = h('div', { class: 'md plain' }, text || '');
    return div;
  }

  // Lấy các tiêu đề # / ## / ### trong Markdown (bỏ qua trong khối ```code```).
  function markdownHeadings(text) {
    const out = [];
    let fence = false;
    String(text || '').split('\n').forEach((line) => {
      if (/^\s*```/.test(line)) fence = !fence;
      if (fence) return;
      const m = line.match(/^(#{1,3})\s+(.+?)\s*#*\s*$/);
      if (m) out.push({ level: m[1].length, text: m[2].replace(/[*_`]/g, '') });
    });
    return out;
  }

  // ---------- Video ----------
  function parseTime(t) {
    if (/^\d+$/.test(t)) return Number(t);
    const m = String(t).match(/^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$/);
    if (m && (m[1] || m[2] || m[3])) return (Number(m[1]) || 0) * 3600 + (Number(m[2]) || 0) * 60 + (Number(m[3]) || 0);
    return String(t).split(':').map(Number).reduce((acc, x) => acc * 60 + x, 0);
  }
  function parseTimestamps(text) {
    return String(text || '').split('\n').map((line) => {
      const m = line.trim().match(/^((?:\d{1,2}:)?\d{1,2}:\d{2})\s*[-–:]?\s*(.*)$/);
      return m ? { sec: parseTime(m[1]), time: m[1], label: m[2] } : null;
    }).filter(Boolean);
  }

  // Nhận diện link video để phát ngay trong app.
  function parseVideo(url) {
    if (!url) return null;
    if (/^asset:/.test(url)) return { kind: 'asset', ref: url };
    let u;
    try { u = new URL(url.trim()); } catch (_) { return null; }
    const host = u.hostname.replace(/^(www|m)\./, '');
    const q = (k) => u.searchParams.get(k);
    if (host === 'youtu.be' || host.endsWith('youtube.com') || host === 'youtube-nocookie.com') {
      let id = host === 'youtu.be' ? u.pathname.slice(1).split('/')[0] : q('v');
      if (!id) {
        const m = u.pathname.match(/^\/(embed|shorts|live|v)\/([\w-]+)/);
        if (m) id = m[2];
      }
      if (id) return { kind: 'youtube', id, start: q('t') || q('start') ? parseTime(q('t') || q('start')) : 0 };
      if (q('list')) return { kind: 'embed', src: `https://www.youtube-nocookie.com/embed/videoseries?list=${encodeURIComponent(q('list'))}` };
    }
    if (host === 'vimeo.com' || host === 'player.vimeo.com') {
      const m = u.pathname.match(/(\d{6,})/);
      if (m) return { kind: 'embed', src: `https://player.vimeo.com/video/${m[1]}`, seek: 'vimeo' };
    }
    if (host === 'drive.google.com') {
      const m = u.pathname.match(/\/file\/d\/([\w-]+)/) || [null, q('id')];
      if (m[1]) return { kind: 'embed', src: `https://drive.google.com/file/d/${m[1]}/preview` };
    }
    if (host.endsWith('facebook.com') || host === 'fb.watch')
      return { kind: 'embed', src: `https://www.facebook.com/plugins/video.php?show_text=false&href=${encodeURIComponent(u.href)}` };
    if (host.endsWith('tiktok.com')) {
      const m = u.pathname.match(/\/video\/(\d+)/);
      if (m) return { kind: 'embed', src: `https://www.tiktok.com/embed/v2/${m[1]}`, tall: true };
    }
    if (host.endsWith('dailymotion.com') || host === 'dai.ly') {
      const m = u.pathname.match(/\/video\/([a-z0-9]+)/i) || (host === 'dai.ly' && [null, u.pathname.slice(1)]);
      if (m && m[1]) return { kind: 'embed', src: `https://www.dailymotion.com/embed/video/${m[1]}` };
    }
    if (/\.(mp4|webm|ogg|ogv|mov|m4v)(\?|$)/i.test(u.pathname)) return { kind: 'file', src: u.href };
    if (u.protocol === 'https:' || u.protocol === 'http:') return { kind: 'link', href: u.href };
    return null;
  }
  const youtubeSrc = (id, start = 0, autoplay = false) =>
    `https://www.youtube-nocookie.com/embed/${encodeURIComponent(id)}?rel=0&playsinline=1${start ? `&start=${start}` : ''}${autoplay ? '&autoplay=1' : ''}`;

  // Tạo trình phát; trả về { el, seek(sec) }.
  function videoPlayer(url, title) {
    const v = parseVideo(url);
    const frame = (src, tall) => h('iframe', {
      src, title: title || 'Video', loading: 'lazy', allowfullscreen: true, referrerpolicy: 'strict-origin-when-cross-origin',
      allow: 'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; fullscreen',
    });
    if (!v) return { el: h('div', { class: 'video-missing' }, url ? 'Link video không hợp lệ.' : 'Chưa có video.'), seek: null };
    if (v.kind === 'youtube') {
      const f = frame(youtubeSrc(v.id, v.start));
      return { el: h('div', { class: 'video-wrap' }, f), seek: (s) => (f.src = youtubeSrc(v.id, s, true)) };
    }
    if (v.kind === 'embed') {
      const f = frame(v.src);
      return { el: h('div', { class: 'video-wrap' + (v.tall ? ' tall' : '') }, f), seek: v.seek === 'vimeo' ? (s) => (f.src = `${v.src}?autoplay=1#t=${s}s`) : null };
    }
    if (v.kind === 'file' || v.kind === 'asset') {
      const el = h('video', { controls: true, preload: 'metadata', playsinline: true });
      if (v.kind === 'file') el.src = v.src;
      else root.Services.Assets.url(v.ref).then((u) => u && (el.src = u));
      return { el: h('div', { class: 'video-wrap' }, el), seek: (s) => { el.currentTime = s; el.play(); } };
    }
    return { el: h('a', { class: 'btn', href: v.href, target: '_blank', rel: 'noopener noreferrer' }, icon('play'), ' Mở video ở trang gốc'), seek: null };
  }

  // ---------- Trình soạn code ----------
  function codeEditor(value, mode, onChange, { readOnly = false, minHeight } = {}) {
    const ta = h('textarea', { class: 'code-edit', spellcheck: 'false', readOnly }, value || '');
    const wrap = h('div', { class: 'editor' }, ta);
    if (minHeight) wrap.style.setProperty('--min-h', minHeight + 'px');
    let cm = null;
    const api = {
      el: wrap,
      getValue: () => (cm ? cm.getValue() : ta.value),
      setValue: (v) => (cm ? cm.setValue(v) : (ta.value = v)),
      focus: () => (cm ? cm.focus() : ta.focus()),
      refresh: () => cm && cm.refresh(),
    };
    // Ô văn bản thường dùng được ngay; CodeMirror thay thế khi đã gắn vào trang.
    ta.addEventListener('input', () => onChange && onChange(ta.value));
    ta.addEventListener('keydown', (e) => {
      if (e.key === 'Tab') {
        e.preventDefault();
        ta.setRangeText('    ', ta.selectionStart, ta.selectionEnd, 'end');
        onChange && onChange(ta.value);
      }
    });
    if (!root.CodeMirror) return api;
    let tries = 0;
    const init = () => {
      if (!wrap.isConnected) {
        if (tries++ < 120) requestAnimationFrame(init);
        return;
      }
      cm = CodeMirror.fromTextArea(ta, {
        mode: mode === 'cpp' ? 'text/x-c++src' : 'javascript',
        theme: isDark() ? 'material-darker' : 'default',
        lineNumbers: true, indentUnit: 4, tabSize: 4, indentWithTabs: false, readOnly,
        matchBrackets: true, autoCloseBrackets: true, viewportMargin: Infinity,
        extraKeys: { Tab: (c) => c.replaceSelection('    ') },
      });
      cm.on('change', () => onChange && onChange(cm.getValue()));
    };
    requestAnimationFrame(init);
    return api;
  }

  // Ô chọn file ẩn → Promise<File[]>.
  function pickFiles(accept, multiple = false) {
    return new Promise((resolve) => {
      const input = h('input', { type: 'file', accept, multiple, style: { display: 'none' } });
      input.addEventListener('change', () => { resolve([...input.files]); input.remove(); });
      document.body.appendChild(input);
      input.click();
    });
  }

  // Tên file không dấu: "Đồ thị 1" → "do-thi-1".
  const slugify = (s) => String(s || 'file').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/g, 'd').replace(/Đ/g, 'D')
    .replace(/[^\w-]+/g, '-').replace(/^-+|-+$/g, '').toLowerCase() || 'file';

  root.UI = {
    slugify, h, icon, btn, toast, timeAgo, fullTime, isDark, modal, confirmBox, promptBox, renderMarkdown, markdownHeadings, slug,
    parseTime, parseTimestamps, parseVideo, videoPlayer, codeEditor, pickFiles,
  };
})(typeof globalThis !== 'undefined' ? globalThis : this);
