// Kiểm thử phần IDE: đọc GDB/MI, chạy tương tác, gỡ lỗi từng dòng bằng gdb (nếu máy có).
const test = require('node:test');
const assert = require('node:assert/strict');
const { spawnSync } = require('child_process');
const { parseLine } = require('../electron/mi.js');
const judge = require('../electron/judge-local.js');
const { DebugSession } = require('../electron/ide.js');

test('đọc dòng GDB/MI', () => {
  const r = parseLine('12^done,variables=[{name="a",value="1"},{name="s",value="\\"hi\\\\n\\""}],stack=[frame={level="0",line="5"}]');
  assert.equal(r.token, 12);
  assert.equal(r.cls, 'done');
  assert.deepEqual(r.data.variables, [{ name: 'a', value: '1' }, { name: 's', value: '"hi\\n"' }]);
  assert.deepEqual(r.data.stack, [{ level: '0', line: '5' }]);
  const s = parseLine('*stopped,reason="breakpoint-hit",frame={func="main",args=[],file="main.cpp",line="7"},thread-id="1"');
  assert.equal(s.kind, '*');
  assert.equal(s.data.frame.line, '7');
  assert.equal(parseLine('~"Hello\\n"').text, 'Hello\n');
  assert.equal(parseLine('(gdb) '), null);
});

const hasGpp = !!spawnSync('g++', ['--version']).stdout;
const hasGdb = hasGpp && !!spawnSync('gdb', ['--version']).stdout;

test('chạy tương tác: gõ input khi chương trình đang chạy', { skip: !hasGpp }, async () => {
  const c = await judge.compile({ source: '#include <iostream>\nint main(){ std::cout << "n? "; int n; std::cin >> n; std::cout << n * 2 << "\\n"; }', gpp: 'g++', flags: '-std=c++17', unbuffered: true });
  assert.ok(c.ok, c.error);
  const child = judge.spawnProgram(c.id);
  let out = '';
  const done = new Promise((resolve) => child.on('close', resolve));
  child.stdout.on('data', (d) => {
    out += String(d).replace(/\r\n/g, '\n'); // Windows xuống dòng bằng \r\n
    if (out === 'n? ') child.stdin.write('21\n');
  });
  const code = await done;
  assert.equal(code, 0);
  assert.equal(out, 'n? 42\n');
  judge.dispose(c.id);
});

test('gỡ lỗi: breakpoint, chạy từng dòng, xem biến, kết thúc', { skip: !hasGdb }, async () => {
  const src = [
    '#include <bits/stdc++.h>', //   1
    'using namespace std;', //       2
    'int sq(int x) {', //            3
    '    return x * x;', //          4
    '}', //                          5
    'int main() {', //               6
    '    int n; cin >> n;', //       7
    '    int s = 0;', //             8
    '    for (int i = 1; i <= n; i++)', // 9
    '        s += sq(i);', //        10
    '    cout << s << endl;', //     11
    '}', //                          12
  ].join('\n');
  const c = await judge.compile({ source: src, gpp: 'g++', flags: '-std=c++17', debug: true });
  assert.ok(c.ok, c.error);
  const events = [];
  let wake = null;
  const next = (type) => new Promise((resolve) => {
    const check = () => {
      const i = events.findIndex((e) => e.type === type);
      if (i !== -1) return resolve(events.splice(0, i + 1).pop());
      wake = check;
    };
    check();
  });
  const s = new DebugSession({
    gdb: 'gdb', progId: c.id, input: '3\n', breakpoints: [10],
    send: (e) => { events.push(e); if (wake) { const w = wake; wake = null; w(); } },
  });
  await s.start();
  let st = await next('stopped');
  assert.equal(st.line, 10);
  assert.equal(st.func, 'main');
  const val = (name) => (st.locals.find((v) => v.name === name) || {}).value;
  assert.equal(val('n'), '3');
  assert.equal(val('i'), '1');
  await s.control('step'); // vào hàm sq
  st = await next('stopped');
  assert.equal(st.func, 'sq');
  assert.equal(st.line, 4);
  assert.deepEqual(st.frames.map((f) => f.func), ['sq', 'main']);
  await s.control('finish');
  st = await next('stopped');
  assert.equal(st.func, 'main');
  await s.removeBreakpoint(10);
  await s.control('continue');
  const ex = await next('exited');
  assert.equal(ex.code, 0);
  assert.equal(ex.output.trim(), '14');
  await next('ended');
});
