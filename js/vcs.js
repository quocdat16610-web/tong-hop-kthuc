/*
 * vcs.js — Lõi "git mini" cho notebook: commit, nhánh, lịch sử, diff, merge 3 chiều.
 * Không phụ thuộc DOM, dùng được cả trong trình duyệt (window.VCS) và Node (module.exports) để test.
 *
 * Cấu trúc dữ liệu:
 *   Snapshot = { title, description, pages: [ { id, title, chapter, blocks: [ { id, type, ...fields } ] } ] }
 *   Commit   = { id, parents: [id], message, author, time, snapshot }
 *   Repo     = { id, commits: {id: Commit}, branches: {name: id}, remotes: {"ai/nhánh": id},
 *                head: tên nhánh, working: Snapshot }
 */
(function (root) {
  'use strict';

  const clone = (x) => (x === undefined ? undefined : JSON.parse(JSON.stringify(x)));
  const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

  function newId(len = 16) {
    const bytes = new Uint8Array(len / 2);
    (root.crypto || require('crypto').webcrypto).getRandomValues(bytes);
    return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
  }

  function emptySnapshot(title = 'Notebook mới') {
    return { title, description: '', pages: [] };
  }

  function createRepo({ title = 'Notebook mới', author = 'Ẩn danh', snapshot } = {}) {
    const snap = snapshot ? clone(snapshot) : emptySnapshot(title);
    const first = {
      id: newId(),
      parents: [],
      message: 'Khởi tạo notebook',
      author,
      time: Date.now(),
      snapshot: clone(snap),
    };
    return {
      id: newId(),
      commits: { [first.id]: first },
      branches: { main: first.id },
      remotes: {},
      head: 'main',
      working: snap,
    };
  }

  // ---------- refs ----------
  function resolveRef(repo, ref) {
    if (!ref) return null;
    if (repo.branches[ref]) return repo.branches[ref];
    if (repo.remotes[ref]) return repo.remotes[ref];
    if (repo.commits[ref]) return ref;
    const hits = Object.keys(repo.commits).filter((id) => id.startsWith(ref));
    return hits.length === 1 ? hits[0] : null;
  }
  const headCommitId = (repo) => repo.branches[repo.head];
  const headSnapshot = (repo) => repo.commits[headCommitId(repo)].snapshot;
  const isDirty = (repo) => !same(repo.working, headSnapshot(repo));

  function validBranchName(name) {
    return /^[\p{L}\p{N}._-]+(\/[\p{L}\p{N}._-]+)*$/u.test(name) && !name.includes('..');
  }

  function commit(repo, { message, author }) {
    if (!isDirty(repo)) throw new Error('Không có thay đổi nào để commit.');
    const c = {
      id: newId(),
      parents: [headCommitId(repo)],
      message: (message || '').trim() || 'Cập nhật ghi chú',
      author: author || 'Ẩn danh',
      time: Date.now(),
      snapshot: clone(repo.working),
    };
    repo.commits[c.id] = c;
    repo.branches[repo.head] = c.id;
    return c;
  }

  function createBranch(repo, name, fromRef) {
    if (!validBranchName(name)) throw new Error('Tên nhánh không hợp lệ (chỉ chữ, số, . _ - /).');
    if (repo.branches[name]) throw new Error(`Nhánh "${name}" đã tồn tại.`);
    const id = resolveRef(repo, fromRef || repo.head);
    if (!id) throw new Error('Không tìm thấy commit gốc cho nhánh.');
    repo.branches[name] = id;
    return id;
  }

  function checkout(repo, name, { force = false } = {}) {
    if (!repo.branches[name]) throw new Error(`Không có nhánh "${name}".`);
    if (!force && isDirty(repo)) throw new Error('Còn thay đổi chưa commit.');
    repo.head = name;
    repo.working = clone(headSnapshot(repo));
  }

  function deleteBranch(repo, name) {
    if (name === repo.head) throw new Error('Không thể xoá nhánh đang đứng.');
    if (!repo.branches[name]) throw new Error(`Không có nhánh "${name}".`);
    delete repo.branches[name];
  }

  function renameBranch(repo, from, to) {
    if (!repo.branches[from]) throw new Error(`Không có nhánh "${from}".`);
    if (!validBranchName(to)) throw new Error('Tên nhánh không hợp lệ.');
    if (repo.branches[to]) throw new Error(`Nhánh "${to}" đã tồn tại.`);
    repo.branches[to] = repo.branches[from];
    delete repo.branches[from];
    if (repo.head === from) repo.head = to;
  }

  // ---------- lịch sử ----------
  function ancestors(repo, id) {
    const seen = new Set();
    const stack = [id];
    while (stack.length) {
      const cur = stack.pop();
      if (!cur || seen.has(cur) || !repo.commits[cur]) continue;
      seen.add(cur);
      stack.push(...repo.commits[cur].parents);
    }
    return seen;
  }

  const isAncestor = (repo, a, b) => ancestors(repo, b).has(a);

  // Tổ tiên chung gần nhất (chọn commit mới nhất trong tập tổ tiên chung không bị commit chung khác "che").
  function mergeBase(repo, a, b) {
    const A = ancestors(repo, a);
    const common = [...ancestors(repo, b)].filter((id) => A.has(id));
    if (!common.length) return null;
    const best = common.filter(
      (c) => !common.some((o) => o !== c && repo.commits[o].parents.length && ancestors(repo, o).has(c))
    );
    best.sort((x, y) => repo.commits[y].time - repo.commits[x].time);
    return best[0];
  }

  // Sắp xếp topo (con trước cha), ưu tiên thời gian mới hơn — dùng cho màn hình lịch sử.
  function log(repo, refs) {
    const starts = (refs || [...Object.values(repo.branches), ...Object.values(repo.remotes)]).filter(Boolean);
    const reach = new Set();
    starts.forEach((s) => ancestors(repo, s).forEach((x) => reach.add(x)));
    const childCount = {};
    reach.forEach((id) => (childCount[id] = 0));
    reach.forEach((id) => repo.commits[id].parents.forEach((p) => reach.has(p) && childCount[p]++));
    const ready = [...reach].filter((id) => childCount[id] === 0);
    const out = [];
    while (ready.length) {
      ready.sort((x, y) => repo.commits[x].time - repo.commits[y].time);
      const id = ready.pop();
      out.push(repo.commits[id]);
      repo.commits[id].parents.forEach((p) => {
        if (reach.has(p) && --childCount[p] === 0) ready.push(p);
      });
    }
    return out;
  }

  // Tính các làn (lane) để vẽ đồ thị commit giống `git log --graph`.
  function graphLayout(commits) {
    let lanes = [];
    return commits.map((c) => {
      const before = lanes.slice();
      let col = before.indexOf(c.id);
      if (col === -1) {
        col = before.indexOf(null);
        if (col === -1) col = before.length;
      }
      const after = before.slice();
      after[col] = c.parents[0] || null;
      for (let k = 0; k < after.length; k++) if (k !== col && after[k] === c.id) after[k] = null;
      c.parents.slice(1).forEach((p) => {
        if (!after.includes(p)) {
          const free = after.indexOf(null);
          if (free === -1) after.push(p);
          else after[free] = p;
        }
      });
      while (after.length && after[after.length - 1] === null) after.pop();
      lanes = after;
      return { commit: c, col, before, after };
    });
  }

  // ---------- diff ----------
  // Diff dòng bằng LCS (đủ nhanh cho ghi chú vài nghìn dòng).
  function diffLines(a, b) {
    const x = (a || '').split('\n');
    const y = (b || '').split('\n');
    const n = x.length;
    const m = y.length;
    if (n * m > 4e6) return [...x.map((t) => ({ op: '-', text: t })), ...y.map((t) => ({ op: '+', text: t }))];
    const dp = Array.from({ length: n + 1 }, () => new Uint32Array(m + 1));
    for (let i = n - 1; i >= 0; i--)
      for (let j = m - 1; j >= 0; j--)
        dp[i][j] = x[i] === y[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1]);
    const out = [];
    let i = 0;
    let j = 0;
    while (i < n && j < m) {
      if (x[i] === y[j]) out.push({ op: ' ', text: x[i++] }), j++;
      else if (dp[i + 1][j] >= dp[i][j + 1]) out.push({ op: '-', text: x[i++] });
      else out.push({ op: '+', text: y[j++] });
    }
    while (i < n) out.push({ op: '-', text: x[i++] });
    while (j < m) out.push({ op: '+', text: y[j++] });
    return out;
  }

  const byId = (arr) => Object.fromEntries((arr || []).map((x) => [x.id, x]));

  // So sánh 2 snapshot, trả về danh sách thay đổi có cấu trúc.
  function diffSnapshots(a, b) {
    a = a || emptySnapshot('');
    b = b || emptySnapshot('');
    const changes = [];
    ['title', 'description'].forEach((f) => {
      if (!same(a[f], b[f])) changes.push({ kind: 'meta', field: f, before: a[f], after: b[f] });
    });
    const pa = byId(a.pages);
    const pb = byId(b.pages);
    if (!same(a.pages.filter((p) => pb[p.id]).map((p) => p.id), b.pages.filter((p) => pa[p.id]).map((p) => p.id))) {
      changes.push({ kind: 'reorder-pages' });
    }
    b.pages.forEach((p) => {
      if (!pa[p.id]) changes.push({ kind: 'page-added', page: p });
    });
    a.pages.forEach((p) => {
      if (!pb[p.id]) changes.push({ kind: 'page-removed', page: p });
    });
    a.pages.forEach((p) => {
      const q = pb[p.id];
      if (!q || same(p, q)) return;
      const fields = ['title', 'chapter'].filter((f) => !same(p[f], q[f]));
      const ba = byId(p.blocks);
      const bb = byId(q.blocks);
      const blocks = [];
      q.blocks.forEach((blk) => !ba[blk.id] && blocks.push({ kind: 'block-added', block: blk }));
      p.blocks.forEach((blk) => !bb[blk.id] && blocks.push({ kind: 'block-removed', block: blk }));
      p.blocks.forEach((blk) => {
        if (bb[blk.id] && !same(blk, bb[blk.id])) blocks.push({ kind: 'block-changed', before: blk, after: bb[blk.id] });
      });
      const ordA = p.blocks.filter((x) => bb[x.id]).map((x) => x.id);
      const ordB = q.blocks.filter((x) => ba[x.id]).map((x) => x.id);
      if (!same(ordA, ordB)) blocks.push({ kind: 'reorder-blocks' });
      changes.push({ kind: 'page-changed', before: p, after: q, fields, blocks });
    });
    return changes;
  }

  function summarize(changes) {
    const s = { added: 0, removed: 0, changed: 0 };
    changes.forEach((c) => {
      if (c.kind === 'page-added') s.added++;
      else if (c.kind === 'page-removed') s.removed++;
      else s.changed++;
    });
    return s;
  }

  // ---------- merge 3 chiều ----------
  // Trả về { snapshot, conflicts }. Ở chỗ xung đột, snapshot tạm giữ phiên bản "của mình" (ours).
  function merge3(base, ours, theirs) {
    base = base || emptySnapshot('');
    const conflicts = [];
    const pick = (b, o, t, onConflict) => {
      if (same(o, t)) return clone(o);
      if (same(o, b)) return clone(t);
      if (same(t, b)) return clone(o);
      onConflict();
      return clone(o);
    };

    const result = { pages: [] };
    ['title', 'description'].forEach((f) => {
      result[f] = pick(base[f], ours[f], theirs[f], () =>
        conflicts.push({ type: 'field', target: { field: f }, label: `Thông tin notebook › ${f === 'title' ? 'tiêu đề' : 'mô tả'}`, base: base[f], ours: ours[f], theirs: theirs[f] })
      );
    });

    const pb = byId(base.pages);
    const po = byId(ours.pages);
    const pt = byId(theirs.pages);
    const order = mergeOrder(base.pages.map((p) => p.id), ours.pages.map((p) => p.id), theirs.pages.map((p) => p.id));

    order.forEach((pid) => {
      const b = pb[pid];
      const o = po[pid];
      const t = pt[pid];
      const name = (o || t || b).title || '(trang không tên)';
      if (!b) {
        // Thêm mới ở một hoặc cả hai bên.
        if (o && t && !same(o, t)) {
          result.pages.push(mergePage({ id: pid, title: o.title, chapter: o.chapter, blocks: [] }, o, t, conflicts, name));
        } else result.pages.push(clone(o || t));
        return;
      }
      if (!o && !t) return; // cả hai cùng xoá
      if (!o || !t) {
        const alive = o || t;
        if (same(alive, b)) return; // một bên xoá, bên kia không sửa → xoá
        conflicts.push({ type: 'page-delete', target: { pageId: pid }, label: `Trang "${name}" bị ${o ? 'họ' : 'bạn'} xoá nhưng bên kia có sửa`, base: b, ours: o || null, theirs: t || null, theirsIndex: theirs.pages.findIndex((p) => p.id === pid) });
        if (o) result.pages.push(clone(o));
        return;
      }
      result.pages.push(mergePage(b, o, t, conflicts, name));
    });

    return { snapshot: result, conflicts };

    function mergePage(b, o, t, conflicts, name) {
      const page = { id: o.id };
      ['title', 'chapter'].forEach((f) => {
        page[f] = pick(b[f], o[f], t[f], () =>
          conflicts.push({ type: 'field', target: { pageId: o.id, field: f }, label: `Trang "${name}" › ${f === 'title' ? 'tiêu đề' : 'chương'}`, base: b[f], ours: o[f], theirs: t[f] })
        );
      });
      const bb = byId(b.blocks);
      const bo = byId(o.blocks);
      const bt = byId(t.blocks);
      page.blocks = [];
      mergeOrder(b.blocks.map((x) => x.id), o.blocks.map((x) => x.id), t.blocks.map((x) => x.id)).forEach((bid) => {
        const B = bb[bid];
        const O = bo[bid];
        const T = bt[bid];
        const blkLabel = `Trang "${name}" › khối ${blockName(O || T || B)}`;
        if (!B) {
          if (O && T && !same(O, T)) page.blocks.push(mergeBlock({ id: bid, type: O.type }, O, T, blkLabel));
          else page.blocks.push(clone(O || T));
          return;
        }
        if (!O && !T) return;
        if (!O || !T) {
          const alive = O || T;
          if (same(alive, B)) return;
          conflicts.push({ type: 'block-delete', target: { pageId: o.id, blockId: bid }, label: `${blkLabel} bị ${O ? 'họ' : 'bạn'} xoá nhưng bên kia có sửa`, base: B, ours: O || null, theirs: T || null, theirsIndex: t.blocks.findIndex((x) => x.id === bid) });
          if (O) page.blocks.push(clone(O));
          return;
        }
        page.blocks.push(mergeBlock(B, O, T, blkLabel));
      });
      return page;

      function mergeBlock(B, O, T, blkLabel) {
        const out = {};
        const keys = new Set([...Object.keys(B), ...Object.keys(O), ...Object.keys(T)]);
        keys.forEach((k) => {
          const v = pick(B[k], O[k], T[k], () =>
            conflicts.push({ type: 'field', target: { pageId: o.id, blockId: O.id, field: k }, label: `${blkLabel} › ${k}`, base: B[k], ours: O[k], theirs: T[k] })
          );
          if (v !== undefined) out[k] = v;
        });
        return out;
      }
    }
  }

  function blockName(b) {
    if (!b) return '';
    const map = { markdown: 'ghi chú', video: 'video', code: 'code C++', sim: 'mô phỏng' };
    const t = b.title || (b.text || '').split('\n')[0].slice(0, 40);
    return `${map[b.type] || b.type}${t ? ` "${t}"` : ''}`;
  }

  // Gộp thứ tự 2 danh sách id: giữ thứ tự của "ours", chèn phần tử chỉ có ở "theirs" ngay sau phần tử đứng trước nó.
  function mergeOrder(base, ours, theirs) {
    const result = ours.slice();
    theirs.forEach((id, i) => {
      // Phần tử có trong base mà ours đã xoá vẫn được đưa vào để merge3 quyết định (xoá hay xung đột).
      if (result.includes(id)) return;
      let pos = 0;
      for (let k = i - 1; k >= 0; k--) {
        const at = result.indexOf(theirs[k]);
        if (at !== -1) {
          pos = at + 1;
          break;
        }
      }
      result.splice(pos, 0, id);
    });
    base.forEach((id) => {
      if (!result.includes(id)) result.push(id);
    });
    return result;
  }

  // Áp dụng lựa chọn cho từng xung đột. choice: 'ours' | 'theirs' | { value }.
  function applyResolutions(snapshot, conflicts, choices) {
    const snap = clone(snapshot);
    conflicts.forEach((c, i) => {
      const ch = choices[i];
      if (ch === undefined) throw new Error(`Chưa giải quyết xung đột: ${c.label}`);
      const value = ch === 'ours' ? c.ours : ch === 'theirs' ? c.theirs : ch.value;
      const { pageId, blockId, field } = c.target;
      if (c.type === 'field') {
        let obj = snap;
        if (pageId) obj = snap.pages.find((p) => p.id === pageId);
        if (obj && blockId) obj = obj.blocks.find((x) => x.id === blockId);
        if (!obj) return;
        if (value === undefined) delete obj[field];
        else obj[field] = clone(value);
      } else if (c.type === 'page-delete') {
        const idx = snap.pages.findIndex((p) => p.id === pageId);
        if (value == null) {
          if (idx !== -1) snap.pages.splice(idx, 1);
        } else if (idx === -1) snap.pages.splice(Math.min(c.theirsIndex, snap.pages.length), 0, clone(value));
        else snap.pages[idx] = clone(value);
      } else if (c.type === 'block-delete') {
        const page = snap.pages.find((p) => p.id === pageId);
        if (!page) return;
        const idx = page.blocks.findIndex((x) => x.id === blockId);
        if (value == null) {
          if (idx !== -1) page.blocks.splice(idx, 1);
        } else if (idx === -1) page.blocks.splice(Math.min(c.theirsIndex, page.blocks.length), 0, clone(value));
        else page.blocks[idx] = clone(value);
      }
    });
    return snap;
  }

  // Chuẩn bị merge nhánh/ref `from` vào nhánh hiện tại.
  function prepareMerge(repo, from) {
    if (isDirty(repo)) throw new Error('Hãy commit hoặc huỷ thay đổi trước khi merge.');
    const theirsId = resolveRef(repo, from);
    if (!theirsId) throw new Error(`Không tìm thấy "${from}".`);
    const oursId = headCommitId(repo);
    if (theirsId === oursId || isAncestor(repo, theirsId, oursId)) return { kind: 'up-to-date' };
    if (isAncestor(repo, oursId, theirsId)) return { kind: 'fast-forward', theirsId };
    const baseId = mergeBase(repo, oursId, theirsId);
    const r = merge3(baseId ? repo.commits[baseId].snapshot : null, repo.commits[oursId].snapshot, repo.commits[theirsId].snapshot);
    return { kind: 'merge', oursId, theirsId, baseId, ...r };
  }

  function finishMerge(repo, prep, { snapshot, author, message, from }) {
    if (prep.kind === 'fast-forward') {
      repo.branches[repo.head] = prep.theirsId;
      repo.working = clone(repo.commits[prep.theirsId].snapshot);
      return repo.commits[prep.theirsId];
    }
    const c = {
      id: newId(),
      parents: [prep.oursId, prep.theirsId],
      message: message || `Merge "${from}" vào "${repo.head}"`,
      author: author || 'Ẩn danh',
      time: Date.now(),
      snapshot: clone(snapshot),
    };
    repo.commits[c.id] = c;
    repo.branches[repo.head] = c.id;
    repo.working = clone(snapshot);
    return c;
  }

  // ---------- chia sẻ / fetch ----------
  // Xuất repo (toàn bộ hoặc chỉ một số nhánh) thành gói chia sẻ.
  function exportBundle(repo, { branches, author } = {}) {
    const names = branches || Object.keys(repo.branches);
    const refs = {};
    names.forEach((n) => (refs[n] = repo.branches[n]));
    const keep = new Set();
    Object.values(refs).forEach((id) => ancestors(repo, id).forEach((x) => keep.add(x)));
    const commits = {};
    keep.forEach((id) => (commits[id] = repo.commits[id]));
    return {
      format: 'dsa-notebook',
      version: 1,
      repoId: repo.id,
      title: repo.working.title,
      sharedBy: author || 'Ẩn danh',
      sharedAt: Date.now(),
      head: names.includes(repo.head) ? repo.head : names[0],
      branches: refs,
      commits,
    };
  }

  function validateBundle(b) {
    if (!b || b.format !== 'dsa-notebook' || typeof b.commits !== 'object' || typeof b.branches !== 'object')
      throw new Error('File không phải notebook DSA hợp lệ.');
    Object.values(b.commits).forEach((c) => {
      if (!c || typeof c.id !== 'string' || !Array.isArray(c.parents) || !c.snapshot || !Array.isArray(c.snapshot.pages))
        throw new Error('Dữ liệu commit bị hỏng.');
    });
    Object.values(b.branches).forEach((id) => {
      if (!b.commits[id]) throw new Error('Nhánh trỏ tới commit không tồn tại.');
    });
    return b;
  }

  // Tạo repo mới (fork) từ gói chia sẻ.
  function repoFromBundle(b, { keepId = false } = {}) {
    validateBundle(b);
    const repo = {
      id: keepId ? b.repoId : newId(),
      commits: clone(b.commits),
      branches: clone(b.branches),
      remotes: {},
      head: b.head && b.branches[b.head] ? b.head : Object.keys(b.branches)[0],
      working: null,
      upstream: b.repoId,
    };
    repo.working = clone(repo.commits[repo.branches[repo.head]].snapshot);
    return repo;
  }

  // Giống `git fetch`: thêm commit và tạo nhánh remote "tên-người/nhánh".
  function fetchBundle(repo, b, remoteName) {
    validateBundle(b);
    let added = 0;
    Object.values(b.commits).forEach((c) => {
      if (!repo.commits[c.id]) {
        repo.commits[c.id] = clone(c);
        added++;
      }
    });
    const prefix = (remoteName || 'remote').replace(/[^\p{L}\p{N}._-]+/gu, '-');
    const refs = [];
    Object.entries(b.branches).forEach(([n, id]) => {
      repo.remotes[`${prefix}/${n}`] = id;
      refs.push(`${prefix}/${n}`);
    });
    return { added, refs };
  }

  const api = {
    newId, clone, same, emptySnapshot, createRepo, resolveRef, headCommitId, headSnapshot, isDirty,
    validBranchName, commit, createBranch, checkout, deleteBranch, renameBranch, ancestors, isAncestor,
    mergeBase, log, graphLayout, diffLines, diffSnapshots, summarize, merge3, mergeOrder, applyResolutions,
    prepareMerge, finishMerge, exportBundle, validateBundle, repoFromBundle, fetchBundle, blockName,
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.VCS = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
