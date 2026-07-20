// 同步面板页面：纯静态 HTML + 原生 JS，无构建依赖。
// 页面本身无需认证即可访问；所有数据接口通过用户填入的 Bearer Token 调用。
// 注意：本文件整体是一个模板字符串，内部 JS 一律使用字符串拼接，避免出现 ${ 或反引号。
export const DASHBOARD_HTML = `<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ZFStatMenus 同步面板</title>
<style>
  :root {
    --bg: #f5f5f7; --surface: #ffffff; --surface-2: #f5f5f7; --text: #1d1d1f;
    --muted: #86868b; --border: rgba(0,0,0,.08); --hairline: rgba(0,0,0,.05);
    --accent: #0a84ff; --accent-soft: rgba(10,132,255,.1); --accent-border: rgba(10,132,255,.28);
    --violet: #af52de; --violet-soft: rgba(175,82,222,.1); --violet-border: rgba(175,82,222,.28);
    --danger: #ff3b30; --danger-soft: rgba(255,59,48,.08); --danger-border: rgba(255,59,48,.25);
    --success: #30d158;
    --radius: 14px;
    --shadow-sm: 0 1px 2px rgba(0,0,0,.04), 0 4px 16px rgba(0,0,0,.04);
    --shadow-md: 0 2px 4px rgba(0,0,0,.05), 0 12px 32px rgba(0,0,0,.08);
    --topbar-bg: rgba(255,255,255,.75);
    --thead-bg: rgba(250,250,252,.85);
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #000000; --surface: #1c1c1e; --surface-2: #2c2c2e; --text: #f5f5f7;
      --muted: #98989d; --border: rgba(255,255,255,.1); --hairline: rgba(255,255,255,.06);
      --accent: #0a84ff; --accent-soft: rgba(10,132,255,.16); --accent-border: rgba(10,132,255,.4);
      --violet: #bf5af2; --violet-soft: rgba(191,90,242,.14); --violet-border: rgba(191,90,242,.35);
      --danger: #ff453a; --danger-soft: rgba(255,69,58,.12); --danger-border: rgba(255,69,58,.35);
      --shadow-sm: 0 1px 2px rgba(0,0,0,.4), 0 4px 16px rgba(0,0,0,.25);
      --shadow-md: 0 2px 4px rgba(0,0,0,.45), 0 12px 32px rgba(0,0,0,.4);
      --topbar-bg: rgba(20,20,22,.75);
      --thead-bg: rgba(38,38,40,.85);
    }
  }
  * { box-sizing: border-box; }
  html { -webkit-font-smoothing: antialiased; text-rendering: optimizeLegibility; }
  body { margin: 0; background: var(--bg); color: var(--text);
    font: 14px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", "PingFang SC", "Helvetica Neue", sans-serif; }
  ::selection { background: var(--accent-soft); }

  .topbar { display: flex; align-items: center; gap: 10px; padding: 12px 24px;
    background: var(--topbar-bg); border-bottom: 1px solid var(--hairline);
    position: sticky; top: 0; z-index: 20;
    -webkit-backdrop-filter: saturate(180%) blur(20px); backdrop-filter: saturate(180%) blur(20px); }
  .brand { width: 28px; height: 28px; border-radius: 8px; flex: none; color: #fff;
    background: linear-gradient(135deg, #34c759 0%, #0a84ff 100%);
    display: flex; align-items: center; justify-content: center;
    font-size: 12px; font-weight: 700; letter-spacing: .5px;
    box-shadow: inset 0 0 0 1px rgba(255,255,255,.18), 0 2px 6px rgba(10,132,255,.35); }
  .topbar h1 { font-size: 15px; margin: 0; font-weight: 600; letter-spacing: -.01em; }
  .topbar .spacer { flex: 1; }
  .topbar .meta { color: var(--muted); font-size: 12px; display: flex; align-items: center; gap: 6px; }
  .status-dot { width: 7px; height: 7px; border-radius: 50%; background: var(--success);
    box-shadow: 0 0 0 3px rgba(48,209,88,.18); }

  .wrap { max-width: 1120px; margin: 0 auto; padding: 28px 24px 48px; }

  .card { background: var(--surface); border: 1px solid var(--hairline); border-radius: var(--radius);
    box-shadow: var(--shadow-sm); }

  .auth-card { max-width: 400px; margin: 10vh auto 0; padding: 32px 28px 28px; text-align: center; }
  .auth-card .logo { width: 52px; height: 52px; border-radius: 14px; margin: 0 auto 16px; color: #fff;
    background: linear-gradient(135deg, #34c759 0%, #0a84ff 100%);
    display: flex; align-items: center; justify-content: center; font-size: 20px; font-weight: 700;
    box-shadow: inset 0 0 0 1px rgba(255,255,255,.18), 0 6px 18px rgba(10,132,255,.4); }
  .auth-card h2 { margin: 0 0 8px; font-size: 19px; font-weight: 600; letter-spacing: -.01em; }
  .auth-card p { margin: 0 0 20px; color: var(--muted); font-size: 13px; line-height: 1.6; }
  .auth-card .btn { width: 100%; padding: 10px 14px; font-size: 14px; margin-top: 12px; }

  input, select { background: var(--surface-2); border: 1px solid var(--border); border-radius: 9px;
    color: var(--text); padding: 8px 11px; font-size: 13px; font-family: inherit;
    transition: border-color .15s ease, box-shadow .15s ease; }
  input:focus, select:focus { outline: none; border-color: var(--accent);
    box-shadow: 0 0 0 3.5px var(--accent-soft); }
  input[type=text], input[type=password] { width: 100%; }

  .btn { background: var(--surface); border: 1px solid var(--border); border-radius: 9px; color: var(--text);
    padding: 7px 14px; font-size: 13px; font-family: inherit; cursor: pointer;
    transition: border-color .15s ease, color .15s ease, box-shadow .15s ease, transform .05s ease; }
  .btn:hover { border-color: var(--accent); color: var(--accent); }
  .btn:active { transform: scale(.97); }
  .btn.primary { background: linear-gradient(180deg, #2b9aff 0%, #0a84ff 100%); border-color: transparent;
    color: #fff; font-weight: 500; box-shadow: 0 2px 8px rgba(10,132,255,.35); }
  .btn.primary:hover { color: #fff; filter: brightness(1.06); }
  .btn.small { padding: 4px 11px; font-size: 12px; border-radius: 8px; }
  .btn.danger:hover { border-color: var(--danger); color: var(--danger); }

  .controls { display: flex; align-items: center; gap: 20px; flex-wrap: wrap;
    padding: 12px 18px; margin-bottom: 20px; }
  .controls label { color: var(--muted); font-size: 11px; font-weight: 500; letter-spacing: .04em;
    display: flex; align-items: center; gap: 8px; text-transform: uppercase; }
  .controls select, .controls input { text-transform: none; letter-spacing: normal; }
  #rate-status { font-size: 12px; color: var(--muted); }
  #rate-status.ok { color: var(--success); }

  .error { background: var(--danger-soft); border: 1px solid var(--danger-border); color: var(--danger);
    border-radius: 10px; padding: 11px 16px; margin-bottom: 18px; font-size: 13px; display: none; }

  .cards { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; margin-bottom: 8px; }
  .stat { position: relative; overflow: hidden; background: var(--surface);
    border: 1px solid var(--hairline); border-radius: var(--radius); padding: 18px 20px 16px;
    box-shadow: var(--shadow-sm); transition: transform .18s ease, box-shadow .18s ease; }
  .stat:hover { transform: translateY(-2px); box-shadow: var(--shadow-md); }
  .stat::before { content: ""; position: absolute; left: 0; right: 0; top: 0; height: 3px;
    background: linear-gradient(90deg, var(--accent), transparent 75%); opacity: .85; }
  .stat:nth-child(2)::before { background: linear-gradient(90deg, var(--violet), transparent 75%); }
  .stat:nth-child(3)::before { background: linear-gradient(90deg, var(--success), transparent 75%); }
  .stat .head { display: flex; align-items: center; justify-content: space-between; }
  .stat .label { color: var(--muted); font-size: 12px; font-weight: 500; }
  .stat .icon { width: 26px; height: 26px; border-radius: 8px; background: var(--accent-soft);
    color: var(--accent); display: flex; align-items: center; justify-content: center; }
  .stat:nth-child(2) .icon { background: var(--violet-soft); color: var(--violet); }
  .stat:nth-child(3) .icon { background: rgba(48,209,88,.12); color: var(--success); }
  .stat .icon svg { width: 15px; height: 15px; }
  .stat .value { font-size: 30px; font-weight: 650; letter-spacing: -.02em; margin: 8px 0 3px;
    font-variant-numeric: tabular-nums; }
  .stat .cost { color: var(--muted); font-size: 12px; font-variant-numeric: tabular-nums; }

  h2.section { font-size: 16px; font-weight: 600; letter-spacing: -.01em; margin: 28px 0 4px; }
  .section-sub { color: var(--muted); font-size: 12px; margin: 0 0 12px; }

  .table-scroll { max-height: 480px; overflow: auto; border: 1px solid var(--hairline);
    border-radius: var(--radius); background: var(--surface); box-shadow: var(--shadow-sm); }
  .table-scroll::-webkit-scrollbar { width: 8px; height: 8px; }
  .table-scroll::-webkit-scrollbar-thumb { background: var(--border); border-radius: 4px; }
  table.data { width: 100%; border-collapse: collapse; font-size: 13px; }
  table.data th, table.data td { padding: 10px 14px; text-align: right;
    border-bottom: 1px solid var(--hairline); font-variant-numeric: tabular-nums; white-space: nowrap; }
  table.data tbody tr:last-child td { border-bottom: none; }
  table.data th { position: sticky; top: 0; z-index: 1; background: var(--thead-bg); color: var(--muted);
    font-weight: 500; font-size: 11px; letter-spacing: .04em; text-transform: uppercase;
    -webkit-backdrop-filter: blur(12px); backdrop-filter: blur(12px); }
  table.data th.l, table.data td.l { text-align: left; }
  table.data tbody tr { transition: background .12s ease; }
  table.data tbody tr:hover { background: var(--surface-2); }
  .model { font-weight: 550; letter-spacing: -.01em; }
  .sub { color: var(--muted); font-size: 11px; display: flex; align-items: center; gap: 6px; margin-top: 2px; }
  .muted { color: var(--muted); }

  .badge { display: inline-flex; align-items: center; gap: 5px; padding: 1px 8px; border-radius: 999px;
    font-size: 11px; font-weight: 500; line-height: 1.6; border: 1px solid transparent; }
  .badge::before { content: ""; width: 5px; height: 5px; border-radius: 50%; background: currentColor; }
  .badge.builtin { color: var(--accent); background: var(--accent-soft); border-color: var(--accent-border); }
  .badge.user { color: var(--violet); background: var(--violet-soft); border-color: var(--violet-border); }
  .badge.none { color: var(--danger); background: var(--danger-soft); border-color: var(--danger-border); }

  tr.editor td { background: var(--surface-2); text-align: left; padding: 0; }
  tr.editor td .editor-box { margin: 4px 12px 12px; background: var(--surface);
    border: 1px solid var(--border); border-radius: 10px; padding: 14px 16px; }
  .editor-grid { display: flex; gap: 12px; flex-wrap: wrap; align-items: flex-end; }
  .field { display: flex; flex-direction: column; gap: 4px; color: var(--muted);
    font-size: 11px; font-weight: 500; }
  .field input { width: 100px; }
  .editor-actions { display: flex; gap: 8px; }
  .editor-hint { margin: 12px 0 0; padding-top: 10px; border-top: 1px dashed var(--border);
    color: var(--muted); font-size: 11px; line-height: 1.6; }

  .two-col { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }
  .foot { text-align: center; color: var(--muted); font-size: 11px; margin: 36px 0 0; line-height: 1.7; }

  @keyframes rise { from { opacity: 0; transform: translateY(8px); } to { opacity: 1; transform: none; } }
  #dashboard .stat, #dashboard .table-scroll { animation: rise .35s ease both; }
  @media (prefers-reduced-motion: reduce) {
    * { animation: none !important; transition: none !important; }
  }
  @media (max-width: 760px) {
    .cards, .two-col { grid-template-columns: 1fr; }
    .topbar { padding: 10px 16px; }
    .wrap { padding: 20px 16px 40px; }
  }
</style>
</head>
<body>
  <div class="topbar">
    <div class="brand">ZF</div>
    <h1>ZFStatMenus 同步面板</h1>
    <div class="spacer"></div>
    <span class="meta" id="conn-user"></span>
    <span class="meta" id="conn-status" style="display:none"><span class="status-dot"></span>已连接</span>
    <button class="btn small" id="reload" style="display:none">刷新</button>
    <button class="btn small" id="logout" style="display:none">退出</button>
  </div>

  <div class="wrap">
    <div id="auth" class="card auth-card">
      <div class="logo">ZF</div>
      <h2>连接到同步服务</h2>
      <p>输入由服务管理员提供的访问 Token（zfsm_ 开头）。<br>Token 仅保存在本浏览器 localStorage，用于调用本服务的数据接口。</p>
      <input type="password" id="token" placeholder="zfsm_…" autocomplete="off">
      <button class="btn primary" id="connect-btn">连接</button>
    </div>

    <div id="dashboard" style="display:none">
      <div class="error" id="error"></div>

      <div class="card controls">
        <label>统计范围
          <select id="range">
            <option value="7">近 7 天</option>
            <option value="30" selected>近 30 天</option>
            <option value="90">近 90 天</option>
            <option value="365">近一年</option>
          </select>
        </label>
        <label>USD/CNY 汇率
          <input type="number" id="rate" step="0.0001" min="0.01" value="7.2" style="width:96px">
        </label>
        <button class="btn small" id="refresh-rate">自动获取汇率</button>
        <span id="rate-status"></span>
      </div>

      <div class="cards" id="summary"></div>

      <h2 class="section">模型用量与定价</h2>
      <p class="section-sub">内置价格与客户端价格目录同步；自定义定价优先于内置价格。</p>
      <div class="table-scroll" id="models"></div>

      <h2 class="section">每日明细</h2>
      <p class="section-sub"></p>
      <div class="table-scroll" id="days"></div>

      <div class="two-col">
        <div>
          <h2 class="section">来源分布</h2>
          <p class="section-sub"></p>
          <div class="table-scroll" id="sources"></div>
        </div>
        <div>
          <h2 class="section">设备</h2>
          <p class="section-sub"></p>
          <div class="table-scroll" id="devices"></div>
        </div>
      </div>

      <p class="foot">费用为公开标准 API 单价的等价估算，不代表订阅产品实际账单。<br>缺少可信公开价格的内部或订阅型号保持「未定价」，不会猜价。</p>
    </div>
  </div>

<script>
var state = { token: '', stats: null, rate: 7.2 };

function esc(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
    return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
  });
}
function fmt(n) {
  n = n || 0;
  if (n >= 1e9) return (n / 1e9).toFixed(1) + 'B';
  if (n >= 1e6) return (n / 1e6).toFixed(1) + 'M';
  if (n >= 1e3) return (n / 1e3).toFixed(1) + 'K';
  return String(Math.round(n));
}
function fmtMoney(v) {
  if (v > 0 && v < 0.01) return v.toFixed(4);
  return v.toFixed(2);
}
function total(r) {
  return (r.inputTokens || 0) + (r.cachedInputTokens || 0) + (r.cacheWriteTokens || 0)
    + (r.outputTokens || 0) + (r.reasoningTokens || 0);
}
function costParts(usdCost, cnyCost) {
  usdCost = usdCost || 0; cnyCost = cnyCost || 0;
  var rate = state.rate || 7.2;
  var usd = usdCost + cnyCost / rate;
  var cny = cnyCost + usdCost * rate;
  if (usd <= 0 && cny <= 0) return '<span class="muted">—</span>';
  return '$' + fmtMoney(usd) + ' · ¥' + fmtMoney(cny);
}
function showError(msg) {
  var el = document.getElementById('error');
  el.textContent = msg || '';
  el.style.display = msg ? 'block' : 'none';
}
function api(method, path, body) {
  var opts = { method: method, headers: { 'Authorization': 'Bearer ' + state.token } };
  if (body !== undefined) {
    opts.headers['Content-Type'] = 'application/json';
    opts.body = JSON.stringify(body);
  }
  return fetch(path, opts).then(function (r) {
    return r.json().then(function (data) {
      if (!r.ok) throw new Error((data && data.error && data.error.message) || ('HTTP ' + r.status));
      return data;
    });
  });
}

function connect() {
  var token = document.getElementById('token').value.trim();
  if (!token) { showError('请输入访问 Token'); return; }
  state.token = token;
  api('GET', '/v1/me').then(function (me) {
    localStorage.setItem('zfsm_token', token);
    document.getElementById('auth').style.display = 'none';
    document.getElementById('dashboard').style.display = 'block';
    document.getElementById('reload').style.display = 'inline-block';
    document.getElementById('logout').style.display = 'inline-block';
    document.getElementById('conn-user').textContent = me.user.displayName;
    document.getElementById('conn-status').style.display = 'flex';
    showError('');
    return loadData();
  }).catch(function (e) {
    state.token = '';
    showError('连接失败：' + e.message);
    var auth = document.getElementById('auth');
    if (auth.style.display === 'none') { location.reload(); }
  });
}

function loadData() {
  var days = document.getElementById('range').value;
  return api('GET', '/v1/stats?days=' + days).then(function (stats) {
    state.stats = stats;
    render();
  }).catch(function (e) { showError(e.message); });
}

function render() {
  if (!state.stats) return;
  renderSummary();
  renderModels();
  renderDays();
  renderSources();
  renderDevices();
}

function shiftDay(dateStr, delta) {
  var d = new Date(dateStr + 'T00:00:00Z');
  d.setUTCDate(d.getUTCDate() + delta);
  return d.toISOString().slice(0, 10);
}
function sumRange(ref, n) {
  var from = shiftDay(ref, -(n - 1));
  var t = { tokens: 0, usd: 0, cny: 0 };
  (state.stats.days || []).forEach(function (d) {
    if (d.day >= from && d.day <= ref) {
      t.tokens += total(d);
      t.usd += d.usdCost || 0;
      t.cny += d.cnyCost || 0;
    }
  });
  return t;
}
var ICONS = {
  today: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>',
  week: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M6 20v-7M12 20V5M18 20v-11"/></svg>',
  month: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="3" y="5" width="18" height="16" rx="3"/><path d="M8 3v4M16 3v4M3 10.5h18"/></svg>'
};
function statCard(title, s, icon) {
  return '<div class="stat"><div class="head"><div class="label">' + title + '</div>'
    + '<div class="icon">' + icon + '</div></div>'
    + '<div class="value">' + fmt(s.tokens) + '</div>'
    + '<div class="cost">' + costParts(s.usd, s.cny) + '</div></div>';
}
function renderSummary() {
  var ref = state.stats.to;
  var html = statCard('今日 · Token', sumRange(ref, 1), ICONS.today)
    + statCard('近 7 天 · Token', sumRange(ref, 7), ICONS.week)
    + statCard('近 30 天 · Token', sumRange(ref, 30), ICONS.month);
  document.getElementById('summary').innerHTML = html;
}

function priceBadge(m) {
  if (m.priceSource === 'user') return '<span class="badge user">自定义</span>';
  if (m.priceSource === 'builtin') return '<span class="badge builtin">内置</span>';
  return '<span class="badge none">未定价</span>';
}
function priceField(label, id, val) {
  return '<label class="field">' + label
    + '<input id="' + id + '" type="number" step="any" min="0" value="' + (val == null ? '' : val) + '" placeholder="0"></label>';
}
function editorHint(m) {
  if (m.priceSource === 'user') return '自定义定价生效中，优先于内置价格。删除后回退为内置价格（若存在）或「未定价」。';
  if (m.priceSource === 'builtin') return '当前使用内置默认定价（与客户端价格目录同步）。保存后将作为你的自定义定价覆盖它。';
  return '该模型暂无定价：内部或订阅型号不猜价。保存后开始按所填价格估算费用。';
}
function editorRow(i, m) {
  var p = m.price || { currency: 'usd', inputPerMtok: '', cachedInputPerMtok: '', cacheWritePerMtok: '', outputPerMtok: '' };
  var isUser = m.priceSource === 'user';
  return '<tr class="editor" id="editor-' + i + '" style="display:none"><td colspan="7"><div class="editor-box"><div class="editor-grid">'
    + priceField('输入 /M', 'pi-' + i, p.inputPerMtok)
    + priceField('缓存读取 /M', 'pc-' + i, p.cachedInputPerMtok)
    + priceField('缓存写入 /M', 'pw-' + i, p.cacheWritePerMtok)
    + priceField('输出推理 /M', 'po-' + i, p.outputPerMtok)
    + '<label class="field">币种<select id="cur-' + i + '">'
    + '<option value="usd"' + (p.currency === 'usd' ? ' selected' : '') + '>USD</option>'
    + '<option value="cny"' + (p.currency === 'cny' ? ' selected' : '') + '>CNY</option></select></label>'
    + '<div class="editor-actions">'
    + '<button class="btn primary small" onclick="savePrice(' + i + ')">保存</button>'
    + (isUser ? '<button class="btn danger small" onclick="deletePrice(' + i + ')">删除定价</button>' : '')
    + '</div></div><p class="editor-hint">' + editorHint(m) + '</p></div></td></tr>';
}
function renderModels() {
  var models = state.stats.models || [];
  var html = '<table class="data"><thead><tr>'
    + '<th class="l">模型</th><th>Token</th><th>输入</th><th>缓存</th><th>输出</th><th>费用</th><th></th>'
    + '</tr></thead><tbody>';
  if (models.length === 0) {
    html += '<tr><td class="l muted" colspan="7">该范围内暂无用量</td></tr>';
  }
  for (var i = 0; i < models.length; i++) {
    var m = models[i];
    html += '<tr>'
      + '<td class="l"><div class="model">' + esc(m.model) + '</div>'
      + '<div class="sub">' + esc(m.provider) + ' ' + priceBadge(m) + '</div></td>'
      + '<td>' + fmt(total(m)) + '</td>'
      + '<td>' + fmt(m.inputTokens) + '</td>'
      + '<td>' + fmt(m.cachedInputTokens) + '</td>'
      + '<td>' + fmt((m.outputTokens || 0) + (m.reasoningTokens || 0)) + '</td>'
      + '<td>' + costParts(m.usdCost, m.cnyCost) + '</td>'
      + '<td><button class="btn small" onclick="toggleEditor(' + i + ')">定价</button></td>'
      + '</tr>';
    html += editorRow(i, m);
  }
  html += '</tbody></table>';
  document.getElementById('models').innerHTML = html;
}
function renderDays() {
  var days = (state.stats.days || []).slice().reverse();
  var html = '<table class="data"><thead><tr>'
    + '<th class="l">日期</th><th>Token</th><th>输入</th><th>缓存</th><th>输出</th><th>费用</th>'
    + '</tr></thead><tbody>';
  if (days.length === 0) html += '<tr><td class="l muted" colspan="6">暂无数据</td></tr>';
  days.forEach(function (d) {
    html += '<tr><td class="l">' + esc(d.day) + '</td><td>' + fmt(total(d)) + '</td>'
      + '<td>' + fmt(d.inputTokens) + '</td><td>' + fmt(d.cachedInputTokens) + '</td>'
      + '<td>' + fmt((d.outputTokens || 0) + (d.reasoningTokens || 0)) + '</td>'
      + '<td>' + costParts(d.usdCost, d.cnyCost) + '</td></tr>';
  });
  html += '</tbody></table>';
  document.getElementById('days').innerHTML = html;
}
function renderSources() {
  var rows = state.stats.sources || [];
  var html = '<table class="data"><thead><tr><th class="l">来源</th><th>Token</th><th>费用</th></tr></thead><tbody>';
  if (rows.length === 0) html += '<tr><td class="l muted" colspan="3">暂无数据</td></tr>';
  rows.forEach(function (s) {
    html += '<tr><td class="l">' + esc(s.source) + '</td><td>' + fmt(total(s)) + '</td>'
      + '<td>' + costParts(s.usdCost, s.cnyCost) + '</td></tr>';
  });
  html += '</tbody></table>';
  document.getElementById('sources').innerHTML = html;
}
function renderDevices() {
  var rows = state.stats.devices || [];
  var html = '<table class="data"><thead><tr><th class="l">设备</th><th>Token</th><th>费用</th></tr></thead><tbody>';
  if (rows.length === 0) html += '<tr><td class="l muted" colspan="3">暂无数据</td></tr>';
  rows.forEach(function (d) {
    html += '<tr><td class="l">' + esc(d.deviceName) + '</td><td>' + fmt(total(d)) + '</td>'
      + '<td>' + costParts(d.usdCost, d.cnyCost) + '</td></tr>';
  });
  html += '</tbody></table>';
  document.getElementById('devices').innerHTML = html;
}

function toggleEditor(i) {
  var el = document.getElementById('editor-' + i);
  el.style.display = el.style.display === 'none' ? 'table-row' : 'none';
}
function numVal(id) {
  var v = parseFloat(document.getElementById(id).value);
  return isNaN(v) || v < 0 ? 0 : v;
}
function savePrice(i) {
  var m = state.stats.models[i];
  var body = {
    provider: m.provider, model: m.model,
    currency: document.getElementById('cur-' + i).value,
    inputPerMtok: numVal('pi-' + i), cachedInputPerMtok: numVal('pc-' + i),
    cacheWritePerMtok: numVal('pw-' + i), outputPerMtok: numVal('po-' + i)
  };
  api('PUT', '/v1/pricing', body).then(function () { return loadData(); })
    .catch(function (e) { showError(e.message); });
}
function deletePrice(i) {
  var m = state.stats.models[i];
  api('DELETE', '/v1/pricing?provider=' + encodeURIComponent(m.provider) + '&model=' + encodeURIComponent(m.model))
    .then(function () { return loadData(); })
    .catch(function (e) { showError(e.message); });
}

function fetchRate() {
  var status = document.getElementById('rate-status');
  status.className = '';
  status.textContent = '获取中…';
  fetch('https://open.er-api.com/v6/latest/USD').then(function (r) { return r.json(); })
    .then(function (d) {
      if (d && d.result === 'success' && d.rates && d.rates.CNY) {
        state.rate = d.rates.CNY;
        localStorage.setItem('zfsm_rate', String(d.rates.CNY));
        document.getElementById('rate').value = d.rates.CNY.toFixed(4);
        status.className = 'ok';
        status.textContent = '已自动获取';
        render();
      } else {
        status.textContent = '获取失败，使用手动值';
      }
    }).catch(function () {
      status.textContent = '获取失败，使用手动值';
    });
}
function onRateChange() {
  var v = parseFloat(document.getElementById('rate').value);
  if (v > 0) {
    state.rate = v;
    localStorage.setItem('zfsm_rate', String(v));
    render();
  }
}

function init() {
  document.getElementById('connect-btn').addEventListener('click', connect);
  document.getElementById('token').addEventListener('keydown', function (e) { if (e.key === 'Enter') connect(); });
  document.getElementById('range').addEventListener('change', function () { loadData(); });
  document.getElementById('rate').addEventListener('change', onRateChange);
  document.getElementById('refresh-rate').addEventListener('click', fetchRate);
  document.getElementById('reload').addEventListener('click', function () { loadData(); });
  document.getElementById('logout').addEventListener('click', function () {
    localStorage.removeItem('zfsm_token');
    location.reload();
  });
  var savedRate = parseFloat(localStorage.getItem('zfsm_rate') || '');
  if (savedRate > 0) {
    state.rate = savedRate;
    document.getElementById('rate').value = String(savedRate);
  }
  fetchRate();
  var saved = localStorage.getItem('zfsm_token');
  if (saved) {
    document.getElementById('token').value = saved;
    connect();
  }
}
document.addEventListener('DOMContentLoaded', init);
</script>
</body>
</html>`;
