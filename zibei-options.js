/* ============================================================
 * [自备] —— 设置页逻辑
 * ============================================================ */
(function () {
  'use strict';

  var DEFAULTS = {
    codecMode: 'avc',
    rafLimit: true,
    scrollLimit: true
  };

  var $ = function (id) { return document.getElementById(id); };
  var savedTimer = null;

  function toast(text, color) {
    var el = $('saved');
    el.textContent = text;
    el.style.background = color || '#30d158';
    el.style.color = color ? '#fff' : '#00230a';
    el.classList.add('show');
    clearTimeout(savedTimer);
    savedTimer = setTimeout(function () { el.classList.remove('show'); }, 1400);
  }

  // ── 读取当前设置并填进界面 ──────────────────────────────
  function load() {
    chrome.storage.sync.get(DEFAULTS, function (v) {
      if (chrome.runtime.lastError) {
        chrome.storage.local.get(DEFAULTS, fill);
        return;
      }
      fill(v);
    });
  }

  function fill(v) {
    var radios = document.querySelectorAll('input[name="codecMode"]');
    for (var i = 0; i < radios.length; i++) {
      radios[i].checked = (radios[i].value === v.codecMode);
    }
    // 万一存的模式不合法，兜底选 avc
    var any = false;
    for (var j = 0; j < radios.length; j++) if (radios[j].checked) any = true;
    if (!any) for (var k = 0; k < radios.length; k++) {
      if (radios[k].value === 'avc') radios[k].checked = true;
    }
    $('rafLimit').checked    = v.rafLimit !== false;
    $('scrollLimit').checked = v.scrollLimit !== false;
  }

  // ── 保存 ────────────────────────────────────────────────
  function save(patch, silent) {
    var api = (chrome.storage.sync || chrome.storage.local);
    api.set(patch, function () {
      if (!silent) toast('已保存');
      // 编码项改完必须刷新页面才生效 —— 播放器在页面加载时就把编码定死了
      if ('codecMode' in patch) {
        toast('已保存 · 编码项需刷新页面才生效', '#ff9f0a');
      }
    });
  }

  // ── 界面事件 ────────────────────────────────────────────
  document.addEventListener('change', function (e) {
    var t = e.target;
    if (!t) return;
    if (t.name === 'codecMode') save({ codecMode: t.value });
    else if (t.id === 'rafLimit')    save({ rafLimit: t.checked });
    else if (t.id === 'scrollLimit') save({ scrollLimit: t.checked });
  });

  // ── 解码能力检测 ────────────────────────────────────────
  //
  // 注意：这里是**原生**能力检测 —— 内容脚本不会在 chrome-extension://
  // 页面上运行，所以本页没有装任何拦截钩子，测出来的是浏览器真实能力。
  //
  // 用 mediaCapabilities.decodingInfo 而不是 isTypeSupported，因为只有它
  // 会告诉我们 powerEfficient —— 也就是「是否真的走硬件解码」。
  // isTypeSupported 对软解也返回 true，分不出来。
  var CODECS = [
    { name: 'H.264 / AVC',  mime: 'video/mp4; codecs="avc1.640028"' },
    { name: 'HEVC / H.265', mime: 'video/mp4; codecs="hev1.1.6.L120.B0"' },
    { name: 'AV1',          mime: 'video/mp4; codecs="av01.0.05M.08"' },
    { name: 'VP9',          mime: 'video/webm; codecs="vp09.00.51.08"' },
    { name: 'VP8',          mime: 'video/webm; codecs="vp8"' },
    { name: 'Dolby Vision', mime: 'video/mp4; codecs="dvh1.05.06"' }
  ];

  var PROBE = { width: 1920, height: 1080, bitrate: 10326000, framerate: 60 };

  function probeOne(c) {
    var supported = false;
    try {
      supported = !!(window.MediaSource && MediaSource.isTypeSupported(c.mime));
    } catch (e) { /* 忽略 */ }

    var p;
    if (navigator.mediaCapabilities && navigator.mediaCapabilities.decodingInfo) {
      p = navigator.mediaCapabilities.decodingInfo({
        type: 'file',
        video: {
          contentType: c.mime,
          width: PROBE.width,
          height: PROBE.height,
          bitrate: PROBE.bitrate,
          framerate: PROBE.framerate
        }
      }).then(function (r) {
        return {
          name: c.name, mime: c.mime,
          supported: r.supported, smooth: r.smooth, efficient: r.powerEfficient
        };
      });
    } else {
      p = Promise.resolve({
        name: c.name, mime: c.mime,
        supported: supported, smooth: null, efficient: null
      });
    }
    return p.catch(function () {
      return { name: c.name, mime: c.mime, supported: supported, smooth: null, efficient: null };
    });
  }

  function renderProbe(rows) {
    var html = '<table><tr><th>格式</th><th>支持</th><th>流畅 1080p60</th>' +
               '<th>解码方式</th></tr>';
    rows.forEach(function (r) {
      var sup = r.supported
        ? '<span class="tag ok">✅ 支持</span>'
        : '<span class="tag bad">❌ 不支持</span>';
      var smooth = (r.smooth === null)
        ? '<span class="dim">—</span>'
        : (r.smooth ? '<span class="ok">✅ 是</span>' : '<span class="warn">⚠ 勉强</span>');
      var how;
      if (!r.supported)               how = '<span class="dim">—</span>';
      else if (r.efficient === true)  how = '<span class="tag ok">⚡ 硬解</span>';
      else if (r.efficient === false) how = '<span class="tag warn">🐌 软解（吃 CPU）</span>';
      else                            how = '<span class="dim">未知</span>';
      html += '<tr><td><b>' + r.name + '</b><div class="dim" style="font-size:11px">' +
              r.mime.replace(/</g, '&lt;') + '</div></td>' +
              '<td>' + sup + '</td><td>' + smooth + '</td><td>' + how + '</td></tr>';
    });
    html += '</table>';
    html += '<div class="note">只有「⚡ 硬解」的格式才适合你这台机器。' +
            '把它对应的那一项选上（例如 H.264 是硬解，就选「优先 AVC」）。</div>';
    $('probeOut').innerHTML = html;
  }

  $('probe').addEventListener('click', function () {
    var btn = this;
    btn.disabled = true;
    btn.textContent = '检测中…';
    $('probeOut').innerHTML = '<div class="hint" style="margin-top:14px">正在逐个探测…</div>';
    Promise.all(CODECS.map(probeOne)).then(function (rows) {
      renderProbe(rows);
      btn.disabled = false;
      btn.textContent = '重新检测';
    });
  });

  load();
})();
