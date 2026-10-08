/*
 * main.js — Ứng dụng máy tính (Electron).
 *
 * App được phục vụ qua một máy chủ nội bộ http://127.0.0.1:<cổng cố định> thay vì file://, vì:
 *  - video YouTube nhúng cần trang có địa chỉ http (file:// bị YouTube từ chối phát);
 *  - cổng cố định giữ nguyên "origin" nên dữ liệu IndexedDB không mất giữa các lần mở.
 */
'use strict';

const { app, BrowserWindow, ipcMain, shell, Menu, net, dialog } = require('electron');
const http = require('http');
const fs = require('fs');
const path = require('path');
const judge = require('./judge-local');

const ROOT = path.join(__dirname, '..');
const PORTS = [47821, 47822, 47823, 47824, 47825];
const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.gif': 'image/gif', '.ico': 'image/x-icon',
  '.mp3': 'audio/mpeg', '.wav': 'audio/wav', '.cur': 'image/x-icon', '.woff2': 'font/woff2',
};
const ALLOWED = ['index.html', 'css/', 'js/', 'vendor/'];

function serve(port) {
  return new Promise((resolve, reject) => {
    const server = http.createServer((req, res) => {
      let rel = decodeURIComponent(new URL(req.url, 'http://x').pathname).replace(/^\/+/, '') || 'index.html';
      rel = path.posix.normalize(rel);
      if (rel.startsWith('..') || !ALLOWED.some((a) => rel === a || rel.startsWith(a))) {
        res.writeHead(404).end();
        return;
      }
      fs.readFile(path.join(ROOT, rel), (err, data) => {
        if (err) return res.writeHead(404).end();
        res.writeHead(200, { 'Content-Type': MIME[path.extname(rel)] || 'application/octet-stream', 'Cache-Control': 'no-cache' });
        res.end(data);
      });
    });
    server.once('error', reject);
    server.listen(port, '127.0.0.1', () => resolve(server));
  });
}

async function startServer() {
  for (const p of PORTS) {
    try {
      await serve(p);
      return p;
    } catch (_) { /* cổng bận, thử cổng sau */ }
  }
  throw new Error('Không mở được cổng nội bộ cho ứng dụng.');
}

function createWindow(port) {
  const win = new BrowserWindow({
    width: 1360,
    height: 880,
    minWidth: 380,
    minHeight: 500,
    title: 'Sổ tay DSA C++',
    backgroundColor: '#ffffff',
    icon: path.join(ROOT, 'build', 'icon.png'),
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      spellcheck: false,
    },
  });
  // Link ngoài mở bằng trình duyệt mặc định.
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https?:/.test(url)) shell.openExternal(url);
    return { action: 'deny' };
  });
  win.webContents.on('will-navigate', (e, url) => {
    if (!url.startsWith(`http://127.0.0.1:${port}/`)) {
      e.preventDefault();
      if (/^https?:/.test(url)) shell.openExternal(url);
    }
  });
  win.loadURL(`http://127.0.0.1:${port}/index.html`);
  return win;
}

function buildMenu() {
  const template = [
    { label: 'Tệp', submenu: [{ role: 'quit', label: 'Thoát' }] },
    {
      label: 'Sửa',
      submenu: [
        { role: 'undo', label: 'Hoàn tác' }, { role: 'redo', label: 'Làm lại' }, { type: 'separator' },
        { role: 'cut', label: 'Cắt' }, { role: 'copy', label: 'Sao chép' }, { role: 'paste', label: 'Dán' }, { role: 'selectAll', label: 'Chọn tất cả' },
      ],
    },
    {
      label: 'Xem',
      submenu: [
        { role: 'reload', label: 'Tải lại' }, { type: 'separator' },
        { role: 'zoomIn', label: 'Phóng to' }, { role: 'zoomOut', label: 'Thu nhỏ' }, { role: 'resetZoom', label: 'Cỡ gốc' },
        { type: 'separator' }, { role: 'togglefullscreen', label: 'Toàn màn hình' }, { role: 'toggleDevTools', label: 'Công cụ nhà phát triển' },
      ],
    },
  ];
  if (process.platform === 'darwin') template.unshift({ role: 'appMenu' });
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

// ---------- IPC: chấm bài trên máy ----------
ipcMain.handle('judge:find', (_e, custom) => judge.findCompiler(custom, process.resourcesPath));
ipcMain.handle('judge:compile', (_e, opts) => judge.compile(opts));
ipcMain.handle('judge:run', (_e, id, input, tl) => judge.run(id, input, tl));
ipcMain.handle('judge:dispose', (_e, id) => judge.dispose(id));
ipcMain.handle('judge:pickCompiler', async () => {
  const r = await dialog.showOpenDialog({
    title: 'Chọn file g++',
    properties: ['openFile'],
    filters: process.platform === 'win32' ? [{ name: 'g++.exe', extensions: ['exe'] }] : [],
  });
  return r.canceled ? null : r.filePaths[0];
});
// Gọi API online từ tiến trình chính để không bị chặn CORS.
ipcMain.handle('net:postJson', async (_e, url, body) => {
  if (!/^https:\/\/godbolt\.org\/api\//.test(url)) throw new Error('URL không được phép');
  const res = await net.fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`Máy chủ biên dịch trả lỗi ${res.status}`);
  return res.json();
});

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  let win = null;
  app.on('second-instance', () => {
    if (win) {
      if (win.isMinimized()) win.restore();
      win.focus();
    }
  });
  app.whenReady().then(async () => {
    buildMenu();
    try {
      const port = await startServer();
      win = createWindow(port);
      app.on('activate', () => {
        if (BrowserWindow.getAllWindows().length === 0) win = createWindow(port);
      });
    } catch (e) {
      dialog.showErrorBox('Sổ tay DSA C++', e.message);
      app.quit();
    }
  });
  app.on('window-all-closed', () => {
    judge.cleanupAll();
    if (process.platform !== 'darwin') app.quit();
  });
}
