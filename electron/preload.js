// Cầu nối an toàn giữa giao diện và tiến trình chính: chỉ mở đúng các chức năng cần cho chấm bài.
'use strict';

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('desktop', {
  platform: process.platform,
  findCompiler: (custom) => ipcRenderer.invoke('judge:find', custom),
  pickCompiler: () => ipcRenderer.invoke('judge:pickCompiler'),
  compile: (opts) => ipcRenderer.invoke('judge:compile', opts),
  run: (id, input, timeLimit) => ipcRenderer.invoke('judge:run', id, input, timeLimit),
  dispose: (id) => ipcRenderer.invoke('judge:dispose', id),
  postJson: (url, body) => ipcRenderer.invoke('net:postJson', url, body),
});
