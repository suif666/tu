/* ============================================================
 * [自备] —— 设置桥接（隔离世界）
 *
 * 为什么需要这个文件：
 *
 *   inject.js 必须跑在网页的 MAIN world 里，否则拦不住播放器
 *   （它要覆写网页自己的 MediaSource 和 HTMLMediaElement）。
 *   但 MAIN world 里**读不到扩展的存储 API**（chrome.storage），
 *   而设置又必须在播放器初始化之前就位。
 *
 * 解决办法：
 *   这个文件跑在隔离世界（能读 chrome.storage），把设置写成
 *   <html> 上的 data-* 属性。两个世界共享同一个 DOM，于是
 *   inject.js 的钩子在被调用时就能读到设置。
 *
 *   钩子是「注册时就位、调用时才读设置」，所以 storage 那 1ms 的
 *   异步延迟完全不影响 —— 播放器初始化远在那之后。
 * ============================================================ */
(function () {
  'use strict';

  var DEFAULTS = {
    codecMode: 'avc',      // auto | avc | hevc | av1
    rafLimit: true,        // requestAnimationFrame 限帧
    scrollLimit: true      // scroll 监听器限流
  };

  var ATTR = {
    codecMode: 'data-zibei-codec',
    rafLimit: 'data-zibei-raf',
    scrollLimit: 'data-zibei-scroll'
  };

  function apply(cfg) {
    var el = document.documentElement;
    if (!el || !el.setAttribute) return;
    cfg = cfg || {};
    try {
      var mode = cfg.codecMode;
      if (['auto', 'avc', 'hevc', 'av1'].indexOf(mode) < 0) mode = DEFAULTS.codecMode;
      el.setAttribute(ATTR.codecMode, mode);
      el.setAttribute(ATTR.rafLimit, cfg.rafLimit === false ? '0' : '1');
      el.setAttribute(ATTR.scrollLimit, cfg.scrollLimit === false ? '0' : '1');
    } catch (e) { /* 忽略 */ }
  }

  function load() {
    // 先写一份默认值，保证 inject.js 任何时刻读到的都是有效值
    apply(DEFAULTS);
    try {
      if (chrome && chrome.storage && chrome.storage.sync) {
        chrome.storage.sync.get(DEFAULTS, function (v) {
          if (!chrome.runtime.lastError) apply(v);
        });
        return;
      }
    } catch (e) { /* 落到 local */ }
    try {
      if (chrome && chrome.storage && chrome.storage.local) {
        chrome.storage.local.get(DEFAULTS, function (v) { apply(v); });
      }
    } catch (e) { /* 忽略 */ }
  }

  load();

  // 用户在设置页改完，已打开的页面立即生效（不用刷新）
  // —— 但编码那项例外：播放器在页面加载时就已经选好编码了，改完要刷新
  try {
    if (chrome && chrome.storage && chrome.storage.onChanged) {
      chrome.storage.onChanged.addListener(function (changes, area) {
        if (area === 'sync' || area === 'local') load();
      });
    }
  } catch (e) { /* 忽略 */ }
})();
