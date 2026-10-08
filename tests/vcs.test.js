// Chạy: node --test tests/
const test = require('node:test');
const assert = require('node:assert/strict');
const V = require('../js/vcs.js');

const page = (id, title, blocks = []) => ({ id, title, chapter: '', blocks });
const md = (id, text) => ({ id, type: 'markdown', text });

function setup() {
  const repo = V.createRepo({ title: 'DSA', author: 'An' });
  repo.working.pages.push(page('p1', 'Mảng', [md('b1', 'dòng 1\ndòng 2'), md('b2', 'hai')]));
  V.commit(repo, { message: 'thêm trang', author: 'An' });
  return repo;
}

test('commit, dirty và lịch sử', () => {
  const repo = setup();
  assert.equal(V.isDirty(repo), false);
  assert.throws(() => V.commit(repo, { message: 'x' }), /Không có thay đổi/);
  repo.working.pages[0].title = 'Mảng 1 chiều';
  assert.equal(V.isDirty(repo), true);
  V.commit(repo, { message: 'đổi tên' });
  assert.equal(V.log(repo).length, 3);
});

test('nhánh và checkout', () => {
  const repo = setup();
  V.createBranch(repo, 'ghi-chu-cua-binh');
  V.checkout(repo, 'ghi-chu-cua-binh');
  repo.working.pages.push(page('p2', 'Stack'));
  assert.throws(() => V.checkout(repo, 'main'), /chưa commit/);
  V.commit(repo, { message: 'stack' });
  V.checkout(repo, 'main');
  assert.equal(repo.working.pages.length, 1);
  assert.throws(() => V.createBranch(repo, 'a b'), /không hợp lệ/);
  assert.throws(() => V.deleteBranch(repo, 'main'), /đang đứng/);
});

test('merge fast-forward', () => {
  const repo = setup();
  V.createBranch(repo, 'f');
  V.checkout(repo, 'f');
  repo.working.pages.push(page('p2', 'Queue'));
  V.commit(repo, { message: 'q' });
  V.checkout(repo, 'main');
  const prep = V.prepareMerge(repo, 'f');
  assert.equal(prep.kind, 'fast-forward');
  V.finishMerge(repo, prep, {});
  assert.equal(repo.working.pages.length, 2);
  assert.equal(V.prepareMerge(repo, 'f').kind, 'up-to-date');
});

test('merge 3 chiều không xung đột', () => {
  const repo = setup();
  V.createBranch(repo, 'f');
  V.checkout(repo, 'f');
  repo.working.pages[0].blocks[0].text = 'dòng 1 sửa\ndòng 2';
  repo.working.pages.push(page('p3', 'Đồ thị'));
  V.commit(repo, { message: 'f' });
  V.checkout(repo, 'main');
  repo.working.pages[0].blocks.push(md('b3', 'ba'));
  repo.working.pages[0].title = 'Mảng (main)';
  V.commit(repo, { message: 'm' });
  const prep = V.prepareMerge(repo, 'f');
  assert.equal(prep.kind, 'merge');
  assert.equal(prep.conflicts.length, 0);
  const c = V.finishMerge(repo, prep, { snapshot: prep.snapshot, from: 'f' });
  assert.equal(c.parents.length, 2);
  const p = repo.working.pages[0];
  assert.equal(p.title, 'Mảng (main)');
  assert.equal(p.blocks[0].text, 'dòng 1 sửa\ndòng 2');
  assert.deepEqual(p.blocks.map((b) => b.id), ['b1', 'b2', 'b3']);
  assert.deepEqual(repo.working.pages.map((x) => x.id), ['p1', 'p3']);
});

test('merge có xung đột + giải quyết', () => {
  const repo = setup();
  V.createBranch(repo, 'f');
  V.checkout(repo, 'f');
  repo.working.pages[0].blocks[1].text = 'của họ';
  repo.working.pages[0].blocks.splice(0, 1, { ...repo.working.pages[0].blocks[0], text: 'họ sửa b1' });
  V.commit(repo, { message: 'f' });
  V.checkout(repo, 'main');
  repo.working.pages[0].blocks[1].text = 'của tôi';
  repo.working.pages[0].blocks.splice(0, 1); // xoá b1 mà bên kia sửa
  V.commit(repo, { message: 'm' });
  const prep = V.prepareMerge(repo, 'f');
  assert.equal(prep.conflicts.length, 2);
  const kinds = prep.conflicts.map((c) => c.type).sort();
  assert.deepEqual(kinds, ['block-delete', 'field']);
  const choices = prep.conflicts.map((c) => (c.type === 'field' ? { value: 'gộp' } : 'theirs'));
  const snap = V.applyResolutions(prep.snapshot, prep.conflicts, choices);
  assert.deepEqual(snap.pages[0].blocks.map((b) => [b.id, b.text]), [['b1', 'họ sửa b1'], ['b2', 'gộp']]);
});

test('chia sẻ: fork và fetch nhánh remote', () => {
  const repo = setup();
  const bundle = JSON.parse(JSON.stringify(V.exportBundle(repo, { author: 'An' })));
  const fork = V.repoFromBundle(bundle);
  assert.notEqual(fork.id, repo.id);
  fork.working.pages[0].title = 'Bình sửa';
  V.commit(fork, { message: 'bình' });
  const back = V.fetchBundle(repo, V.exportBundle(fork), 'Bình');
  assert.equal(back.added, 1);
  assert.deepEqual(back.refs, ['Bình/main']);
  const prep = V.prepareMerge(repo, 'Bình/main');
  assert.equal(prep.kind, 'fast-forward');
  assert.throws(() => V.validateBundle({ format: 'x' }), /không phải/);
});

test('diff dòng và diff snapshot', () => {
  const d = V.diffLines('a\nb\nc', 'a\nx\nc');
  assert.deepEqual(d.map((x) => x.op + x.text), [' a', '-b', '+x', ' c']);
  const a = { title: 't', description: '', pages: [page('p1', 'A', [md('b1', '1')])] };
  const b = { title: 't2', description: '', pages: [page('p1', 'A', [md('b1', '2')]), page('p2', 'B')] };
  const kinds = V.diffSnapshots(a, b).map((c) => c.kind);
  assert.deepEqual(kinds, ['meta', 'page-added', 'page-changed']);
});

test('graphLayout vẽ được nhánh rẽ và merge', () => {
  const repo = setup();
  V.createBranch(repo, 'f');
  V.checkout(repo, 'f');
  repo.working.title = 'F';
  V.commit(repo, { message: 'f' });
  V.checkout(repo, 'main');
  repo.working.description = 'M';
  V.commit(repo, { message: 'm' });
  const prep = V.prepareMerge(repo, 'f');
  V.finishMerge(repo, prep, { snapshot: prep.snapshot });
  const rows = V.graphLayout(V.log(repo));
  assert.equal(rows[0].commit.parents.length, 2);
  assert.ok(Math.max(...rows.map((r) => r.col)) >= 1);
});
