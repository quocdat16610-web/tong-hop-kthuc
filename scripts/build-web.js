// Gom các file giao diện vào www/ để đóng gói Android (Capacitor).
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const OUT = path.join(ROOT, 'www');
fs.rmSync(OUT, { recursive: true, force: true });
fs.mkdirSync(OUT, { recursive: true });
for (const item of ['index.html', 'css', 'js', 'vendor']) {
  fs.cpSync(path.join(ROOT, item), path.join(OUT, item), { recursive: true });
}
console.log('Đã tạo thư mục www/');
