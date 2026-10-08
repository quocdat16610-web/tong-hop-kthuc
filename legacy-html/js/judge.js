/*
 * judge.js — Chấm bài kiểu Codeforces và bảng xếp hạng kiểu ICPC.
 * Không phụ thuộc DOM; "backend" (g++ trên máy hoặc online) được truyền vào.
 *
 * backend = {
 *   name,
 *   compile(source) -> { ok, id, error }
 *   run(id, input, timeLimitMs) -> { stdout, stderr, exitCode, timeMs, timedOut, compileError? }
 *   dispose(id)
 * }
 */
(function (root) {
  'use strict';

  const VERDICT = {
    AC: 'Accepted',
    WA: 'Wrong answer',
    TLE: 'Time limit exceeded',
    RE: 'Runtime error',
    CE: 'Compilation error',
    NT: 'Chưa có test',
    ERR: 'Lỗi hệ thống chấm',
  };

  function verdictText(r) {
    if (!r) return '';
    const base = VERDICT[r.verdict] || r.verdict;
    return r.test && r.verdict !== 'AC' && r.verdict !== 'CE' ? `${base} on test ${r.test}` : base;
  }

  // ---------- So sánh output ----------
  const tokens = (s) => String(s || '').split(/\s+/).filter(Boolean);
  function check(checker, expected, got) {
    if (checker === 'exact') {
      const norm = (s) => String(s || '').replace(/\r\n/g, '\n').split('\n').map((l) => l.replace(/\s+$/, '')).join('\n').replace(/\n+$/, '');
      return norm(expected) === norm(got);
    }
    const a = tokens(expected);
    const b = tokens(got);
    if (a.length !== b.length) return false;
    if (checker && checker.startsWith('float')) {
      const eps = Number(checker.split(':')[1]) || 1e-6;
      return a.every((x, i) => {
        if (x === b[i]) return true;
        const p = Number(x);
        const q = Number(b[i]);
        if (Number.isNaN(p) || Number.isNaN(q)) return false;
        return Math.abs(p - q) <= eps * Math.max(1, Math.abs(p));
      });
    }
    return a.every((x, i) => x === b[i]);
  }

  // Chạy song song tối đa `limit` việc, dừng sớm khi `stop()` trả true.
  async function pool(items, limit, fn) {
    let next = 0;
    let stopped = false;
    const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
      while (!stopped && next < items.length) {
        const i = next++;
        if (await fn(items[i], i)) stopped = true;
      }
    });
    await Promise.all(workers);
  }

  // ---------- Chấm một bài ----------
  async function judge({ source, tests, timeLimit = 1000, checker = 'tokens' }, backend, onProgress) {
    if (!tests || !tests.length) return { verdict: 'NT' };
    const comp = await backend.compile(source);
    if (!comp.ok) return { verdict: 'CE', message: comp.error || '' };
    const results = new Array(tests.length);
    let firstBad = Infinity;
    let done = 0;
    try {
      await pool(tests, backend.parallel || 1, async (t, i) => {
        if (i > firstBad) return true;
        const r = await backend.run(comp.id, t.input, timeLimit);
        done++;
        onProgress && onProgress(done, tests.length);
        let verdict = 'AC';
        if (r.compileError !== undefined) verdict = 'CE';
        else if (r.timedOut || r.timeMs > timeLimit) verdict = 'TLE';
        else if (r.exitCode !== 0) verdict = 'RE';
        else if (!check(checker, t.output, r.stdout)) verdict = 'WA';
        results[i] = { verdict, timeMs: r.timeMs || 0, stdout: r.stdout, stderr: r.stderr, exitCode: r.exitCode, compileError: r.compileError };
        if (verdict !== 'AC') {
          firstBad = Math.min(firstBad, i);
          return true;
        }
        return false;
      });
    } finally {
      backend.dispose && backend.dispose(comp.id);
    }
    const maxTime = Math.max(0, ...results.filter(Boolean).map((r) => r.timeMs));
    if (firstBad === Infinity) return { verdict: 'AC', timeMs: maxTime, tests: tests.length };
    const bad = results[firstBad];
    if (bad.verdict === 'CE') return { verdict: 'CE', message: bad.compileError };
    return {
      verdict: bad.verdict,
      test: firstBad + 1,
      timeMs: bad.timeMs,
      input: tests[firstBad].input,
      expected: tests[firstBad].output,
      got: bad.stdout,
      stderr: bad.stderr,
      exitCode: bad.exitCode,
    };
  }

  // Chạy chương trình trên danh sách input (dùng để sinh test bằng code chuẩn / generator).
  async function runAll(source, inputs, backend, { timeLimit = 5000, onProgress } = {}) {
    const comp = await backend.compile(source);
    if (!comp.ok) throw new Error('Lỗi biên dịch:\n' + (comp.error || ''));
    const out = new Array(inputs.length);
    let done = 0;
    try {
      await pool(inputs, backend.parallel || 1, async (input, i) => {
        const r = await backend.run(comp.id, input, timeLimit);
        if (r.compileError !== undefined) throw new Error('Lỗi biên dịch:\n' + r.compileError);
        if (r.timedOut) throw new Error(`Chạy quá ${timeLimit} ms ở test ${i + 1}`);
        if (r.exitCode !== 0) throw new Error(`Lỗi khi chạy test ${i + 1} (mã thoát ${r.exitCode})\n${r.stderr || ''}`);
        out[i] = r.stdout;
        onProgress && onProgress(++done, inputs.length);
        return false;
      });
    } finally {
      backend.dispose && backend.dispose(comp.id);
    }
    return out;
  }

  // ---------- Bảng xếp hạng ICPC ----------
  // participants: [{ user, startedAt, subs: [{ problemId, time, verdict }] }]
  function standings(contest, participants) {
    const dur = (contest.durationMin || 120) * 60000;
    const rows = participants.map((p) => {
      const cells = {};
      let solved = 0;
      let penalty = 0;
      let last = 0;
      contest.problems.forEach((pid) => {
        const subs = (p.subs || [])
          .filter((s) => s.problemId === pid && s.time >= p.startedAt && s.time <= p.startedAt + dur && s.verdict !== 'CE')
          .sort((a, b) => a.time - b.time);
        const acIdx = subs.findIndex((s) => s.verdict === 'AC');
        if (acIdx === -1) cells[pid] = { solved: false, tries: subs.length };
        else {
          const minutes = Math.floor((subs[acIdx].time - p.startedAt) / 60000);
          cells[pid] = { solved: true, tries: acIdx, minutes };
          solved++;
          penalty += minutes + 20 * acIdx;
          last = Math.max(last, subs[acIdx].time);
        }
      });
      return { user: p.user, solved, penalty, last, cells };
    });
    rows.sort((a, b) => b.solved - a.solved || a.penalty - b.penalty || a.last - b.last || a.user.localeCompare(b.user));
    rows.forEach((r, i) => (r.rank = i > 0 && rows[i - 1].solved === r.solved && rows[i - 1].penalty === r.penalty ? rows[i - 1].rank : i + 1));
    return rows;
  }

  const letter = (i) => (i < 26 ? String.fromCharCode(65 + i) : 'P' + (i + 1));

  // ---------- Backend online: Compiler Explorer ----------
  // postJson(url, body) -> Promise<json>
  function onlineBackend(postJson, { compiler = 'g132', flags = '-O2 -std=c++17' } = {}) {
    return {
      name: 'Compiler Explorer (online)',
      parallel: 3,
      async compile(source) {
        return { ok: true, id: source };
      },
      async run(source, input, timeLimit) {
        const data = await postJson(`https://godbolt.org/api/compiler/${encodeURIComponent(compiler)}/compile`, {
          source,
          options: {
            userArguments: flags,
            executeParameters: { args: [], stdin: input || '' },
            compilerOptions: { executorRequest: true },
            filters: { execute: true },
            tools: [],
            libraries: [],
          },
          lang: 'c++',
          allowStoreCodeDebug: false,
        });
        const exec = data.execResult || data;
        const build = exec.buildResult || data.buildResult || {};
        const text = (arr) => (arr || []).map((x) => x.text).join('\n');
        if (build.code && build.code !== 0) return { compileError: text(build.stderr) || 'Biên dịch thất bại' };
        const timeMs = Number(exec.execTime) || 0;
        return {
          stdout: text(exec.stdout),
          stderr: text(exec.stderr),
          exitCode: exec.code,
          timeMs,
          timedOut: !!exec.timedOut || (timeLimit && timeMs > timeLimit),
          warnings: text(build.stderr),
        };
      },
    };
  }

  const api = { VERDICT, verdictText, check, judge, runAll, standings, letter, onlineBackend };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.Judge = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
