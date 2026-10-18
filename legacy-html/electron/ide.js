/*
 * ide.js — Phần chạy trong tiến trình chính cho chế độ IDE:
 *  - mở / lưu file thật trên máy (chỉ những file/thư mục người dùng đã chọn qua hộp thoại);
 *  - chạy chương trình tương tác (gõ input khi chương trình đang chạy);
 *  - gỡ lỗi từng dòng bằng gdb (giống Code::Blocks).
 */
'use strict';

const { spawn, execFile } = require('child_process');
const fs = require('fs');
const path = require('path');
const judge = require('./judge-local');
const { parseLine } = require('./mi');

const isWin = process.platform === 'win32';
const TEXT_EXT = /\.(cpp|cc|cxx|c|h|hpp|hh|txt|in|inp|out|ans|md|json)$/i;
const MAX_FILE = 4 * 1024 * 1024;

// ---------------- File ----------------
const allowedFiles = new Set();
const allowedDirs = new Set();
const isAllowed = (p) => {
  const abs = path.resolve(p);
  return allowedFiles.has(abs) || [...allowedDirs].some((d) => abs.startsWith(d + path.sep));
};

function readText(p) {
  const st = fs.statSync(p);
  if (st.size > MAX_FILE) throw new Error(`File quá lớn (${(st.size / 1048576).toFixed(1)} MB)`);
  return fs.readFileSync(p, 'utf8');
}

function listDir(dir, depth = 0) {
  if (depth > 4) return [];
  let entries = [];
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch (_) { return []; }
  const out = [];
  entries
    .filter((e) => !e.name.startsWith('.') && e.name !== 'node_modules')
    .sort((a, b) => (b.isDirectory() - a.isDirectory()) || a.name.localeCompare(b.name))
    .slice(0, 300)
    .forEach((e) => {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) {
        const children = listDir(p, depth + 1);
        if (children.length) out.push({ name: e.name, path: p, dir: true, children });
      } else if (TEXT_EXT.test(e.name)) out.push({ name: e.name, path: p, dir: false });
    });
  return out;
}

// ---------------- Gỡ lỗi bằng gdb ----------------
function findGdb(gppPath) {
  const candidates = [];
  if (gppPath && path.isAbsolute(gppPath)) candidates.push(path.join(path.dirname(gppPath), isWin ? 'gdb.exe' : 'gdb'));
  candidates.push(isWin ? 'gdb.exe' : 'gdb');
  return new Promise((resolve) => {
    const tryNext = (i) => {
      if (i >= candidates.length) return resolve(null);
      const c = candidates[i];
      if (path.isAbsolute(c) && !fs.existsSync(c)) return tryNext(i + 1);
      execFile(c, ['--version'], { timeout: 8000, windowsHide: true }, (err, stdout) => {
        if (err) tryNext(i + 1);
        else resolve({ path: c, version: String(stdout).split('\n')[0].trim() });
      });
    };
    tryNext(0);
  });
}

class DebugSession {
  constructor({ gdb, progId, input, breakpoints, send }) {
    this.gdb = gdb;
    this.prog = judge.programInfo(progId);
    this.progId = progId;
    this.input = input || '';
    this.breakpoints = new Map(); // dòng -> số hiệu breakpoint của gdb
    this.initialBps = breakpoints || [];
    this.send = send;
    this.token = 1;
    this.pending = new Map();
    this.buf = '';
    this.lastCmd = null;
    this.done = false;
  }

  start() {
    const dir = this.prog.dir;
    fs.writeFileSync(path.join(dir, 'input.txt'), this.input);
    fs.writeFileSync(path.join(dir, 'output.txt'), '');
    const env = { ...process.env, PATH: this.prog.gppDir + path.delimiter + (process.env.PATH || '') };
    this.proc = spawn(this.gdb, ['--interpreter=mi2', '--quiet', '--nx', this.prog.exe], { cwd: dir, windowsHide: true, env });
    this.proc.stdout.on('data', (d) => this.onData(d));
    this.proc.stderr.on('data', () => {});
    this.proc.on('error', (e) => this.finish({ error: e.message }));
    this.proc.on('close', () => this.finish({}));
    return this.setup();
  }

  async setup() {
    await this.cmd('-gdb-set confirm off');
    await this.cmd('-gdb-set print pretty off');
    if (isWin) await this.cmd('-gdb-set new-console off').catch(() => {});
    for (const line of this.initialBps) await this.addBreakpoint(line);
    if (!this.initialBps.length) await this.cmd('-break-insert -t main'); // dừng ở đầu main như Thonny
    await this.cmd('-exec-arguments < input.txt > output.txt');
    this.lastCmd = 'run';
    await this.cmd('-exec-run');
  }

