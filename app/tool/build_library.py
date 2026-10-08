#!/usr/bin/env python3
"""Gom các notebook trong content/*.dsanote.json thành một file thư viện cho app (noi-dung.json)."""
import glob
import json
import os
import sys
import time

root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, 'dist', 'noi-dung.json')
items = []
for path in sorted(glob.glob(os.path.join(root, 'content', '*.dsanote.json'))):
    with open(path, encoding='utf-8') as f:
        b = json.load(f)
    if b.get('format') != 'dsa-notebook':
        print(f'Bỏ qua {path}: không phải notebook', file=sys.stderr)
        continue
    head = b['branches'].get(b.get('head')) or next(iter(b['branches'].values()))
    snap = b['commits'][head]['snapshot']
    items.append({
        'file': os.path.basename(path),
        'title': snap.get('title') or b.get('title') or 'Notebook',
        'description': snap.get('description', ''),
        'bundle': b,
    })
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, 'w', encoding='utf-8') as f:
    json.dump({'version': 1, 'generatedAt': int(time.time() * 1000), 'notebooks': items}, f, ensure_ascii=False)
print(f'{len(items)} notebook → {out}')
