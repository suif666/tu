/* ============================================================
 * [自备] —— 设置小窗逻辑（点工具栏图标弹出）
 * ============================================================ */
(function () {
  'use strict';

  var DEFAULTS = { codecMode: 'auto', rafLimit: true, scrollLimit: true, autoReload: true };

  var AUTO_NAMES = {
    av1:  'AV1',
    hevc: 'HEVC',
    avc:  'H.264',
    vp9:  'VP9'
  };

  var $ = function (id) { return document.getElementById(id); };
  var toastTimer = null;

  function toast(text, warn) {
    var el = $('saved');
    el.textContent = text || '\u00a0';
    el.className = 'show' + (warn ? ' warn' : '');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { el.className = ''; }, 1800);
  }

  // ── 界面填充 ────────────────────────────────────────────
  function fill(v) {
    var rs = document.querySelectorAll('input[name="codecMode"]');
    var hit = false;
    for (var i = 0; i < rs.length; i++) {
      rs[i].checked = (rs[i].value === v.codecMode);
      if (rs[i].checked) hit = true;
    }
    if (!hit && rs.length) rs[0].checked = true;
    $('rafLimit').checked    = v.rafLimit !== false;
    $('scrollLimit').checked = v.scrollLimit !== false;
    $('autoReload').checked  = v.autoReload !== false;
  }

  // 在「自动」那一行右侧显示它挑中的编码 + 硬解/软解
  function renderAutoBadge(codec, efficient) {
    var b = $('badgeAuto');
    if (!codec) { b.style.display = 'none'; return; }
    b.style.display = '';
    b.textContent = AUTO_NAMES[codec] || codec;
    b.className = 'badge ' + (efficient ? 'hw' : 'sw');
    b.title = efficient ? '本机对该编码有硬件解码' : '本机只能软件解码该编码';
  }

  // 把探测结果渲染成表格
  function renderTable(report) {
    if (!window.__zibeiProbe) return;
    var list = window.__zibeiProbe.CANDIDATES;
    var html = '';
    for (var i = 0; i < list.length; i++) {
      var c = list[i];
      var r = report && report[c.key];
      var right;
      if (!r) {
        right = '<span style="color:var(--dim)">未检测</span>';
      } else if (!r.supported) {
        right = '<span class="bad">不支持</span>';
      } else if (r.efficient) {
        right = '<span class="ok">⚡ 硬解</span>';
      } else {
        right = '<span class="warn">🐌 软解</span>';
      }
      html += '<tr><td>' + c.name + '</td><td class="r">' + right + '</td></tr>';
    }
    $('probeTable').innerHTML = html;
  }

  function renderSub(v) {
    var sub = $('sub');
    if (v.codecMode === 'auto' && v.autoCodec) {
      sub.textContent = '自动模式：已挑定 ' + (AUTO_NAMES[v.autoCodec] || v.autoCodec) +
        (v.autoEfficient ? '（本机硬解）' : '（本机软解）');
    } else if (v.autoAt) {
      var days = Math.floor((Date.now() - v.autoAt) / 86400000);
      sub.textContent = '上次检测：' + (days <= 0 ? '今天' : days + ' 天前');
    } else {
      sub.textContent = '尚未检测本机解码能力';
    }
  }

  // ── 读取 ────────────────────────────────────────────────
  function load() {
    chrome.storage.local.get({
      codecMode:   DEFAULTS.codecMode,
      rafLimit:    DEFAULTS.rafLimit,
      scrollLimit: DEFAULTS.scrollLimit,
      autoReload:  DEFAULTS.autoReload,
      autoCodec:   null,
      autoEfficient: null,
      autoReport:  null,
      autoAt:      0
    }, function (v) {
      if (chrome.runtime.lastError) { renderTable(null); return; }
      fill(v);
      renderAutoBadge(v.autoCodec, v.autoEfficient);
      renderTable(v.autoReport);
      renderSub(v);
      // 从没检测过就立刻测一次
      if (!v.autoAt) runProbe();
    });
  }

  // ── 保存 ────────────────────────────────────────────────
  function save(patch) {
    chrome.storage.local.set(patch, function () {
      toast('已保存' + ('codecMode' in patch ? ' · 正在刷新网页…' : ''),
            'codecMode' in patch);
      if ('codecMode' in patch) {
        // 刷新一下副标题
        chrome.storage.local.get(null, function (v) { renderSub(v); });
      }
    });
  }

  document.addEventListener('change', function (e) {
    var t = e.target;
    if (!t) return;
    if (t.name === 'codecMode')      save({ codecMode: t.value });
    else if (t.id === 'rafLimit')    save({ rafLimit: t.checked });
    else if (t.id === 'scrollLimit') save({ scrollLimit: t.checked });
    else if (t.id === 'autoReload')  save({ autoReload: t.checked });
  });

  // ── 探测 ────────────────────────────────────────────────
  function runProbe() {
    if (!window.__zibeiProbe) { renderTable(null); return; }
    var btn = $('probe');
    btn.disabled = true;
    btn.textContent = '检测中…';
    window.__zibeiProbe.probe().then(function (r) {
      var best = r.report[r.best] || {};
      chrome.storage.local.set({
        autoCodec: r.best,
        autoEfficient: best.efficient === true,
        autoReport: r.report,
        autoAt: r.at
      }, function () {
        renderAutoBadge(r.best, best.efficient === true);
        renderTable(r.report);
        chrome.storage.local.get(null, function (v) { renderSub(v); });
        btn.disabled = false;
        btn.textContent = '重新检测';
        toast('检测完成：' + (AUTO_NAMES[r.best] || r.best) +
              (best.efficient ? '（硬解）' : '（软解）'), !best.efficient);
      });
    })['catch'](function () {
      btn.disabled = false;
      btn.textContent = '重新检测';
      toast('检测失败', true);
    });
  }

  $('probe').addEventListener('click', runProbe);

  load();
})();
