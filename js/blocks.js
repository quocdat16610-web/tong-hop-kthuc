/*
 * blocks.js — Lập trình kéo thả kiểu Scratch (Blockly) cho khối mô phỏng.
 * Các khối sinh ra code JavaScript dùng thư viện `viz` (xem sim.js) rồi chạy trong sandbox.
 */
(function (root) {
  'use strict';

  const C = {
    input: '#4C97FF', array: '#FF8C1A', ds: '#CF63CF', grid: '#59C059', graph: '#FF6680', show: '#9966FF',
  };
  const COLOR_OPTS = [
    ['xanh dương (đang xét)', 'active'], ['vàng (so sánh)', 'compare'], ['đỏ (đổi chỗ)', 'swap'],
    ['xanh lá (xong)', 'done'], ['tím (đã thăm)', 'visited'], ['cam (đường đi)', 'path'],
    ['xám (bỏ qua)', 'dim'], ['tường', 'wall'], ['điểm đầu', 'start'], ['điểm cuối', 'end'], ['bỏ màu', 'none'],
  ];
  const v = (name, extra) => ({ type: 'field_variable', name, variable: extra || 'a' });
  const num = (name) => ({ type: 'input_value', name, check: 'Number' });
  const any = (name) => ({ type: 'input_value', name });
  const color = { type: 'field_dropdown', name: 'COLOR', options: COLOR_OPTS };
  const stmt = (type, message0, args0, colour, tooltip) => ({ type, message0, args0, colour, tooltip, previousStatement: null, nextStatement: null, inputsInline: true });
  const expr = (type, message0, args0, colour, output, tooltip) => ({ type, message0, args0, colour, tooltip, output, inputsInline: true });

  const DEFS = [
    // Dữ liệu vào
    expr('dsa_read_numbers', 'các số trong dữ liệu vào', [], C.input, 'Array', 'Mọi số có trong ô "Dữ liệu vào"'),
    expr('dsa_input_text', 'dữ liệu vào (chữ)', [], C.input, 'String'),
    expr('dsa_input_lines', 'các dòng của dữ liệu vào', [], C.input, 'Array'),
    // Mảng
    stmt('dsa_array_create', 'tạo mảng %1 từ %2 vẽ dạng %3', [v('VAR'), any('LIST'), { type: 'field_dropdown', name: 'STYLE', options: [['ô', 'box'], ['cột', 'bars']] }], C.array),
    expr('dsa_array_get', '%1 [ %2 ]', [v('VAR'), num('I')], C.array, null, 'Phần tử ở vị trí i (đánh số từ 0 như C++)'),
    expr('dsa_array_length', 'độ dài %1', [v('VAR')], C.array, 'Number'),
    stmt('dsa_array_set', 'gán %1 [ %2 ] = %3', [v('VAR'), num('I'), any('X')], C.array),
    stmt('dsa_array_swap', 'đổi chỗ %1 [ %2 ] và [ %3 ]', [v('VAR'), num('I'), num('J')], C.array),
    expr('dsa_array_compare', 'so sánh %1 [ %2 ] %3 [ %4 ]', [v('VAR'), num('I'), { type: 'field_dropdown', name: 'OP', options: [['>', 'GT'], ['<', 'LT'], ['=', 'EQ']] }, num('J')], C.array, 'Boolean', 'So sánh hai phần tử và tô màu vàng'),
    stmt('dsa_array_mark', 'tô màu %1 [ %2 ] màu %3', [v('VAR'), num('I'), color], C.array),
    stmt('dsa_array_pointer', 'đặt mũi tên %1 của %2 tại %3', [{ type: 'field_input', name: 'NAME', text: 'i' }, v('VAR'), num('I')], C.array),
    stmt('dsa_array_push', 'thêm %2 vào cuối %1', [v('VAR'), any('X')], C.array),
    // Stack / queue
    stmt('dsa_ds_create', 'tạo %1 là %2 rỗng', [v('VAR', 'st'), { type: 'field_dropdown', name: 'KIND', options: [['stack (ngăn xếp)', 'stack'], ['queue (hàng đợi)', 'queue']] }], C.ds),
    stmt('dsa_ds_push', 'đưa %2 vào %1', [v('VAR', 'st'), any('X')], C.ds),
    expr('dsa_ds_pop', 'lấy ra từ %1', [v('VAR', 'st')], C.ds, null, 'Stack: lấy ở đỉnh. Queue: lấy ở đầu.'),
    stmt('dsa_ds_pop_stmt', 'bỏ một phần tử khỏi %1', [v('VAR', 'st')], C.ds),
    expr('dsa_ds_peek', '%2 của %1', [v('VAR', 'st'), { type: 'field_dropdown', name: 'WHICH', options: [['đỉnh', 'top'], ['đầu', 'front']] }], C.ds, null),
    expr('dsa_ds_empty', '%1 rỗng?', [v('VAR', 'st')], C.ds, 'Boolean'),
    expr('dsa_ds_size', 'kích thước %1', [v('VAR', 'st')], C.ds, 'Number'),
    // Lưới
    stmt('dsa_grid_from_lines', 'tạo lưới %1 từ các dòng %2', [v('VAR', 'g'), any('LINES')], C.grid, 'Mỗi ký tự là một ô'),
    stmt('dsa_grid_create', 'tạo lưới %1 có %2 hàng %3 cột', [v('VAR', 'g'), num('R'), num('C')], C.grid),
    expr('dsa_grid_get', 'ô %1 [ %2 ][ %3 ]', [v('VAR', 'g'), num('R'), num('C')], C.grid, null),
    stmt('dsa_grid_set', 'gán ô %1 [ %2 ][ %3 ] = %4', [v('VAR', 'g'), num('R'), num('C'), any('X')], C.grid),
    stmt('dsa_grid_mark', 'tô màu ô %1 [ %2 ][ %3 ] màu %4', [v('VAR', 'g'), num('R'), num('C'), color], C.grid),
    expr('dsa_grid_is', 'ô %1 [ %2 ][ %3 ] có màu %4', [v('VAR', 'g'), num('R'), num('C'), color], C.grid, 'Boolean'),
    expr('dsa_grid_inside', 'ô [ %2 ][ %3 ] nằm trong %1', [v('VAR', 'g'), num('R'), num('C')], C.grid, 'Boolean'),
    expr('dsa_grid_size', 'số %2 của %1', [v('VAR', 'g'), { type: 'field_dropdown', name: 'DIM', options: [['hàng', 'rows'], ['cột', 'cols']] }], C.grid, 'Number'),
    // Đồ thị / cây
    stmt('dsa_graph_create', 'tạo đồ thị %1 từ các số %2 mỗi cạnh %3 số, có hướng %4', [v('VAR', 'G'), any('LIST'), { type: 'field_dropdown', name: 'K', options: [['2', '2'], ['3 (có trọng số)', '3']] }, { type: 'field_checkbox', name: 'DIRECTED', checked: false }], C.graph),
    stmt('dsa_tree_create', 'tạo cây %1 rỗng', [v('VAR', 'T')], C.graph),
    stmt('dsa_graph_add_node', 'thêm đỉnh %2 vào %1', [v('VAR', 'T'), any('N')], C.graph),
    stmt('dsa_graph_add_edge', 'thêm cạnh %2 → %3 vào %1', [v('VAR', 'T'), any('U'), any('W')], C.graph),
    stmt('dsa_graph_visit', 'tô màu đỉnh %2 của %1 màu %3', [v('VAR', 'G'), any('N'), color], C.graph),
    stmt('dsa_graph_edge', 'tô màu cạnh %2 — %3 của %1 màu %4', [v('VAR', 'G'), any('U'), any('W'), color], C.graph),
    stmt('dsa_graph_label', 'ghi %3 lên đỉnh %2 của %1', [v('VAR', 'G'), any('N'), any('X')], C.graph),
    expr('dsa_graph_neighbors', 'các đỉnh kề %2 trong %1', [v('VAR', 'G'), any('N')], C.graph, 'Array'),
    expr('dsa_graph_weight', 'trọng số cạnh %2 — %3 trong %1', [v('VAR', 'G'), any('U'), any('W')], C.graph, 'Number'),
    // Hiển thị
    stmt('dsa_step', 'chụp bước, ghi chú %1', [any('X')], C.show, 'Tạo một bước trong trình phát'),
    stmt('dsa_var', 'hiện biến %1 = %2', [{ type: 'field_input', name: 'NAME', text: 'i' }, any('X')], C.show),
    stmt('dsa_log', 'in ra %1', [any('X')], C.show),
    stmt('dsa_auto', 'tự chụp bước sau mỗi thao tác %1', [{ type: 'field_checkbox', name: 'ON', checked: true }], C.show),
  ];

  function defineGenerators(G, O) {
    const f = G.forBlock;
    const V = (b) => G.getVariableName(b.getFieldValue('VAR'));
    const N = (b) => JSON.stringify(b.getField('VAR').getText());
    const val = (b, name, order = O.NONE, dflt = '0') => G.valueToCode(b, name, order) || dflt;
    const col = (b) => (b.getFieldValue('COLOR') === 'none' ? 'null' : JSON.stringify(b.getFieldValue('COLOR')));
    const call = (code) => [code, O.FUNCTION_CALL];

    f.dsa_read_numbers = () => call('readNumbers()');
    f.dsa_input_text = () => ['INPUT', O.ATOMIC];
    f.dsa_input_lines = () => call("INPUT.split('\\n').filter((l) => l.trim() !== '')");

    f.dsa_array_create = (b) => `${V(b)} = viz.array(${val(b, 'LIST', O.NONE, '[]')}, { name: ${N(b)}, bars: ${b.getFieldValue('STYLE') === 'bars'} });\n`;
    f.dsa_array_get = (b) => call(`${V(b)}.get(${val(b, 'I')})`);
    f.dsa_array_length = (b) => [`${V(b)}.length`, O.MEMBER];
    f.dsa_array_set = (b) => `${V(b)}.set(${val(b, 'I')}, ${val(b, 'X')});\n`;
    f.dsa_array_swap = (b) => `${V(b)}.swap(${val(b, 'I')}, ${val(b, 'J')});\n`;
    f.dsa_array_compare = (b) => {
      const op = { GT: '> 0', LT: '< 0', EQ: '=== 0' }[b.getFieldValue('OP')];
      return [`${V(b)}.compare(${val(b, 'I')}, ${val(b, 'J')}) ${op}`, O.RELATIONAL];
    };
    f.dsa_array_mark = (b) => `${V(b)}.mark(${val(b, 'I')}, ${col(b)});\n`;
    f.dsa_array_pointer = (b) => `${V(b)}.pointer(${JSON.stringify(b.getFieldValue('NAME'))}, ${val(b, 'I')});\n`;
    f.dsa_array_push = (b) => `${V(b)}.push(${val(b, 'X')});\n`;

    f.dsa_ds_create = (b) => `${V(b)} = viz.${b.getFieldValue('KIND')}([], { name: ${N(b)} });\n`;
    f.dsa_ds_push = (b) => `${V(b)}.push(${val(b, 'X')});\n`;
    f.dsa_ds_pop = (b) => call(`${V(b)}.pop()`);
    f.dsa_ds_pop_stmt = (b) => `${V(b)}.pop();\n`;
    f.dsa_ds_peek = (b) => call(`${V(b)}.${b.getFieldValue('WHICH')}()`);
    f.dsa_ds_empty = (b) => call(`${V(b)}.empty()`);
    f.dsa_ds_size = (b) => call(`${V(b)}.size()`);

    f.dsa_grid_from_lines = (b) => `${V(b)} = viz.grid((${val(b, 'LINES', O.NONE, '[]')}).map((r) => String(r).split('')), { name: ${N(b)} });\n`;
    f.dsa_grid_create = (b) => `${V(b)} = viz.grid(${val(b, 'R')}, ${val(b, 'C')}, '', { name: ${N(b)} });\n`;
    f.dsa_grid_get = (b) => call(`${V(b)}.get(${val(b, 'R')}, ${val(b, 'C')})`);
    f.dsa_grid_set = (b) => `${V(b)}.set(${val(b, 'R')}, ${val(b, 'C')}, ${val(b, 'X')});\n`;
    f.dsa_grid_mark = (b) => `${V(b)}.mark(${val(b, 'R')}, ${val(b, 'C')}, ${col(b)});\n`;
    f.dsa_grid_is = (b) => [`${V(b)}.state(${val(b, 'R')}, ${val(b, 'C')}) === ${col(b)}`, O.EQUALITY];
    f.dsa_grid_inside = (b) => call(`${V(b)}.inside(${val(b, 'R')}, ${val(b, 'C')})`);
    f.dsa_grid_size = (b) => [`${V(b)}.${b.getFieldValue('DIM')}`, O.MEMBER];

    const EDGES = '((a, k) => { const e = []; for (let i = 0; i + k <= a.length; i += k) e.push(a.slice(i, i + k)); return e; })';
    f.dsa_graph_create = (b) => `${V(b)} = viz.graph({ edges: ${EDGES}(${val(b, 'LIST', O.NONE, '[]')}, ${b.getFieldValue('K')}), directed: ${b.getFieldValue('DIRECTED') === 'TRUE'}, name: ${N(b)} });\n`;
    f.dsa_tree_create = (b) => `${V(b)} = viz.tree({ name: ${N(b)} });\n`;
    f.dsa_graph_add_node = (b) => `${V(b)}.addNode(${val(b, 'N')});\n`;
    f.dsa_graph_add_edge = (b) => `${V(b)}.addEdge(${val(b, 'U')}, ${val(b, 'W')});\n`;
    f.dsa_graph_visit = (b) => `${V(b)}.visit(${val(b, 'N')}, ${col(b)});\n`;
    f.dsa_graph_edge = (b) => `${V(b)}.edge(${val(b, 'U')}, ${val(b, 'W')}, ${col(b)});\n`;
    f.dsa_graph_label = (b) => `${V(b)}.label(${val(b, 'N')}, ${val(b, 'X', O.NONE, "''")});\n`;
    f.dsa_graph_neighbors = (b) => call(`${V(b)}.neighbors(${val(b, 'N')})`);
    f.dsa_graph_weight = (b) => call(`${V(b)}.weight(${val(b, 'U')}, ${val(b, 'W')})`);

    f.dsa_step = (b) => `viz.step(String(${val(b, 'X', O.NONE, "''")}));\n`;
    f.dsa_var = (b) => `viz.var(${JSON.stringify(b.getFieldValue('NAME'))}, ${val(b, 'X')});\n`;
    f.dsa_log = (b) => `viz.log(${val(b, 'X', O.NONE, "''")});\n`;
    f.dsa_auto = (b) => `viz.auto(${b.getFieldValue('ON') === 'TRUE'});\n`;
  }

  // ---------- Hộp công cụ ----------
  const sh = (n) => ({ shadow: { type: 'math_number', fields: { NUM: n } } });
  const st = (t) => ({ shadow: { type: 'text', fields: { TEXT: t } } });
  const blk = (type, inputs, fields) => ({ kind: 'block', type, inputs, fields });
  const TOOLBOX = {
    kind: 'categoryToolbox',
    contents: [
      { kind: 'category', name: 'Dữ liệu vào', colour: C.input, contents: [blk('dsa_read_numbers'), blk('dsa_input_lines'), blk('dsa_input_text')] },
      {
        kind: 'category', name: 'Mảng', colour: C.array, contents: [
          blk('dsa_array_create', { LIST: { block: { type: 'dsa_read_numbers' } } }),
          blk('dsa_array_get', { I: sh(0) }), blk('dsa_array_length'), blk('dsa_array_set', { I: sh(0), X: sh(0) }),
          blk('dsa_array_swap', { I: sh(0), J: sh(1) }), blk('dsa_array_compare', { I: sh(0), J: sh(1) }),
          blk('dsa_array_mark', { I: sh(0) }, { COLOR: 'done' }), blk('dsa_array_pointer', { I: sh(0) }), blk('dsa_array_push', { X: sh(0) }),
        ],
      },
      {
        kind: 'category', name: 'Stack / Queue', colour: C.ds, contents: [
          blk('dsa_ds_create'), blk('dsa_ds_push', { X: sh(0) }), blk('dsa_ds_pop'), blk('dsa_ds_pop_stmt'), blk('dsa_ds_peek'), blk('dsa_ds_empty'), blk('dsa_ds_size'),
        ],
      },
      {
        kind: 'category', name: 'Lưới', colour: C.grid, contents: [
          blk('dsa_grid_from_lines', { LINES: { block: { type: 'dsa_input_lines' } } }), blk('dsa_grid_create', { R: sh(5), C: sh(5) }),
          blk('dsa_grid_get', { R: sh(0), C: sh(0) }), blk('dsa_grid_set', { R: sh(0), C: sh(0), X: st('') }),
          blk('dsa_grid_mark', { R: sh(0), C: sh(0) }, { COLOR: 'visited' }), blk('dsa_grid_is', { R: sh(0), C: sh(0) }, { COLOR: 'wall' }),
          blk('dsa_grid_inside', { R: sh(0), C: sh(0) }), blk('dsa_grid_size'),
        ],
      },
      {
        kind: 'category', name: 'Đồ thị / Cây', colour: C.graph, contents: [
          blk('dsa_graph_create', { LIST: { block: { type: 'dsa_read_numbers' } } }), blk('dsa_tree_create'),
          blk('dsa_graph_add_node', { N: sh(1) }), blk('dsa_graph_add_edge', { U: sh(1), W: sh(2) }),
          blk('dsa_graph_visit', { N: sh(0) }, { COLOR: 'visited' }), blk('dsa_graph_edge', { U: sh(0), W: sh(1) }, { COLOR: 'path' }),
          blk('dsa_graph_label', { N: sh(0), X: st('') }), blk('dsa_graph_neighbors', { N: sh(0) }), blk('dsa_graph_weight', { U: sh(0), W: sh(1) }),
        ],
      },
      {
        kind: 'category', name: 'Hiển thị', colour: C.show, contents: [
          blk('dsa_step', { X: st('ghi chú') }), blk('dsa_var', { X: sh(0) }), blk('dsa_log', { X: st('xin chào') }), blk('dsa_auto'),
        ],
      },
      { kind: 'sep' },
      {
        kind: 'category', name: 'Điều kiện', categorystyle: 'logic_category', contents: [
          blk('controls_if'), { kind: 'block', type: 'controls_if', extraState: { hasElse: true } }, blk('logic_compare'), blk('logic_operation'), blk('logic_negate'), blk('logic_boolean'),
        ],
      },
      {
        kind: 'category', name: 'Vòng lặp', categorystyle: 'loop_category', contents: [
          blk('controls_for', { FROM: sh(0), TO: sh(9), BY: sh(1) }), blk('controls_whileUntil'), blk('controls_repeat_ext', { TIMES: sh(10) }),
          blk('controls_forEach'), blk('controls_flow_statements'),
        ],
      },
      {
        kind: 'category', name: 'Toán', categorystyle: 'math_category', contents: [
          blk('math_number'), blk('math_arithmetic', { A: sh(1), B: sh(1) }), blk('math_modulo', { DIVIDEND: sh(10), DIVISOR: sh(3) }),
          blk('math_single'), blk('math_round'), blk('math_on_list'), blk('math_random_int', { FROM: sh(1), TO: sh(100) }), blk('math_number_property', { NUMBER_TO_CHECK: sh(0) }),
        ],
      },
      { kind: 'category', name: 'Chữ', categorystyle: 'text_category', contents: [blk('text'), blk('text_join'), blk('text_length'), blk('text_charAt')] },
      {
        kind: 'category', name: 'Danh sách', categorystyle: 'list_category', contents: [
          blk('lists_create_empty'), blk('lists_create_with'), blk('lists_repeat', { NUM: sh(5) }), blk('lists_length'), blk('lists_isEmpty'),
          blk('lists_getIndex'), blk('lists_setIndex'), blk('lists_indexOf'), blk('lists_sort'),
        ],
      },
      { kind: 'category', name: 'Biến', categorystyle: 'variable_category', custom: 'VARIABLE' },
      { kind: 'category', name: 'Hàm', categorystyle: 'procedure_category', custom: 'PROCEDURE' },
    ],
  };

  // ---------- Mẫu kéo thả ----------
  const vget = (n) => `<block type="variables_get"><field name="VAR">${n}</field></block>`;
  const numb = (n) => `<shadow type="math_number"><field name="NUM">${n}</field></shadow>`;
  const arith = (op, a, b) => `<block type="math_arithmetic"><field name="OP">${op}</field><value name="A">${a}</value><value name="B">${b}</value></block>`;
  const lenA = '<block type="dsa_array_length"><field name="VAR">a</field></block>';
  const BLOCK_TEMPLATES = [
    {
      id: 'b-bubble', name: 'Kéo thả: Sắp xếp nổi bọt', input: '5 1 4 2 8 3',
      xml: `<xml><variables><variable>a</variable><variable>i</variable><variable>j</variable></variables>
<block type="dsa_array_create" x="20" y="20"><field name="VAR">a</field><field name="STYLE">bars</field>
<value name="LIST"><block type="dsa_read_numbers"></block></value>
<next><block type="controls_for"><field name="VAR">i</field><value name="FROM">${numb(0)}</value>
<value name="TO">${arith('MINUS', lenA, numb(2))}</value><value name="BY">${numb(1)}</value>
<statement name="DO"><block type="controls_for"><field name="VAR">j</field><value name="FROM">${numb(0)}</value>
<value name="TO">${arith('MINUS', arith('MINUS', lenA, numb(2)), vget('i'))}</value><value name="BY">${numb(1)}</value>
<statement name="DO"><block type="controls_if"><value name="IF0"><block type="dsa_array_compare"><field name="VAR">a</field><field name="OP">GT</field>
<value name="I">${vget('j')}</value><value name="J">${arith('ADD', vget('j'), numb(1))}</value></block></value>
<statement name="DO0"><block type="dsa_array_swap"><field name="VAR">a</field><value name="I">${vget('j')}</value><value name="J">${arith('ADD', vget('j'), numb(1))}</value></block></statement>
</block></statement>
<next><block type="dsa_array_mark"><field name="VAR">a</field><field name="COLOR">done</field><value name="I">${arith('MINUS', arith('MINUS', lenA, numb(1)), vget('i'))}</value></block></next>
</block></statement>
<next><block type="dsa_array_mark"><field name="VAR">a</field><field name="COLOR">done</field><value name="I">${numb(0)}</value></block></next>
</block></next></block></xml>`,
    },
    {
      id: 'b-linear', name: 'Kéo thả: Tìm kiếm tuần tự', input: '4 8 15 16 23 42\n23',
      xml: `<xml><variables><variable>a</variable><variable>x</variable><variable>i</variable><variable>nums</variable></variables>
<block type="variables_set" x="20" y="20"><field name="VAR">nums</field><value name="VALUE"><block type="dsa_read_numbers"></block></value>
<next><block type="variables_set"><field name="VAR">x</field><value name="VALUE"><block type="lists_getIndex"><mutation statement="false" at="false"></mutation><field name="MODE">GET_REMOVE</field><field name="WHERE">LAST</field><value name="VALUE">${vget('nums')}</value></block></value>
<next><block type="dsa_array_create"><field name="VAR">a</field><field name="STYLE">box</field><value name="LIST">${vget('nums')}</value>
<next><block type="dsa_var"><field name="NAME">x</field><value name="X">${vget('x')}</value>
<next><block type="controls_for"><field name="VAR">i</field><value name="FROM">${numb(0)}</value><value name="TO">${arith('MINUS', lenA, numb(1))}</value><value name="BY">${numb(1)}</value>
<statement name="DO"><block type="dsa_array_mark"><field name="VAR">a</field><field name="COLOR">compare</field><value name="I">${vget('i')}</value>
<next><block type="controls_if"><value name="IF0"><block type="logic_compare"><field name="OP">EQ</field><value name="A"><block type="dsa_array_get"><field name="VAR">a</field><value name="I">${vget('i')}</value></block></value><value name="B">${vget('x')}</value></block></value>
<statement name="DO0"><block type="dsa_array_mark"><field name="VAR">a</field><field name="COLOR">done</field><value name="I">${vget('i')}</value>
<next><block type="dsa_step"><value name="X"><block type="text_join"><mutation items="2"></mutation><value name="ADD0"><block type="text"><field name="TEXT">Tìm thấy tại vị trí </field></block></value><value name="ADD1">${vget('i')}</value></block></value>
<next><block type="controls_flow_statements"><field name="FLOW">BREAK</field></block></next></block></next></block></statement>
<next><block type="dsa_array_mark"><field name="VAR">a</field><field name="COLOR">dim</field><value name="I">${vget('i')}</value></block></next>
</block></next></block></statement>
</block></next></block></next></block></next></block></next></block></xml>`,
    },
  ];

  let ready = false;
  function setup() {
    if (ready) return true;
    if (!root.Blockly || !root.javascript) return false;
    Blockly.common.defineBlocksWithJsonArray(DEFS);
    defineGenerators(javascript.javascriptGenerator, javascript.Order);
    Blockly.Theme.defineTheme('dsa-dark', {
      name: 'dsa-dark',
      base: Blockly.Themes.Classic,
      componentStyles: {
        workspaceBackgroundColour: '#1e1f22', toolboxBackgroundColour: '#2b2d30', toolboxForegroundColour: '#dfe1e5',
        flyoutBackgroundColour: '#313338', flyoutForegroundColour: '#dfe1e5', flyoutOpacity: 1, scrollbarColour: '#5a5d63',
        insertionMarkerColour: '#ffffff', insertionMarkerOpacity: 0.3, scrollbarOpacity: 0.6, cursorColour: '#d0d0d0',
      },
    });
    ready = true;
    return true;
  }

  // Gắn trình kéo thả vào `container`. onChange(json, code) gọi khi người dùng sửa.
  function mount(container, { json, dark, readOnly, onChange }) {
    if (!setup()) {
      container.textContent = 'Không tải được thư viện kéo thả (Blockly).';
      return null;
    }
    const ws = Blockly.inject(container, {
      toolbox: readOnly ? undefined : TOOLBOX,
      readOnly: !!readOnly,
      renderer: 'zelos',
      theme: dark ? 'dsa-dark' : Blockly.Themes.Classic,
      media: 'vendor/blockly/media/',
      oneBasedIndex: false,
      trashcan: !readOnly,
      zoom: { controls: true, wheel: false, startScale: 0.7, maxScale: 2, minScale: 0.3, scaleSpeed: 1.15 },
      move: { scrollbars: true, drag: true, wheel: true },
      grid: { spacing: 24, length: 2, colour: dark ? '#33363b' : '#e3e5e8', snap: true },
      sounds: false,
    });
    if (json) {
      Blockly.Events.disable();
      try {
        Blockly.serialization.workspaces.load(json, ws);
      } catch (e) {
        console.warn('Không đọc được khối:', e);
      } finally {
        Blockly.Events.enable();
      }
    }
    const code = () => javascript.javascriptGenerator.workspaceToCode(ws);
    if (onChange)
      ws.addChangeListener((e) => {
        if (e.isUiEvent || ws.isDragging()) return;
        onChange(Blockly.serialization.workspaces.save(ws), code());
      });
    return {
      workspace: ws,
      code,
      save: () => Blockly.serialization.workspaces.save(ws),
      loadXml(xml) {
        ws.clear();
        Blockly.Xml.domToWorkspace(Blockly.utils.xml.textToDom(xml), ws);
        onChange && onChange(Blockly.serialization.workspaces.save(ws), code());
      },
      resize: () => Blockly.svgResize(ws),
      dispose: () => ws.dispose(),
    };
  }

  // Chuyển mẫu XML → { json, code } không cần hiển thị (dùng khi tạo notebook).
  function fromXml(xml) {
    if (!setup()) return null;
    const ws = new Blockly.Workspace(new Blockly.Options({ oneBasedIndex: false }));
    try {
      Blockly.Xml.domToWorkspace(Blockly.utils.xml.textToDom(xml), ws);
      return { json: Blockly.serialization.workspaces.save(ws), code: javascript.javascriptGenerator.workspaceToCode(ws) };
    } finally {
      ws.dispose();
    }
  }

  root.BLOCKS = { mount, fromXml, BLOCK_TEMPLATES, available: () => !!(root.Blockly && root.javascript) };
})(typeof globalThis !== 'undefined' ? globalThis : this);
