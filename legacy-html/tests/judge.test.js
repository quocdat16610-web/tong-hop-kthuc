// Kiểm thử chấm bài: so sánh output, chấm bằng g++ thật (nếu máy có), bảng xếp hạng.
const test = require('node:test');
const assert = require('node:assert/strict');
const J = require('../js/judge.js');
const local = require('../electron/judge-local.js');

test('so sánh output', () => {
  assert.ok(J.check('tokens', '1 2\n3', '1  2 3\n\n'));
  assert.ok(!J.check('tokens', '1 2', '1 3'));
  assert.ok(J.check('exact', 'a b\nc\n', 'a b  \nc'));
  assert.ok(!J.check('exact', 'a b', 'a  b'));
  assert.ok(J.check('float:1e-6', '0.3333333', '0.33333334'));
  assert.ok(!J.check('float:1e-6', '0.33', '0.34'));
});

test('bảng xếp hạng ICPC', () => {
  const contest = { durationMin: 60, problems: ['A', 'B'] };
  const t0 = 1_000_000;
  const rows = J.standings(contest, [
    { user: 'An', startedAt: t0, subs: [
      { problemId: 'A', time: t0 + 10 * 60000, verdict: 'WA' },
      { problemId: 'A', time: t0 + 12 * 60000, verdict: 'AC' },
      { problemId: 'B', time: t0 + 5 * 60000, verdict: 'CE' },
    ] },
    { user: 'Bình', startedAt: t0 + 3000, subs: [
      { problemId: 'A', time: t0 + 3000 + 20 * 60000, verdict: 'AC' },
      { problemId: 'B', time: t0 + 3000 + 70 * 60000, verdict: 'AC' }, // ngoài giờ
    ] },
  ]);
  assert.equal(rows[0].user, 'Bình');
  assert.equal(rows[0].penalty, 20);
  assert.equal(rows[1].penalty, 32);
  assert.deepEqual(rows[1].cells.B, { solved: false, tries: 0 });
  assert.equal(J.verdictText({ verdict: 'WA', test: 3 }), 'Wrong answer on test 3');
});

const backend = {
  name: 'local', parallel: 2,
  compile: (source) => local.compile({ source, gpp: 'g++', flags: '-O2 -std=c++17' }),
  run: local.run,
  dispose: local.dispose,
};

const SUM = '#include <bits/stdc++.h>\nint main(){long long a,b;std::cin>>a>>b;std::cout<<a+b<<"\\n";}';
const tests = [{ input: '1 2', output: '3' }, { input: '5 7', output: '12' }, { input: '2000000000 2000000000', output: '4000000000' }];

test('chấm bằng g++: AC / WA / TLE / RE / CE', { skip: !require('child_process').spawnSync('g++', ['--version']).stdout }, async () => {
  assert.equal((await J.judge({ source: SUM, tests }, backend)).verdict, 'AC');
  const wa = await J.judge({ source: SUM.replace('long long', 'int'), tests }, backend);
  assert.deepEqual([wa.verdict, wa.test], ['WA', 3]);
  const tle = await J.judge({ source: 'int main(){volatile long long x=0;while(true)x++;}', tests, timeLimit: 300 }, backend);
  assert.deepEqual([tle.verdict, tle.test], ['TLE', 1]);
  const re = await J.judge({ source: '#include <cstdlib>\nint main(){std::abort();}', tests }, backend);
  assert.equal(re.verdict, 'RE');
  const ce = await J.judge({ source: 'int main(){ return x; }', tests }, backend);
  assert.equal(ce.verdict, 'CE');
  assert.match(ce.message, /main\.cpp/);
  const outs = await J.runAll(SUM, ['2 2', '3 4'], backend);
  assert.deepEqual(outs.map((s) => s.trim()), ['4', '7']);
});
