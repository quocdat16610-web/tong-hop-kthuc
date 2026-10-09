// Thư viện code mẫu C++ cho DSA: chèn nhanh vào IDE hoặc khối code.
class Snippet {
  final String name, group, note, code;
  const Snippet(this.group, this.name, this.note, this.code);
}

const snippets = <Snippet>[
  Snippet('Khung', 'Khung bài thi (đọc nhanh)', 'main + tắt đồng bộ cin/cout', r'''#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);

    return 0;
}
'''),
  Snippet('Khung', 'Nhiều test (t test)', 'Đọc số test rồi giải từng test', r'''void solve() {

}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int t;
    cin >> t;
    while (t--) solve();
}
'''),
  Snippet('Cấu trúc dữ liệu', 'DSU (hợp nhất tập hợp)', 'find có nén đường, unite theo kích thước — O(α(n))', r'''struct DSU {
    vector<int> p, sz;
    DSU(int n) : p(n), sz(n, 1) { iota(p.begin(), p.end(), 0); }
    int find(int x) { return p[x] == x ? x : p[x] = find(p[x]); }
    bool unite(int a, int b) {
        a = find(a), b = find(b);
        if (a == b) return false;
        if (sz[a] < sz[b]) swap(a, b);
        p[b] = a;
        sz[a] += sz[b];
        return true;
    }
};
'''),
  Snippet('Cấu trúc dữ liệu', 'Fenwick (BIT) — tổng tiền tố', 'Cập nhật điểm, truy vấn tổng đoạn — O(log n), đánh số từ 1', r'''struct Fenwick {
    int n;
    vector<long long> t;
    Fenwick(int n) : n(n), t(n + 1, 0) {}
    void add(int i, long long v) { for (; i <= n; i += i & -i) t[i] += v; }
    long long sum(int i) { long long s = 0; for (; i > 0; i -= i & -i) s += t[i]; return s; }
    long long sum(int l, int r) { return sum(r) - sum(l - 1); }
};
'''),
  Snippet('Cấu trúc dữ liệu', 'Cây phân đoạn (min đoạn)', 'Cập nhật điểm, truy vấn min [l, r] — O(log n), đánh số từ 0', r'''struct SegTree {
    int n;
    vector<long long> t;
    SegTree(int n) : n(n), t(2 * n, LLONG_MAX) {}
    void update(int i, long long v) {
        for (t[i += n] = v; i > 1; i >>= 1) t[i >> 1] = min(t[i], t[i ^ 1]);
    }
    long long query(int l, int r) { // [l, r]
        long long res = LLONG_MAX;
        for (l += n, r += n + 1; l < r; l >>= 1, r >>= 1) {
            if (l & 1) res = min(res, t[l++]);
            if (r & 1) res = min(res, t[--r]);
        }
        return res;
    }
};
'''),
  Snippet('Cấu trúc dữ liệu', 'Bảng thưa (Sparse Table) RMQ', 'Tiền xử lý O(n log n), truy vấn min O(1)', r'''struct SparseTable {
    vector<vector<int>> st;
    vector<int> lg;
    SparseTable(const vector<int>& a) {
        int n = a.size(), K = __lg(max(n, 1)) + 1;
        st.assign(K, a);
        lg.assign(n + 1, 0);
        for (int i = 2; i <= n; i++) lg[i] = lg[i / 2] + 1;
        for (int k = 1; k < K; k++)
            for (int i = 0; i + (1 << k) <= n; i++)
                st[k][i] = min(st[k - 1][i], st[k - 1][i + (1 << (k - 1))]);
    }
    int query(int l, int r) { // [l, r]
        int k = lg[r - l + 1];
        return min(st[k][l], st[k][r - (1 << k) + 1]);
    }
};
'''),
  Snippet('Đồ thị', 'BFS (đường đi ngắn nhất, không trọng số)', 'dist[v] = số cạnh ít nhất từ s — O(n + m)', r'''vector<int> bfs(int s, const vector<vector<int>>& g) {
    vector<int> dist(g.size(), -1);
    queue<int> q;
    dist[s] = 0;
    q.push(s);
    while (!q.empty()) {
        int u = q.front(); q.pop();
        for (int v : g[u])
            if (dist[v] == -1) {
                dist[v] = dist[u] + 1;
                q.push(v);
            }
    }
    return dist;
}
'''),
  Snippet('Đồ thị', 'DFS đệ quy', 'Duyệt sâu, đánh dấu đã thăm — O(n + m)', r'''vector<vector<int>> g;
vector<bool> visited;

void dfs(int u) {
    visited[u] = true;
    for (int v : g[u])
        if (!visited[v]) dfs(v);
}
'''),
  Snippet('Đồ thị', 'Dijkstra', 'Đường đi ngắn nhất, trọng số không âm — O((n + m) log n)', r'''vector<long long> dijkstra(int s, const vector<vector<pair<int, int>>>& g) {
    vector<long long> d(g.size(), LLONG_MAX);
    priority_queue<pair<long long, int>, vector<pair<long long, int>>, greater<>> pq;
    d[s] = 0;
    pq.push({0, s});
    while (!pq.empty()) {
        auto [du, u] = pq.top(); pq.pop();
        if (du != d[u]) continue;
        for (auto [v, w] : g[u])
            if (d[u] + w < d[v]) {
                d[v] = d[u] + w;
                pq.push({d[v], v});
            }
    }
    return d;
}
'''),
  Snippet('Đồ thị', 'Sắp xếp tô-pô (Kahn)', 'Thứ tự tô-pô của DAG; rỗng nếu có chu trình', r'''vector<int> topoSort(const vector<vector<int>>& g) {
    int n = g.size();
    vector<int> indeg(n, 0), order;
    for (int u = 0; u < n; u++) for (int v : g[u]) indeg[v]++;
    queue<int> q;
    for (int u = 0; u < n; u++) if (indeg[u] == 0) q.push(u);
    while (!q.empty()) {
        int u = q.front(); q.pop();
        order.push_back(u);
        for (int v : g[u]) if (--indeg[v] == 0) q.push(v);
    }
    if ((int)order.size() < n) return {}; // có chu trình
    return order;
}
'''),
  Snippet('Đồ thị', 'Kruskal (cây khung nhỏ nhất)', 'Cần DSU — O(m log m)', r'''// cạnh: {w, u, v}; cần struct DSU
long long kruskal(int n, vector<array<int, 3>> edges) {
    sort(edges.begin(), edges.end());
    DSU d(n);
    long long total = 0;
    for (auto [w, u, v] : edges)
        if (d.unite(u, v)) total += w;
    return total;
}
'''),
  Snippet('Tìm kiếm', 'Tìm kiếm nhị phân trên kết quả', 'Tìm x nhỏ nhất thoả ok(x) (ok đơn điệu)', r'''// ok(x) sai ... sai đúng ... đúng → trả về x đúng đầu tiên trong [lo, hi]
long long firstTrue(long long lo, long long hi, function<bool(long long)> ok) {
    while (lo < hi) {
        long long mid = lo + (hi - lo) / 2;
        if (ok(mid)) hi = mid;
        else lo = mid + 1;
    }
    return lo;
}
'''),
  Snippet('Tìm kiếm', 'Hai con trỏ (cặp có tổng = x)', 'Mảng đã sắp xếp — O(n)', r'''bool hasPairSum(const vector<int>& a, int x) {
    int l = 0, r = (int)a.size() - 1;
    while (l < r) {
        int s = a[l] + a[r];
        if (s == x) return true;
        if (s < x) l++;
        else r--;
    }
    return false;
}
'''),
  Snippet('Quy hoạch động', 'Dãy con tăng dài nhất (LIS)', 'O(n log n)', r'''int lis(const vector<int>& a) {
    vector<int> d;
    for (int x : a) {
        auto it = lower_bound(d.begin(), d.end(), x);
        if (it == d.end()) d.push_back(x);
        else *it = x;
    }
    return d.size();
}
'''),
  Snippet('Quy hoạch động', 'Cái túi 0/1', 'W là sức chứa — O(n·W)', r'''long long knapsack(const vector<int>& w, const vector<long long>& v, int W) {
    vector<long long> dp(W + 1, 0);
    for (int i = 0; i < (int)w.size(); i++)
        for (int c = W; c >= w[i]; c--)
            dp[c] = max(dp[c], dp[c - w[i]] + v[i]);
    return dp[W];
}
'''),
  Snippet('Quy hoạch động', 'Xâu con chung dài nhất (LCS)', 'O(n·m)', r'''int lcs(const string& a, const string& b) {
    int n = a.size(), m = b.size();
    vector<vector<int>> dp(n + 1, vector<int>(m + 1, 0));
    for (int i = 1; i <= n; i++)
        for (int j = 1; j <= m; j++)
            dp[i][j] = a[i - 1] == b[j - 1] ? dp[i - 1][j - 1] + 1 : max(dp[i - 1][j], dp[i][j - 1]);
    return dp[n][m];
}
'''),
  Snippet('Chuỗi', 'KMP (tìm chuỗi con)', 'Vị trí mọi lần xuất hiện của p trong s — O(n + m)', r'''vector<int> kmp(const string& s, const string& p) {
    string t = p + '#' + s;
    vector<int> pi(t.size(), 0), res;
    for (int i = 1; i < (int)t.size(); i++) {
        int j = pi[i - 1];
        while (j > 0 && t[i] != t[j]) j = pi[j - 1];
        if (t[i] == t[j]) j++;
        pi[i] = j;
        if (j == (int)p.size()) res.push_back(i - 2 * p.size());
    }
    return res;
}
'''),
  Snippet('Toán', 'Sàng Eratosthenes', 'Đánh dấu số nguyên tố ≤ n — O(n log log n)', r'''vector<bool> sieve(int n) {
    vector<bool> prime(n + 1, true);
    prime[0] = false;
    if (n >= 1) prime[1] = false;
    for (int i = 2; 1LL * i * i <= n; i++)
        if (prime[i])
            for (int j = i * i; j <= n; j += i) prime[j] = false;
    return prime;
}
'''),
  Snippet('Toán', 'Luỹ thừa nhanh mod', 'a^b mod m — O(log b)', r'''long long power(long long a, long long b, long long m) {
    long long r = 1;
    a %= m;
    while (b > 0) {
        if (b & 1) r = r * a % m;
        a = a * a % m;
        b >>= 1;
    }
    return r;
}
'''),
  Snippet('Toán', 'GCD / LCM', 'Ước chung lớn nhất, bội chung nhỏ nhất', r'''long long gcdll(long long a, long long b) { return b == 0 ? a : gcdll(b, a % b); }
long long lcmll(long long a, long long b) { return a / gcdll(a, b) * b; }
'''),
];
