/* ============================================================
 * [自备] —— 设置桥接 + 设备能力自动探测 + 改编码后自动刷新（隔离世界）
 *
 * 三个职责：
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
 *
 *   3) 编码变了就自动刷新本页
 *      播放器是在页面加载那一刻调用 isTypeSupported() 把编码定死的，
 *      之后改设置对"已经加载完的页面"没用，必须重载一次让它重新选。
 *      这里用 sessionStorage 记住"本页是按哪种编码加载的"，
 *      只有真的变了才刷，刷完记录就一致了 → 不会循环。
 * ============================================================ */
(function () {
  'use strict';

  var DEFAULTS = {
    codecMode: 'auto',     // auto | avc | hevc | av1
    rafLimit: true,
    scrollLimit: true,
    autoReload: true       // 改编码后自动刷新页面
  };

  // 探测结果的有效期。硬件不会变，但浏览器升级可能新增支持，定期重测。
  var PROBE_TTL = 7 * 24 * 3600 * 1000;

  var VALID_MODES = ['auto', 'avc', 'hevc', 'av1'];

  // ── 自动刷新的防循环措施 ──────────────────────────────────
  //
  // 用 sessionStorage 而不是 localStorage：sessionStorage 是"每个标签页
  // 一份、且跨重载保留"，正好符合"这一页是按哪种编码加载的"这个语义，
  // 关掉标签页就自动清掉，不会污染以后。
  var MARK  = 'zibeiCodecApplied';   // 本页加载时实际生效的编码
  var COUNT = 'zibeiReloadCount';    // 本页已自动刷新的次数（安全阀）
  var MAX_RELOAD = 3;

  // 只对看起来真的在放视频的页面自动刷新，避免把正在填的表单刷掉。
  var VIDEO_SITES = /(^|\.)(bilibili\.com|b23\.tv|youtube\.com|youtu\.be|netflix\.com|iqiyi\.com|v\.qq\.com|youku\.com|mgtv\.com|douyin\.com|twitch\.tv|vimeo\.com)$/i;

  function ss(fn, dflt) {
    try { return fn(); } catch (e) { return dflt; }
  }

  // 当前设置下，这一页应该用哪种编码
  function effectiveCodec(mode, autoCodec) {
    if (mode === 'auto') return autoCodec || 'avc';
    return mode;
  }

  function isVideoish() {
    try {
      if (document.querySelector('video,audio')) return true;
    } catch (e) { /* 忽略 */ }
    try {
      return VIDEO_SITES.test(location.hostname || '');
    } catch (e) { return false; }
  }

  // ── 站点适配 ────────────────────────────────────────────
  //
  // 有些网站自己有编码偏好开关，光拦 isTypeSupported 不管用：
  // 它们先读自己的偏好决定"想要哪个"，能力判断只管"能不能放"。
  //
  // B站 就是典型。它的播放器按 DEF_CODEC_STRATEGY = [AV1, HEVC, AVC]
  // 的顺序挑 —— 默认就要 AV1。偏好存在 localStorage 里（也就是它设置里
  // 「优先 AVC」那个开关）。所以必须直接改它的偏好，而不是只堵 API。
  //
  // 键的语义是从 B站 播放器 core.js 里挖出来的：
  //   localStorage  bilibili_player_codec_prefer_strategy
  //       0 = RECOMMEND（默认，顺序 AV1 → HEVC → AVC）
  //       1 = 优先 HEVC
  //       2 = DISABLE（优先 AVC）   ← 它自己的「优先 AVC」就写这个
  //       3 = 优先 AV1
  //   sessionStorage enableAV1Error  = '1' → 关闭 AV1
  //   sessionStorage enableHEVCError = '1' → 关闭 HEVC
  //
  // 必须在播放器启动前写好，否则这一页不生效 —— 所以放在 document_start
  // 阶段。B站 播放器版本更新时还会自己重置这个偏好，因此每次加载都写一遍。
  var SITE_ADAPTERS = [
    {
      match: /(^|\.)bilibili\.com$/i,
      strategyKey: 'bilibili_player_codec_prefer_strategy',
      av1ErrorKey: 'enableAV1Error',
      hevcErrorKey: 'enableHEVCError',
      strategyValue: { avc: '2', hevc: '1', av1: '3' }
    }
  ];

  function setSessionFlag(key, off) {
    if (!key) return;
    try {
      if (off) {
        if (sessionStorage.getItem(key) !== '1') sessionStorage.setItem(key, '1');
      } else if (sessionStorage.getItem(key) !== null) {
        sessionStorage.removeItem(key);
      }
    } catch (e) { /* 忽略 */ }
  }

  function applySiteAdapter(eff) {
    if (!eff) return;
    var host;
    try { host = location.hostname || ''; } catch (e) { return; }

    for (var i = 0; i < SITE_ADAPTERS.length; i++) {
      var a = SITE_ADAPTERS[i];
      if (!a.match.test(host)) continue;

      // 1) 站点自己的编码偏好
      var v = a.strategyValue[eff];
      if (v) {
        try {
          if (localStorage.getItem(a.strategyKey) !== v) {
            localStorage.setItem(a.strategyKey, v);
          }
        } catch (e) { /* 无痕模式等，忽略 */ }
      }

      // 2) 关掉本站对"我们不允许的编码"的开关
      //    avc  → AV1、HEVC 都关
      //    hevc → 只关 AV1
      //    av1  → 只关 HEVC
      setSessionFlag(a.av1ErrorKey,  eff === 'avc' || eff === 'hevc');
      setSessionFlag(a.hevcErrorKey, eff === 'avc' || eff === 'av1');
      return;
    }
  }

  function maybeReload(eff) {
    if (!eff) return;
    // 只在顶层文档动手 —— content script 跑在所有 iframe 里，
    // 刷错地方会把页面刷坏
    if (window.top !== window.self) return;

    var prev = ss(function () { return sessionStorage.getItem(MARK); }, null);

    if (prev === eff) return;                       // 本页就是按这个编码加载的 → 不用刷
    ss(function () { sessionStorage.setItem(MARK, eff); });
    if (prev === null) return;                      // 本页第一次记录 → 它本来就是按这个加载的

    // 走到这里说明：本页加载时的编码 ≠ 现在应有的编码 → 需要刷新一次
    var n = parseInt(ss(function () { return sessionStorage.getItem(COUNT); }, '0') || '0', 10) || 0;
    if (n >= MAX_RELOAD) return;                    // 安全阀：万一判断有误也不会刷个不停
    ss(function () { sessionStorage.setItem(COUNT, String(n + 1)); });

    if (!isVideoish()) return;                      // 不是在放视频的页面就别打扰

    // 等一下让 storage 落盘，再刷
    setTimeout(function () {
      ss(function () { location.reload(); });
    }, 150);
  }

  function apply(cfg, autoCodec, allowReload) {
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

    if (allowReload) {
      // 真正拿到设置之后，先把站点自己的偏好改掉 —— 这一步必须早于
      // 播放器初始化，否则这一页不生效。
      applySiteAdapter(effectiveCodec(mode, autoCodec));
      if (cfg.autoReload !== false) maybeReload(effectiveCodec(mode, autoCodec));
      else ss(function () { sessionStorage.setItem(MARK, effectiveCodec(mode, autoCodec)); });
    }
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
    // 先写一份默认值，保证 inject.js 任何时刻读到的都有效。
    // 注意这里 allowReload = false —— 这一份只是占位，真正的设置是
    // 下面异步读出来的，不能让占位值参与"要不要刷新"的判断，
    // 否则每开一个新标签页都会白刷一次。
    apply(DEFAULTS, null, false);

    var api;
    try { api = chrome.storage.local; } catch (e) { return; }
    if (!api) return;

    api.get({
      codecMode:   DEFAULTS.codecMode,
      rafLimit:    DEFAULTS.rafLimit,
      scrollLimit: DEFAULTS.scrollLimit,
      autoReload:  DEFAULTS.autoReload,
      autoCodec:   null,
      autoAt:      0
    }, function (v) {
      try { if (chrome.runtime.lastError) return; } catch (e) { /* 忽略 */ }

      apply(v, v.autoCodec, true);

      // 没有探测结果、或已过期 —— 后台重测一次。
      // 测完如果结果和本页现在用的不一样，会触发一次自动刷新。
      var stale = !v.autoCodec || (Date.now() - (v.autoAt || 0)) > PROBE_TTL;
      if (stale && window.__zibeiProbe) {
        window.__zibeiProbe.probe().then(function (r) {
          saveProbe(r);
          apply(v, r.best, true);
        })['catch'](function () { /* 忽略 */ });
      }
    });
  }

  load();

  // 设置小窗里改完，已打开的页面立即跟着变；编码变了会自动刷新本页。
  try {
    if (chrome && chrome.storage && chrome.storage.onChanged) {
      chrome.storage.onChanged.addListener(function (changes, area) {
        if (area === 'local' || area === 'sync') load();
      });
    }
  } catch (e) { /* 忽略 */ }

  // 暴露给控制台排查用：__zibeiBridge.state()
  try {
    window.__zibeiBridge = {
      get mark() { return ss(function () { return sessionStorage.getItem(MARK); }, null); },
      get reloads() { return parseInt(ss(function () { return sessionStorage.getItem(COUNT); }, '0') || '0', 10) || 0; },
      get videoish() { return isVideoish(); },
      get isTop() { return window.top === window.self; }
    };
  } catch (e) { /* 忽略 */ }
})();