  cmd(text) {
    if (this.done) return Promise.reject(new Error('Phiên gỡ lỗi đã kết thúc'));
    const t = this.token++;
    return new Promise((resolve, reject) => {
      this.pending.set(t, { resolve, reject });
      this.proc.stdin.write(`${t}${text}\n`);
    });
  }

  onData(d) {
    this.buf += d.toString('utf8');
    let i;
    while ((i = this.buf.indexOf('\n')) !== -1) {
      const line = this.buf.slice(0, i);
      this.buf = this.buf.slice(i + 1);
      let rec;
      try { rec = parseLine(line); } catch (_) { rec = null; }
      if (rec) this.onRecord(rec);
    }
  }

  onRecord(rec) {
    if (rec.kind === '^' && rec.token !== null && this.pending.has(rec.token)) {
      const p = this.pending.get(rec.token);
      this.pending.delete(rec.token);
      if (rec.cls === 'error') p.reject(new Error(rec.data.msg || 'gdb error'));
      else p.resolve(rec.data);
    } else if (rec.kind === '*' && rec.cls === 'running') {
      this.send({ type: 'running' });
    } else if (rec.kind === '*' && rec.cls === 'stopped') {
      this.onStopped(rec.data).catch((e) => this.send({ type: 'log', text: e.message }));
    }
  }

  output() {
    try {
      const p = path.join(this.prog.dir, 'output.txt');
      const st = fs.statSync(p);
      const fd = fs.openSync(p, 'r');
      const n = Math.min(st.size, 256 * 1024);
      const b = Buffer.alloc(n);
      fs.readSync(fd, b, 0, n, st.size - n);
      fs.closeSync(fd);
      return b.toString('utf8');
    } catch (_) {
      return '';
    }
  }

  isUser(frame) {
    return frame && frame.file && path.basename(frame.file) === 'main.cpp';
  }

  async onStopped(data) {
    const reason = data.reason || '';
    if (reason.startsWith('exited')) {
      const code = reason === 'exited-normally' ? 0 : parseInt(data['exit-code'] || '1', 8);
      this.send({ type: 'exited', code, output: this.output() });
      this.stop();
      return;
    }
    // Bước vào thư viện chuẩn (vd. cout) thì tự đi ra lại code của người dùng.
    if (!this.isUser(data.frame) && (this.lastCmd === 'step' || this.lastCmd === 'next') && reason === 'end-stepping-range') {
      this.lastCmd = 'finish';
      await this.cmd('-exec-finish').catch(() => this.cmd('-exec-next'));
      return;
    }
    const frames = ((await this.cmd('-stack-list-frames').catch(() => ({}))).stack || []).map((f) => ({
      level: Number(f.level), func: f.func, line: Number(f.line) || null, user: this.isUser(f),
    }));
    const top = frames.find((f) => f.user);
    let locals = [];
    if (top) {
      if (top.level > 0) await this.cmd(`-stack-select-frame ${top.level}`).catch(() => {});
      const v = await this.cmd('-stack-list-variables --all-values').catch(() => ({}));
      locals = (v.variables || []).map((x) => ({ name: x.name, value: x.value !== undefined ? x.value : '…', arg: !!x.arg }));
    }
    this.send({
      type: 'stopped',
      reason,
      signal: data['signal-name'] ? `${data['signal-name']} (${data['signal-meaning'] || ''})` : null,
      line: top ? top.line : null,
      func: top ? top.func : (data.frame && data.frame.func) || '?',
      frames: frames.filter((f) => f.user),
      locals,
      output: this.output(),
    });
  }

  async addBreakpoint(line) {
    if (this.breakpoints.has(line)) return;
    const r = await this.cmd(`-break-insert --source main.cpp --line ${line}`).catch(() => null);
    if (r && r.bkpt) this.breakpoints.set(line, r.bkpt.number);
  }

  async removeBreakpoint(line) {
    const n = this.breakpoints.get(line);
    if (!n) return;
    this.breakpoints.delete(line);
    await this.cmd(`-break-delete ${n}`).catch(() => {});
  }

  async control(action) {
    const map = { continue: '-exec-continue', next: '-exec-next', step: '-exec-step', finish: '-exec-finish' };
    if (!map[action]) return;
    this.lastCmd = action;
    await this.cmd(map[action]).catch((e) => this.send({ type: 'log', text: e.message }));
  }

  stop() {
    if (this.done) return;
    try { this.proc.stdin.write('-gdb-exit\n'); } catch (_) { /* đã đóng */ }
    setTimeout(() => { try { this.proc.kill('SIGKILL'); } catch (_) { /* đã thoát */ } }, 500);
  }

  finish(info) {
    if (this.done) return;
    this.done = true;
    this.pending.forEach((p) => p.reject(new Error('gdb đã thoát')));
    this.pending.clear();
    this.send({ type: 'ended', ...info });
    judge.dispose(this.progId);
  }
}

