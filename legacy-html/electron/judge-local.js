/*
 * judge-local.js — Biên dịch & chạy C++ trên máy bằng g++ (dùng trong tiến trình chính của Electron).
 */
'use strict';

const { spawn, execFile } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');

const isWin = process.platform === 'win32';
const WORK = path.join(os.tmpdir(), 'so-tay-dsa-judge');
const MAX_OUTPUT = 64 * 1024 * 1024;
const programs = new Map(); // id -> { dir, exe }

// Nơi có thể có g++ trên Windows (MinGW đi kèm app, MSYS2, Dev-C++, Code::Blocks…).
function candidates(custom, resourcesPath) {
  const list = [];
  if (custom) list.push(custom);
  if (resourcesPath) list.push(path.join(resourcesPath, 'mingw64', 'bin', isWin ? 'g++.exe' : 'g++'));
  list.push(isWin ? 'g++.exe' : 'g++');
  if (isWin) {
    const pf = [process.env.ProgramFiles, process.env['ProgramFiles(x86)'], 'C:\\'].filter(Boolean);
    const rel = [
      'mingw64\\bin', 'MinGW\\bin', 'msys64\\ucrt64\\bin', 'msys64\\mingw64\\bin',
      'Dev-Cpp\\MinGW64\\bin', 'Embarcadero\\Dev-Cpp\\TDM-GCC-64\\bin', 'CodeBlocks\\MinGW\\bin', 'TDM-GCC-64\\bin',
    ];
    pf.forEach((base) => rel.forEach((r) => list.push(path.join(base, r, 'g++.exe'))));
  } else if (process.platform === 'darwin') {
    list.push('/opt/homebrew/bin/g++', '/usr/local/bin/g++', '/usr/bin/clang++');
  }
  return [...new Set(list)];
}

function version(gpp) {
  return new Promise((resolve) => {
    execFile(gpp, ['--version'], { timeout: 8000, windowsHide: true }, (err, stdout) => {
      resolve(err ? null : String(stdout).split('\n')[0].trim());
    });
  });
}

async function findCompiler(custom, resourcesPath) {
  for (const c of candidates(custom, resourcesPath)) {
    if (path.isAbsolute(c) && !fs.existsSync(c)) continue;
    const v = await version(c);
    if (v) return { path: c, version: v };
  }
  return null;
}

// Header được chèn vào bản build của IDE: tắt bộ đệm stdout để output hiện ngay (console, gỡ lỗi).
function unbufHeader() {
  const f = path.join(WORK, 'dsa_unbuffered.h');
  if (!fs.existsSync(f)) {
    fs.mkdirSync(WORK, { recursive: true });
    fs.writeFileSync(f, '#include <cstdio>\nstatic void __attribute__((constructor)) dsa_unbuffered_stdout() { std::setvbuf(stdout, nullptr, _IONBF, 0); }\n');
  }
  return f;
}

// opts: source, gpp, flags, includeDir (thư mục chứa file để #include "x.h"), debug (thêm -g -O0), unbuffered
function compile({ source, gpp, flags, includeDir, debug, unbuffered }) {
  return new Promise((resolve) => {
    const id = crypto.randomBytes(8).toString('hex');
    const dir = path.join(WORK, id);
    fs.mkdirSync(dir, { recursive: true });
    const src = path.join(dir, 'main.cpp');
    const exe = path.join(dir, isWin ? 'main.exe' : 'main');
    fs.writeFileSync(src, source);
    let base = splitFlags(flags || '-O2 -std=c++17');
    if (debug) base = [...base.filter((f) => !/^-O/.test(f)), '-g', '-O0'];
    const args = [...base, src, '-o', exe];
    if (includeDir && fs.existsSync(includeDir)) args.push('-I', includeDir);
    if (unbuffered || debug) args.push('-include', unbufHeader());
    // Trên Windows: ngăn xếp lớn như Codeforces (đệ quy sâu không tràn) và liên kết tĩnh (không cần DLL của MinGW).
    if (isWin) args.push('-Wl,--stack,268435456', '-static');
    // Thêm thư mục của g++ vào PATH để tìm được các DLL của MinGW.
    const env = { ...process.env, PATH: path.dirname(gpp) + path.delimiter + (process.env.PATH || '') };
    execFile(gpp, args, { cwd: dir, timeout: 60000, windowsHide: true, env, maxBuffer: 8 * 1024 * 1024 }, (err, stdout, stderr) => {
      if (err || !fs.existsSync(exe)) {
        fs.rmSync(dir, { recursive: true, force: true });
        const msg = String(stderr || '').split(src).join('main.cpp') || (err && err.message) || 'Biên dịch thất bại';
        resolve({ ok: false, error: err && err.killed ? 'Biên dịch quá 60 giây.' : msg });
      } else {
        programs.set(id, { dir, exe, src, gppDir: path.dirname(gpp) });
        resolve({ ok: true, id, warnings: String(stderr || '').split(src).join('main.cpp') });
      }
    });
  });
}

