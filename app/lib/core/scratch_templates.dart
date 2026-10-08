// Mẫu mô phỏng dạng khối kéo thả.
import 'scratch.dart';
import 'vcs.dart' show Json, deepClone;

Json _n(String op, [Map<String, dynamic> a = const {}, List? body, List? other]) {
  final n = newNode(op, a: Map<String, dynamic>.from(a));
  if (body != null) n['do'] = body;
  if (other != null) n['else'] = other;
  return n;
}

Json _v(String name) => _n('var_get', {'VAR': name});
Json _op(dynamic a, String op, dynamic b) => _n('arith', {'A': a, 'OP': op, 'B': b});
Json _cmp(dynamic a, String op, dynamic b) => _n('compare', {'A': a, 'OP': op, 'B': b});
Json _len(String arr) => _n('array_len', {'VAR': arr});
Json _get(String arr, dynamic i) => _n('array_get', {'VAR': arr, 'I': i});

class BlockTemplate {
  final String id, name, input;
  final Json Function() build;
  const BlockTemplate(this.id, this.name, this.input, this.build);
  Json program() => deepClone(build()) as Json;
}

final blockTemplates = <BlockTemplate>[
  BlockTemplate('k-bubble', 'Sắp xếp nổi bọt', '5 1 4 2 8 3', () => {
        'v': 2,
        'vars': ['a', 'i', 'j'],
        'funcs': [],
        'main': [
          _n('array_create', {'VAR': 'a', 'LIST': _n('read_numbers'), 'STYLE': 'bars'}),
          _n('for', {'VAR': 'i', 'FROM': '0', 'TO': _op(_len('a'), '-', '2'), 'BY': '1'}, [
            _n('for', {'VAR': 'j', 'FROM': '0', 'TO': _op(_op(_len('a'), '-', '2'), '-', _v('i')), 'BY': '1'}, [
              _n('array_pointer', {'NAME': 'j', 'VAR': 'a', 'I': _v('j')}),
              _n('if', {'COND': _n('array_compare', {'VAR': 'a', 'I': _v('j'), 'OP': '>', 'J': _op(_v('j'), '+', '1')})}, [
                _n('array_swap', {'VAR': 'a', 'I': _v('j'), 'J': _op(_v('j'), '+', '1')}),
              ]),
            ]),
            _n('array_mark', {'VAR': 'a', 'I': _op(_op(_len('a'), '-', '1'), '-', _v('i')), 'COLOR': 'done'}),
          ]),
          _n('array_mark', {'VAR': 'a', 'I': '0', 'COLOR': 'done'}),
          _n('array_unpointer', {'NAME': 'j', 'VAR': 'a'}),
          _n('step', {'X': 'Đã sắp xếp xong'}),
        ],
      }),
  BlockTemplate('k-selection', 'Sắp xếp chọn', '29 10 14 37 13 5', () => {
        'v': 2,
        'vars': ['a', 'i', 'j', 'nho'],
        'funcs': [],
        'main': [
          _n('array_create', {'VAR': 'a', 'LIST': _n('read_numbers'), 'STYLE': 'bars'}),
          _n('for', {'VAR': 'i', 'FROM': '0', 'TO': _op(_len('a'), '-', '2'), 'BY': '1'}, [
            _n('var_set', {'VAR': 'nho', 'X': _v('i')}),
            _n('array_pointer', {'NAME': 'min', 'VAR': 'a', 'I': _v('nho')}),
            _n('for', {'VAR': 'j', 'FROM': _op(_v('i'), '+', '1'), 'TO': _op(_len('a'), '-', '1'), 'BY': '1'}, [
              _n('if', {'COND': _n('array_compare', {'VAR': 'a', 'I': _v('j'), 'OP': '<', 'J': _v('nho')})}, [
                _n('var_set', {'VAR': 'nho', 'X': _v('j')}),
                _n('array_pointer', {'NAME': 'min', 'VAR': 'a', 'I': _v('nho')}),
              ]),
            ]),
            _n('if', {'COND': _cmp(_v('nho'), '!=', _v('i'))}, [
              _n('array_swap', {'VAR': 'a', 'I': _v('i'), 'J': _v('nho')}),
            ]),
            _n('array_mark', {'VAR': 'a', 'I': _v('i'), 'COLOR': 'done'}),
          ]),
          _n('array_mark', {'VAR': 'a', 'I': _op(_len('a'), '-', '1'), 'COLOR': 'done'}),
          _n('array_unpointer', {'NAME': 'min', 'VAR': 'a'}),
        ],
      }),
  BlockTemplate('k-insertion', 'Sắp xếp chèn', '7 3 9 1 6 2', () => {
        'v': 2,
        'vars': ['a', 'i', 'j'],
        'funcs': [],
        'main': [
          _n('array_create', {'VAR': 'a', 'LIST': _n('read_numbers'), 'STYLE': 'bars'}),
          _n('array_mark', {'VAR': 'a', 'I': '0', 'COLOR': 'done'}),
          _n('for', {'VAR': 'i', 'FROM': '1', 'TO': _op(_len('a'), '-', '1'), 'BY': '1'}, [
            _n('var_set', {'VAR': 'j', 'X': _v('i')}),
            _n('while', {
              'COND': _n('and', {'A': _cmp(_v('j'), '>', '0'), 'OP': '&&', 'B': _n('array_compare', {'VAR': 'a', 'I': _op(_v('j'), '-', '1'), 'OP': '>', 'J': _v('j')})}),
            }, [
              _n('array_swap', {'VAR': 'a', 'I': _op(_v('j'), '-', '1'), 'J': _v('j')}),
              _n('var_change', {'VAR': 'j', 'X': '-1'}),
            ]),
            _n('array_mark_range', {'VAR': 'a', 'L': '0', 'R': _v('i'), 'COLOR': 'done'}),
          ]),
        ],
      }),
  BlockTemplate('k-binary', 'Tìm kiếm nhị phân', '1 3 5 7 9 11 13 15 17\n13', () => {
        'v': 2,
        'vars': ['so', 'x', 'a', 'l', 'r', 'm'],
        'funcs': [],
        'main': [
          _n('var_set', {'VAR': 'so', 'X': _n('read_numbers')}),
          _n('var_set', {'VAR': 'x', 'X': _n('list_pop', {'VAR': 'so'})}),
          _n('array_create', {'VAR': 'a', 'LIST': _v('so'), 'STYLE': 'box'}),
          _n('var_set', {'VAR': 'l', 'X': '0'}),
          _n('var_set', {'VAR': 'r', 'X': _op(_len('a'), '-', '1')}),
          _n('while', {'COND': _cmp(_v('l'), '<=', _v('r'))}, [
            _n('var_set', {'VAR': 'm', 'X': _n('idiv', {'A': _op(_v('l'), '+', _v('r')), 'B': '2'})}),
            _n('array_pointer', {'NAME': 'l', 'VAR': 'a', 'I': _v('l')}),
            _n('array_pointer', {'NAME': 'r', 'VAR': 'a', 'I': _v('r')}),
            _n('array_pointer', {'NAME': 'm', 'VAR': 'a', 'I': _v('m')}),
            _n('array_highlight', {'VAR': 'a', 'I': _v('m'), 'COLOR': 'compare'}),
            _n('ifelse', {'COND': _cmp(_get('a', _v('m')), '==', _v('x'))}, [
              _n('array_mark', {'VAR': 'a', 'I': _v('m'), 'COLOR': 'done'}),
              _n('step', {'X': _n('join', {'A': 'Tìm thấy tại vị trí ', 'B': _v('m')})}),
              _n('break'),
            ], [
              _n('ifelse', {'COND': _cmp(_get('a', _v('m')), '<', _v('x'))}, [
                _n('array_mark_range', {'VAR': 'a', 'L': _v('l'), 'R': _v('m'), 'COLOR': 'dim'}),
                _n('var_set', {'VAR': 'l', 'X': _op(_v('m'), '+', '1')}),
              ], [
                _n('array_mark_range', {'VAR': 'a', 'L': _v('m'), 'R': _v('r'), 'COLOR': 'dim'}),
                _n('var_set', {'VAR': 'r', 'X': _op(_v('m'), '-', '1')}),
              ]),
            ]),
          ]),
        ],
      }),
  BlockTemplate('k-brackets', 'Stack: kiểm tra ngoặc', '({[]})[', () => {
        'v': 2,
        'vars': ['st', 'c', 'dung'],
        'funcs': [],
        'main': [
          _n('ds_create', {'VAR': 'st', 'KIND': 'stack'}),
          _n('var_set', {'VAR': 'dung', 'X': _n('bool', {'V': 'true'})}),
          _n('foreach', {'VAR': 'c', 'LIST': _n('input_text')}, [
            _n('ifelse', {'COND': _n('text_has', {'X': '([{', 'Y': _v('c')})}, [
              _n('ds_push', {'VAR': 'st', 'X': _v('c')}),
            ], [
              _n('if', {'COND': _n('text_has', {'X': ')]}', 'Y': _v('c')})}, [
                _n('ifelse', {
                  'COND': _n('and', {
                    'A': _n('not', {'A': _n('ds_empty', {'VAR': 'st'})}),
                    'OP': '&&',
                    'B': _cmp(_n('char_at', {'I': _n('text_index', {'Y': _v('c'), 'X': ')]}'}), 'X': '([{'}), '==', _n('ds_peek', {'VAR': 'st', 'WHICH': 'top'})),
                  }),
                }, [
                  _n('ds_pop_stmt', {'VAR': 'st'}),
                ], [
                  _n('var_set', {'VAR': 'dung', 'X': _n('bool', {'V': 'false'})}),
                  _n('step', {'X': _n('join', {'A': 'Ngoặc đóng không khớp: ', 'B': _v('c')})}),
                  _n('break'),
                ]),
              ]),
            ]),
          ]),
          _n('ifelse', {'COND': _n('and', {'A': _cmp(_v('dung'), '==', _n('bool', {'V': 'true'})), 'OP': '&&', 'B': _n('ds_empty', {'VAR': 'st'})})}, [
            _n('step', {'X': 'Dãy ngoặc ĐÚNG'}),
          ], [
            _n('step', {'X': 'Dãy ngoặc SAI'}),
          ]),
        ],
      }),
  BlockTemplate('k-bfs', 'BFS trên lưới', 'S..#....\n.#.#.##.\n.#...#..\n.####.#.\n......#E', () => {
        'v': 2,
        'vars': ['g', 'q', 'r', 'c', 'o', 'k', 'nr', 'nc', 'dr', 'dc'],
        'funcs': [],
        'main': [
          _n('grid_from_lines', {'VAR': 'g', 'LINES': _n('input_lines')}),
          _n('auto', {'ON': 'false'}),
          _n('var_set', {'VAR': 'dr', 'X': _n('list_of', {'T': '-1 1 0 0'})}),
          _n('var_set', {'VAR': 'dc', 'X': _n('list_of', {'T': '0 0 -1 1'})}),
          _n('for', {'VAR': 'r', 'FROM': '0', 'TO': _op(_n('grid_size', {'VAR': 'g', 'DIM': 'rows'}), '-', '1'), 'BY': '1'}, [
            _n('for', {'VAR': 'c', 'FROM': '0', 'TO': _op(_n('grid_size', {'VAR': 'g', 'DIM': 'cols'}), '-', '1'), 'BY': '1'}, [
              _n('if', {'COND': _cmp(_n('grid_get', {'VAR': 'g', 'R': _v('r'), 'C': _v('c')}), '==', '#')}, [
                _n('grid_mark', {'VAR': 'g', 'R': _v('r'), 'C': _v('c'), 'COLOR': 'wall'}),
              ]),
              _n('if', {'COND': _cmp(_n('grid_get', {'VAR': 'g', 'R': _v('r'), 'C': _v('c')}), '==', 'S')}, [
                _n('ds_create', {'VAR': 'q', 'KIND': 'queue'}),
                _n('ds_push', {'VAR': 'q', 'X': _op(_op(_v('r'), '*', '1000'), '+', _v('c'))}),
                _n('grid_mark', {'VAR': 'g', 'R': _v('r'), 'C': _v('c'), 'COLOR': 'start'}),
                _n('grid_set', {'VAR': 'g', 'R': _v('r'), 'C': _v('c'), 'X': '0'}),
              ]),
            ]),
          ]),
          _n('auto', {'ON': 'true'}),
          _n('step', {'X': 'Bắt đầu loang từ S'}),
          _n('until', {'COND': _n('ds_empty', {'VAR': 'q'})}, [
            _n('var_set', {'VAR': 'o', 'X': _n('ds_pop', {'VAR': 'q'})}),
            _n('var_set', {'VAR': 'r', 'X': _n('idiv', {'A': _v('o'), 'B': '1000'})}),
            _n('var_set', {'VAR': 'c', 'X': _n('mod', {'A': _v('o'), 'B': '1000'})}),
            _n('for', {'VAR': 'k', 'FROM': '0', 'TO': '3', 'BY': '1'}, [
              _n('var_set', {'VAR': 'nr', 'X': _op(_v('r'), '+', _n('list_get', {'I': _v('k'), 'L': _v('dr')}))}),
              _n('var_set', {'VAR': 'nc', 'X': _op(_v('c'), '+', _n('list_get', {'I': _v('k'), 'L': _v('dc')}))}),
              _n('if', {
                'COND': _n('and', {
                  'A': _n('grid_inside', {'VAR': 'g', 'R': _v('nr'), 'C': _v('nc')}),
                  'OP': '&&',
                  'B': _n('and', {
                    'A': _n('not', {'A': _n('grid_is', {'VAR': 'g', 'R': _v('nr'), 'C': _v('nc'), 'COLOR': 'wall'})}),
                    'OP': '&&',
                    'B': _n('not', {'A': _n('grid_is', {'VAR': 'g', 'R': _v('nr'), 'C': _v('nc'), 'COLOR': 'visited'})}),
                  }),
                }),
              }, [
                _n('if', {'COND': _cmp(_n('grid_get', {'VAR': 'g', 'R': _v('nr'), 'C': _v('nc')}), '==', 'E')}, [
                  _n('grid_mark', {'VAR': 'g', 'R': _v('nr'), 'C': _v('nc'), 'COLOR': 'end'}),
                  _n('step', {'X': _n('join', {'A': 'Đến đích sau ', 'B': _n('join', {'A': _op(_n('grid_get', {'VAR': 'g', 'R': _v('r'), 'C': _v('c')}), '+', '1'), 'B': ' bước'})})}),
                  _n('stop'),
                ]),
                _n('grid_set', {'VAR': 'g', 'R': _v('nr'), 'C': _v('nc'), 'X': _op(_n('grid_get', {'VAR': 'g', 'R': _v('r'), 'C': _v('c')}), '+', '1')}),
                _n('grid_mark', {'VAR': 'g', 'R': _v('nr'), 'C': _v('nc'), 'COLOR': 'visited'}),
                _n('ds_push', {'VAR': 'q', 'X': _op(_op(_v('nr'), '*', '1000'), '+', _v('nc'))}),
              ]),
            ]),
          ]),
          _n('step', {'X': 'Không tới được đích'}),
        ],
      }),
  BlockTemplate('k-dfs', 'DFS đệ quy trên đồ thị (dùng hàm)', '1 2 1 3 2 4 2 5 3 6 5 6', () => {
        'v': 2,
        'vars': ['G', 'da', 'v', 'u'],
        'funcs': [
          {
            'name': 'dfs',
            'params': ['u'],
            'body': [
              _n('list_push', {'VAR': 'da', 'X': _v('u')}),
              _n('graph_visit', {'VAR': 'G', 'N': _v('u'), 'COLOR': 'visited'}),
              _n('foreach', {'VAR': 'v', 'LIST': _n('graph_neighbors', {'VAR': 'G', 'N': _v('u')})}, [
                _n('if', {'COND': _n('not', {'A': _n('list_has', {'L': _v('da'), 'X': _v('v')})})}, [
                  _n('graph_edge', {'VAR': 'G', 'U': _v('u'), 'W': _v('v'), 'COLOR': 'path'}),
                  _n('call', {'FN': 'dfs', 'P0': _v('v')}),
                ]),
              ]),
              _n('graph_visit', {'VAR': 'G', 'N': _v('u'), 'COLOR': 'done'}),
            ],
          },
        ],
        'main': [
          _n('graph_create', {'VAR': 'G', 'LIST': _n('read_numbers'), 'K': '2', 'DIR': 'false'}),
          _n('var_set', {'VAR': 'da', 'X': _n('list_new')}),
          _n('call', {'FN': 'dfs', 'P0': _n('input_k', {'K': '0'})}),
          _n('step', {'X': _n('join', {'A': 'Thứ tự thăm: ', 'B': _n('list_text', {'L': _v('da')})})}),
        ],
      }),
  BlockTemplate('k-bst', 'Cây nhị phân tìm kiếm (chèn)', '50 30 70 20 40 60 80 35', () => {
        'v': 2,
        'vars': ['T', 'x', 'cur', 'trai', 'phai'],
        'funcs': [],
        'main': [
          _n('tree_create', {'VAR': 'T'}),
          _n('var_set', {'VAR': 'trai', 'X': _n('js_expr', {'CODE': '{}'})}),
          _n('var_set', {'VAR': 'phai', 'X': _n('js_expr', {'CODE': '{}'})}),
          _n('foreach', {'VAR': 'x', 'LIST': _n('read_numbers')}, [
            _n('ifelse', {'COND': _cmp(_n('list_len', {'L': _n('graph_nodes', {'VAR': 'T'})}), '==', '0')}, [
              _n('graph_add_node', {'VAR': 'T', 'N': _v('x')}),
            ], [
              _n('var_set', {'VAR': 'cur', 'X': _n('list_get', {'I': '0', 'L': _n('graph_nodes', {'VAR': 'T'})})}),
              _n('repeat', {'N': '100'}, [
                _n('graph_highlight', {'VAR': 'T', 'N': _v('cur')}),
                _n('ifelse', {'COND': _cmp(_v('x'), '<', _v('cur'))}, [
                  _n('if', {'COND': _cmp(_n('js_expr', {'CODE': 'v_trai[v_cur]'}), '==', _n('js_expr', {'CODE': 'undefined'}))}, [
                    _n('js', {'CODE': 'v_trai[v_cur] = v_x;'}),
                    _n('graph_add_edge', {'VAR': 'T', 'U': _v('cur'), 'W': _v('x'), 'C': ''}),
                    _n('break'),
                  ]),
                  _n('var_set', {'VAR': 'cur', 'X': _n('js_expr', {'CODE': 'v_trai[v_cur]'})}),
                ], [
                  _n('if', {'COND': _cmp(_n('js_expr', {'CODE': 'v_phai[v_cur]'}), '==', _n('js_expr', {'CODE': 'undefined'}))}, [
                    _n('js', {'CODE': 'v_phai[v_cur] = v_x;'}),
                    _n('graph_add_edge', {'VAR': 'T', 'U': _v('cur'), 'W': _v('x'), 'C': ''}),
                    _n('break'),
                  ]),
                  _n('var_set', {'VAR': 'cur', 'X': _n('js_expr', {'CODE': 'v_phai[v_cur]'})}),
                ]),
              ]),
            ]),
          ]),
          _n('step', {'X': 'Cây BST sau khi chèn tất cả các số'}),
        ],
      }),
];