// ---------------- Đăng ký IPC ----------------
function register(ipcMain, dialog, BrowserWindow) {
  const procs = new Map();
  let session = null;
  let seq = 1;
  const sender = (e) => (msg) => { if (!e.sender.isDestroyed()) e.sender.send('ide:event', msg); };

  ipcMain.handle('fs:openFiles', async (e) => {
    const r = await dialog.showOpenDialog(BrowserWindow.fromWebContents(e.sender), {
      title: 'Mở file', properties: ['openFile', 'multiSelections'],
      filters: [{ name: 'Mã nguồn C/C++', extensions: ['cpp', 'cc', 'cxx', 'c', 'h', 'hpp'] }, { name: 'Tất cả', extensions: ['*'] }],
    });
    if (r.canceled) return [];
    return r.filePaths.map((p) => {
      allowedFiles.add(path.resolve(p));
      return { path: p, name: path.basename(p), content: readText(p) };
    });
  });

  ipcMain.handle('fs:openFolder', async (e) => {
    const r = await dialog.showOpenDialog(BrowserWindow.fromWebContents(e.sender), { title: 'Mở thư mục', properties: ['openDirectory'] });
    if (r.canceled) return null;
    const dir = path.resolve(r.filePaths[0]);
    allowedDirs.add(dir);
    return { path: dir, name: path.basename(dir), children: listDir(dir) };
  });

  ipcMain.handle('fs:refreshFolder', (_e, dir) => {
    if (!allowedDirs.has(path.resolve(dir))) throw new Error('Thư mục chưa được mở');
    return { path: dir, name: path.basename(dir), children: listDir(dir) };
  });

  ipcMain.handle('fs:read', (_e, p) => {
    if (!isAllowed(p)) throw new Error('Không có quyền đọc file này');
    return readText(p);
  });

  ipcMain.handle('fs:write', (_e, p, content) => {
    if (!isAllowed(p)) throw new Error('Không có quyền ghi file này');
    fs.writeFileSync(p, content, 'utf8');
    return true;
  });

  ipcMain.handle('fs:saveAs', async (e, defaultName, content) => {
    const r = await dialog.showSaveDialog(BrowserWindow.fromWebContents(e.sender), {
      title: 'Lưu file', defaultPath: defaultName || 'main.cpp',
      filters: [{ name: 'C++', extensions: ['cpp'] }, { name: 'Tất cả', extensions: ['*'] }],
    });
    if (r.canceled || !r.filePath) return null;
    fs.writeFileSync(r.filePath, content, 'utf8');
    allowedFiles.add(path.resolve(r.filePath));
    return { path: r.filePath, name: path.basename(r.filePath) };
  });

  // Chạy tương tác
  ipcMain.handle('proc:start', (e, progId) => {
    const send = sender(e);
    const child = judge.spawnProgram(progId);
    const id = seq++;
    const start = Date.now();
    procs.set(id, child);
    child.stdout.on('data', (d) => send({ type: 'out', id, text: d.toString('utf8') }));
    child.stderr.on('data', (d) => send({ type: 'err', id, text: d.toString('utf8') }));
    child.on('error', (err) => send({ type: 'err', id, text: err.message + '\n' }));
    child.on('close', (code, signal) => {
      procs.delete(id);
      send({ type: 'exit', id, code: code === null ? -1 : code, signal, timeMs: Date.now() - start });
    });
    child.stdin.on('error', () => {});
    return id;
  });
  ipcMain.handle('proc:input', (_e, id, text) => {
    const c = procs.get(id);
    if (c) c.stdin.write(text);
  });
  ipcMain.handle('proc:eof', (_e, id) => {
    const c = procs.get(id);
    if (c) c.stdin.end();
  });
  ipcMain.handle('proc:kill', (_e, id) => {
    const c = procs.get(id);
    if (c) c.kill('SIGKILL');
  });

  // Gỡ lỗi
  ipcMain.handle('debug:find', (_e, gppPath) => findGdb(gppPath));
  ipcMain.handle('debug:start', async (e, opts) => {
    if (session) session.stop();
    const gdb = await findGdb(opts.gppPath);
    if (!gdb) throw new Error('Không tìm thấy gdb trên máy.');
    session = new DebugSession({ gdb: gdb.path, progId: opts.progId, input: opts.input, breakpoints: opts.breakpoints, send: sender(e) });
    await session.start();
    return true;
  });
  ipcMain.handle('debug:control', (_e, action) => session && session.control(action));
  ipcMain.handle('debug:breakpoint', (_e, line, on) => session && !session.done && (on ? session.addBreakpoint(line) : session.removeBreakpoint(line)));
  ipcMain.handle('debug:stop', () => { if (session) session.stop(); });

  return () => {
    procs.forEach((c) => c.kill('SIGKILL'));
    if (session) session.stop();
  };
}

module.exports = { register, DebugSession, findGdb, listDir };