function splitFlags(s) {
  return (String(s).match(/"[^"]*"|\S+/g) || []).map((x) => x.replace(/^"|"$/g, ''));
}

function run(id, input, timeLimitMs = 2000) {
  const prog = programs.get(id);
  if (!prog) return Promise.resolve({ stdout: '', stderr: 'Chương trình chưa được biên dịch', exitCode: -1, timeMs: 0 });
  return new Promise((resolve) => {
    const env = { ...process.env, PATH: prog.gppDir + path.delimiter + (process.env.PATH || '') };
    const child = spawn(prog.exe, [], { cwd: prog.dir, windowsHide: true, env });
    const out = [];
    const err = [];
    let size = 0;
    let timedOut = false;
    let tooBig = false;
    const start = process.hrtime.bigint();
    // Cho thêm thời gian để đo được TLE rõ ràng, rồi mới dừng hẳn.
    const killer = setTimeout(() => { timedOut = true; child.kill('SIGKILL'); }, timeLimitMs + 500);
    child.stdout.on('data', (d) => {
      size += d.length;
      if (size > MAX_OUTPUT) { tooBig = true; child.kill('SIGKILL'); } else out.push(d);
    });
    child.stderr.on('data', (d) => { if (err.length < 200) err.push(d); });
    child.on('error', (e) => {
      clearTimeout(killer);
      resolve({ stdout: '', stderr: e.message, exitCode: -1, timeMs: 0 });
    });
    child.on('close', (code, signal) => {
      clearTimeout(killer);
      const timeMs = Number(process.hrtime.bigint() - start) / 1e6;
      resolve({
        stdout: Buffer.concat(out).toString('utf8'),
        stderr: Buffer.concat(err).toString('utf8').slice(0, 20000) + (tooBig ? '\nOutput quá lớn (> 64 MB).' : ''),
        exitCode: code === null ? (signal ? 1 : -1) : code,
        timeMs: Math.round(timeMs),
        timedOut: timedOut || timeMs > timeLimitMs,
      });
    });
    child.stdin.on('error', () => {}); // chương trình thoát trước khi đọc hết input
    child.stdin.end(input || '');
  });
}

// Chạy tương tác (console của IDE): trả về tiến trình con để giao diện gửi input / nhận output dần dần.
function spawnProgram(id) {
  const prog = programs.get(id);
  if (!prog) throw new Error('Chương trình chưa được biên dịch');
  const env = { ...process.env, PATH: prog.gppDir + path.delimiter + (process.env.PATH || '') };
  return spawn(prog.exe, [], { cwd: prog.dir, windowsHide: true, env });
}

const programInfo = (id) => programs.get(id) || null;

function dispose(id) {
  const prog = programs.get(id);
  if (!prog) return;
  programs.delete(id);
  // Trên Windows file .exe có thể còn bị khoá một chút sau khi tiến trình kết thúc.
  setTimeout(() => fs.rm(prog.dir, { recursive: true, force: true }, () => {}), 300);
}

function cleanupAll() {
  try { fs.rmSync(WORK, { recursive: true, force: true }); } catch (_) { /* bỏ qua */ }
}

module.exports = { findCompiler, compile, run, spawnProgram, programInfo, dispose, cleanupAll, splitFlags, WORK };
