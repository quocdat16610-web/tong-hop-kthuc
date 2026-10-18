// Cầu nối an toàn giữa giao diện và tiến trình chính: chỉ mở đúng các chức năng cần thiết.
'use strict';

const { contextBridge, ipcRenderer } = require('electron');

const on = (channel) => (cb) => {
  const fn = (_e, msg) => cb(msg);
  ipcRenderer.on(channel, fn);
  return () => ipcRenderer.removeListener(channel, fn);
};

contextBridge.exposeInMainWorld('desktop', {
  platform: process.platform,
  // Chấm bài
  findCompiler: (custom) => ipcRenderer.invoke('judge:find', custom),
  pickCompiler: () => ipcRenderer.invoke('judge:pickCompiler'),
  compile: (opts) => ipcRenderer.invoke('judge:compile', opts),
  run: (id, input, timeLimit) => ipcRenderer.invoke('judge:run', id, input, timeLimit),
  dispose: (id) => ipcRenderer.invoke('judge:dispose', id),
  postJson: (url, body) => ipcRenderer.invoke('net:postJson', url, body),
  onOpenShare: on('open-share'),
  // IDE
  ide: {
    openFiles: () => ipcRenderer.invoke('fs:openFiles'),
    openFolder: () => ipcRenderer.invoke('fs:openFolder'),
    refreshFolder: (dir) => ipcRenderer.invoke('fs:refreshFolder', dir),
    read: (p) => ipcRenderer.invoke('fs:read', p),
    write: (p, content) => ipcRenderer.invoke('fs:write', p, content),
    saveAs: (name, content) => ipcRenderer.invoke('fs:saveAs', name, content),
    start: (progId) => ipcRenderer.invoke('proc:start', progId),
    input: (id, text) => ipcRenderer.invoke('proc:input', id, text),
    eof: (id) => ipcRenderer.invoke('proc:eof', id),
    kill: (id) => ipcRenderer.invoke('proc:kill', id),
    findGdb: (gppPath) => ipcRenderer.invoke('debug:find', gppPath),
    debugStart: (opts) => ipcRenderer.invoke('debug:start', opts),
    debugControl: (action) => ipcRenderer.invoke('debug:control', action),
    debugBreakpoint: (line, on) => ipcRenderer.invoke('debug:breakpoint', line, on),
    debugStop: () => ipcRenderer.invoke('debug:stop'),
    onEvent: on('ide:event'),
  },
});
