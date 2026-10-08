/*
 * mi.js — Đọc dòng kết quả của gdb ở chế độ máy (GDB/MI), ví dụ:
 *   12^done,variables=[{name="a",value="1"}]
 *   *stopped,reason="breakpoint-hit",frame={func="main",line="5"}
 */
'use strict';

function parseCString(s, i) {
  // s[i] === '"'
  let out = '';
  i++;
  while (i < s.length && s[i] !== '"') {
    if (s[i] === '\\') {
      const c = s[i + 1];
      if (c === 'n') out += '\n';
      else if (c === 't') out += '\t';
      else if (c === 'r') out += '\r';
      else if (/[0-7]/.test(c)) {
        const m = /^[0-7]{1,3}/.exec(s.slice(i + 1));
        out += String.fromCharCode(parseInt(m[0], 8));
        i += m[0].length - 1;
      } else out += c;
      i += 2;
    } else out += s[i++];
  }
  return [out, i + 1];
}

function parseValue(s, i) {
  if (s[i] === '"') return parseCString(s, i);
  if (s[i] === '{') {
    const obj = {};
    i++;
    if (s[i] === '}') return [obj, i + 1];
    for (;;) {
      const [k, v, j] = parseResult(s, i);
      obj[k] = v;
      i = j;
      if (s[i] === ',') i++;
      else return [obj, i + 1];
    }
  }
  if (s[i] === '[') {
    const arr = [];
    i++;
    if (s[i] === ']') return [arr, i + 1];
    for (;;) {
      // Danh sách có thể chứa giá trị hoặc cặp tên=giá trị (khi đó bỏ tên).
      if (s[i] === '"' || s[i] === '{' || s[i] === '[') {
        const [v, j] = parseValue(s, i);
        arr.push(v);
        i = j;
      } else {
        const [, v, j] = parseResult(s, i);
        arr.push(v);
        i = j;
      }
      if (s[i] === ',') i++;
      else return [arr, i + 1];
    }
  }
  throw new Error('MI: ký tự lạ ở vị trí ' + i);
}

function parseResult(s, i) {
  const eq = s.indexOf('=', i);
  const key = s.slice(i, eq);
  const [v, j] = parseValue(s, eq + 1);
  return [key, v, j];
}

// Trả về { token, kind, cls, data } hoặc null nếu là dòng "(gdb)".
function parseLine(line) {
  line = line.replace(/\r$/, '');
  if (!line || line.startsWith('(gdb)')) return null;
  const m = /^(\d*)([\^*=+~@&])(.*)$/.exec(line);
  if (!m) return { kind: 'text', text: line };
  const token = m[1] ? Number(m[1]) : null;
  const kind = m[2];
  const rest = m[3];
  if (kind === '~' || kind === '@' || kind === '&') {
    try { return { token, kind, text: parseCString(rest, 0)[0] }; } catch (_) { return { token, kind, text: rest }; }
  }
  const comma = rest.indexOf(',');
  const cls = comma === -1 ? rest : rest.slice(0, comma);
  const data = {};
  if (comma !== -1) {
    let i = comma + 1;
    while (i < rest.length) {
      const [k, v, j] = parseResult(rest, i);
      data[k] = v;
      i = j;
      if (rest[i] === ',') i++;
      else break;
    }
  }
  return { token, kind, cls, data };
}

module.exports = { parseLine };
