/* ============================================================
 * [自备] —— 设置桥接 + 设备能力自动探测（隔离世界）
 *
 * 两个职责：
 *
 *   1) 把设置从 chrome.storage 搬到 DOM 上
 *      inject.js 必须跑在网页的 MAIN world（否则覆写不到网页自己的
 *      MediaSource），而 MAIN world 读不到 chrome.storage。
 *      于是这里把设置写成 <html> 的 data-* 属性 —— 两个世界共享 DOM。
 *      钩子是「注册时就位、调用时才读设置」，所以 storage 那 1ms 的
 *      异步延迟完全不影响：播放器初始化远在那之后。
 *
 *   2) 探测本机解码能力，算出「自动」模式该用哪种编码
 *      用 probe.js 里的 mediaCapabilities 探测。跑在隔离世界，读到的
 *      是浏览器原生能力，不受我们自己拦截的影响。
 *      结果存进 storage 并写成 data-zibei-auto 属性，于是 inject.js 的
 *      「自动」模式就知道该放行谁、该屏蔽谁。
 * ============================================================ */
(function () {
  'use strict';

  var DEFAULTS = {
    codecMode: 'auto',     // auto | avc | hevc | av1
    rafLimit: true,
    scrollLimit: true
  };

  // 探测结果的有效期。硬件不会变，但浏览器升级可能新增支持，定期重测。
  var PROBE_TTL = 7 * 24 * 3600 * 1000;

  var VALID_MODES = ['auto', 'avc', 'hevc', 'av1'];

  function apply(cfg, autoCodec) {
    var el = document.documentElement;
    if (!el || !el.setAttribute) return;
    cfg = cfg || {};
    try {
      var mode = cfg.codecMode;
      if (VALID_MODES.indexOf(mode) < 0) mode = DEFAULTS.codecMode;
      el.setAttribute('data-zibei-codec', mode);
      el.setAttribute('data-zibei-raf', cfg.rafLimit === false ? '0' : '1');
      el.setAttribute('data-zibei-scroll', cfg.scrollLimit === false ? '0' : '1');
      if (autoCodec) el.setAttribute('data-zibei-auto', autoCodec);
    } catch (e) { /* 忽略 */ }
  }

  function saveProbe(r) {
    try {
      var best = r.report[r.best] || {};
      chrome.storage.local.set({
        autoCodec: r.best,
        autoEfficient: best.efficient === true,   // 是否硬解（设置小窗里显示用）
        autoReport: r.report,                     // 完整结果，供设置小窗渲染表格
        // 存一份人能看懂的摘要，方便排查
        autoSummary: r.list.map(function (x) {
          return x.name + '=' + (x.supported ? '支持' : '不支持') +
                 '/' + (x.efficient ? '硬解' : '软解');
        }).join('  '),
        autoAt: r.at
      });
    } catch (e) { /* 忽略 */ }
  }

  function load() {
    // 先写一份默认值，保证 inject.js 任何时刻读到的都有效
    apply(DEFAULTS, null);

    var api;
    try { api = chrome.storage.local; } catch (e) { return; }
    if (!api) return;

    api.get({
      codecMode: DEFAULTS.codecMode,
      rafLimit: DEFAULTS.rafLimit,
      scrollLimit: DEFAULTS.scrollLimit,
      autoCodec: null,
      autoAt: 0
    }, function (v) {
      try { if (chrome.runtime.lastError) return; } catch (e) { /* 忽略 */ }

      apply(v, v.autoCodec);

      // 没有探测结果、或已过期 —— 后台重测一次。
      // 本次页面继续用旧值（或 inject.js 的保守兜底），下次加载就是新的。
      var stale = !v.autoCodec || (Date.now() - (v.autoAt || 0)) > PROBE_TTL;
      if (stale && window.__zibeiProbe) {
        window.__zibeiProbe.probe().then(function (r) {
          saveProbe(r);
          apply(v, r.best);
        })['catch'](function () { /* 忽略 */ });
      }
    });
  }

  load();

  // 用户在设置小窗里改完，已打开的页面立即生效。
  // （编码那一项例外：播放器在页面加载时就把编码定死了，改完要刷新。）
  try {
    if (chrome && chrome.storage && chrome.storage.onChanged) {
      chrome.storage.onChanged.addListener(function (changes, area) {
        if (area === 'local' || area === 'sync') load();
      });
    }
  } catch (e) { /* 忽略 */ }
})();
