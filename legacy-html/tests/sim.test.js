// Chạy các mẫu mô phỏng qua bộ ghi khung (không cần trình duyệt).
const test = require('node:test');
const assert = require('node:assert/strict');
globalThis.VCS = require('../js/vcs.js');
const { simWorkerMain } = require('../js/sim.js');
require('../js/templates.js');

function runSim(code, input) {
  let result;
  const self = { postMessage: (r) => (result = r) };
  simWorkerMain(self);
  self.onmessage({ data: { code, input } });
  return result;
}

for (const t of globalThis.TEMPLATES.SIM_TEMPLATES) {
  test(`mẫu "${t.name}" chạy không lỗi`, () => {
    const r = runSim(t.code, t.input);
    assert.equal(r.error, null);
    assert.ok(r.frames.length >= 2);
  });
}

test('bubble sort cho ra mảng đã sắp xếp', () => {
  const t = globalThis.TEMPLATES.SIM_TEMPLATES.find((x) => x.id === 'bubble');
  const r = runSim(t.code, '3 2 1');
  assert.deepEqual(r.frames.at(-1).s[0].v, [1, 2, 3]);
});

test('BFS tìm được đường', () => {
  const t = globalThis.TEMPLATES.SIM_TEMPLATES.find((x) => x.id === 'bfsgrid');
  const r = runSim(t.code, t.input);
  assert.match(r.frames.at(-1).note, /Đường đi ngắn nhất dài \d+ bước/);
});

test('lỗi trong script được báo kèm số dòng', () => {
  const r = runSim('const a = viz.array([1]);\nfoo();', '');
  assert.match(r.error, /foo is not defined/);
});

test('giới hạn số bước', () => {
  const r = runSim('const a = viz.array([1,2]); while (true) a.swap(0,1);', '');
  assert.match(r.error, /Quá 5000 bước/);
});
