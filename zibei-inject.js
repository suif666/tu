/* ============================================================
 * [自备] —— 面向老机器的网页减负脚本
 *
 * 本文件做两件事：
 *
 *   第一部分：编码强制
 *     让网站以为浏览器不支持 AV1 / HEVC / VP9，从而回退到 H.264。
 *     H.264 在 2011–2015 年的 Intel Mac 上有 GPU 硬件解码，
 *     而 AV1 / HEVC / VP9 只能纯 CPU 软解，1080p60 扛不住。
 *
 *   第二部分：动效削减（JS 层）
 *     CSS 驱动的动效由 reduce.css 处理。但有一类动态效果 CSS 管不到：
 *       · Canvas / WebGL 做的水波纹、粒子、流体背景
 *       · 光标移动到哪里、哪里就变化的跟随效果
 *     这些是 JS 靠 requestAnimationFrame 每帧重绘实现的，
 *     所以必须在 JS 层限帧。
 *
 * 两项都只影响性能相关的行为，不收集任何数据、不联网。
 * ============================================================ */
(function () {
  'use strict';

  /* ==========================================================
   * 第一部分：编码强制
   * ========================================================== */

  // 各编码的识别串，全部小写。
  // 注意 vp9 / vp09 两种写法都要列：vp9 并不是 vp09 的子串
  // （vp09 中间多一个 0），漏掉哪个都会放过对应的流。
  //   av01           AV1          —— B站 / YouTube 新默认，软解最重
  //   hev1 / hvc1    HEVC/H.265   —— B站高码率 / 大会员
  //   dvh1 / dvhe    Dolby Vision —— 基于 HEVC，老机器同样解不动
  //   vp09 / vp9     VP9          —— YouTube 默认
  //   vp08 / vp8     VP8          —— 很老的格式
  var TAGS = {
    av1:  ['av01'],
    hevc: ['hev1', 'hvc1'],
    dv:   ['dvh1', 'dvhe'],
    vp9:  ['vp09', 'vp9'],
    vp8:  ['vp08', 'vp8']
  };

  var ALL_KEYS = ['av1', 'hevc', 'dv', 'vp9', 'vp8'];

  var MODE_NAMES = {
    auto: '自动（按本机硬解能力）',
    avc:  '优先 AVC / H.264',
    hevc: '优先 HEVC / H.265',
    av1:  '优先 AV1'
  };

  var AUTO_NAMES = {
    av1:  'AV1',
    hevc: 'HEVC / H.265',
    avc:  'H.264 / AVC',
    vp9:  'VP9'
  };

  // 从 <html> 的 data-* 属性读设置。
  //
  // 为什么要绕 DOM：本脚本跑在网页的 MAIN world 里（必须如此，否则
  // 覆写不到网页自己的 MediaSource），而 MAIN world 读不到扩展的
  // chrome.storage。于是由 bridge.js 在隔离世界读好设置，写成 data-*
  // 属性 —— 两个世界共享同一个 DOM。
  //
  // 钩子是「注册时就位、调用时才读设置」，所以 storage 那 1ms 的异步
  // 延迟完全不影响：播放器初始化远在那之后。
  function getMode() {
    var el = document.documentElement;
    var m = (el && el.getAttribute) ? el.getAttribute('data-zibei-codec') : null;
    if (m !== 'auto' && m !== 'avc' && m !== 'hevc' && m !== 'av1') m = 'auto';
    return m;
  }

  // 读一个开关型属性。属性缺失时按「开」处理 ——
  // bridge.js 还没跑完的那一瞬间不应该导致功能失效。
  function toggleOn(attr) {
    var el = document.documentElement;
    if (!el || !el.getAttribute) return true;
    return el.getAttribute(attr) !== '0';
  }

  // 「自动」模式下，本机该用哪种编码 —— 由 bridge.js 探测后写入。
  //
  // bridge.js 的探测跑在隔离世界，读到的是浏览器**原生**解码能力，
  // 用 mediaCapabilities.decodingInfo 拿到 powerEfficient（是否硬解），
  // 规则是：优先挑有硬解的、压缩率最高的那个；一个硬解都没有时，
  // 退而挑纯 CPU 开销最低的那个。
  function getAutoCodec() {
    var el = document.documentElement;
    var a = (el && el.getAttribute) ? el.getAttribute('data-zibei-auto') : null;
    if (a === 'av1' || a === 'hevc' || a === 'avc' || a === 'vp9') return a;
    return 'avc';   // 还没探测出结果 → 保守用 H.264（老机器上最稳）
  }

  // 当前模式下允许哪些编码类别
  function allowKeys() {
    var mode = getMode();
    var allow;
    if (mode === 'auto')       allow = [getAutoCodec()];
    else if (mode === 'hevc')  allow = ['hevc'];
    else if (mode === 'av1')   allow = ['av1'];
    else                       allow = ['avc'];

    // H.264 永远放行 —— 通用兜底。否则遇到只提供 H.264 的网站会直接
    // 变成"无可用视频源"，比卡顿还糟。
    if (allow.indexOf('avc') < 0) allow = allow.concat(['avc']);
    // Dolby Vision 基于 HEVC，允许 HEVC 时一并放行
    if (allow.indexOf('hevc') >= 0) allow = allow.concat(['dv']);
    return allow;
  }

  // 把模式翻译成实际要拦截的字符串列表，并缓存 ——
  // isTypeSupported 会被调用很多次，不必每次都重建数组。
  var _blKey = null, _blList = [];
  function blockList() {
    var mode = getMode();
    var key = mode + '|' + (mode === 'auto' ? getAutoCodec() : '');
    if (key !== _blKey) {
      var allow = allowKeys();
      var out = [];
      for (var i = 0; i < ALL_KEYS.length; i++) {
        if (allow.indexOf(ALL_KEYS[i]) >= 0) continue;   // 放行的跳过
        out = out.concat(TAGS[ALL_KEYS[i]]);
      }
      _blKey = key;
      _blList = out;
    }
    return _blList;
  }

  // 注意：必须用「包含」判断，不能用「开头」判断。
  // 真实的 MIME 串长这样：
  //     video/mp4; codecs="av01.0.05M.08"
  //                 ^^^^^ 开头是 video/，所以前缀匹配永远不成立。
  function isBlocked(type) {
    if (typeof type !== 'string') return false;
    var list = blockList();
    if (!list.length) return false;          // auto 模式：什么都不拦
    var t = type.trim().toLowerCase();
    for (var i = 0; i < list.length; i++) {
      if (t.indexOf(list[i]) !== -1) return true;
    }
    return false;
  }

  // —— 1) HTMLMediaElement.prototype.canPlayType ——
  // 返回 ''（空串）= 不支持，'maybe' / 'probably' = 支持
  try {
    var origCanPlayType = HTMLMediaElement.prototype.canPlayType;
    HTMLMediaElement.prototype.canPlayType = function (type) {
      if (isBlocked(type)) return '';
      return origCanPlayType.apply(this, arguments);
    };
  } catch (e) { /* 忽略：某些环境可能冻结了原型 */ }

  // —— 2) MediaSource.isTypeSupported ——
  // B站 bpx-player / DashPlayer 和 YouTube 主要靠这个做判断
  try {
    if (window.MediaSource && window.MediaSource.isTypeSupported) {
      var origIsTypeSupported = window.MediaSource.isTypeSupported;
      window.MediaSource.isTypeSupported = function (type) {
        if (isBlocked(type)) return false;
        return origIsTypeSupported.apply(this, arguments);
      };
    }
  } catch (e) { /* 忽略 */ }

  // —— 3) ManagedMediaSource ——
  // Safari 的接口，Chromium 里通常不存在，顺手一起处理
  try {
    if (window.ManagedMediaSource && window.ManagedMediaSource.isTypeSupported) {
      var origMMS = window.ManagedMediaSource.isTypeSupported;
      window.ManagedMediaSource.isTypeSupported = function (type) {
        if (isBlocked(type)) return false;
        return origMMS.apply(this, arguments);
      };
    }
  } catch (e) { /* 忽略 */ }

  /* ==========================================================
   * 第二部分：动效削减（JS 层）
   * ========================================================== */

  // 帧率上限。Canvas 水波纹 / 光标跟随这类效果就是靠
  // requestAnimationFrame 每帧重绘实现的，把它们限到 30fps，
  // 视觉效果几乎无感，但重绘次数直接砍半。
  // 想更省电可以改成 1000/20（20fps）；想关掉这功能就设成 0。
  var RAF_MIN_INTERVAL = 1000 / 30;

  // 滚动事件监听器的调用频率上限。
  // 滚动卡顿的另一大来源：网站给 scroll 挂了很重的处理函数，
  // 每次滚动都触发。滚动事件本身是按屏幕刷新率（60Hz）发的，
  // 压到 30Hz 后处理开销直接减半 —— 而且滚动处理函数基本都是
  // 读取当前位置，丢掉一半事件不影响结果。
  // 想关掉就设成 0。
  var SCROLL_MIN_INTERVAL = 1000 / 30;

  // —— 4) 强制 prefers-reduced-motion: reduce ——
  // 正规做过适配的网站会读这个媒体查询，然后自己关掉动效。
  // 让网站自己关，比我们硬拆它的 DOM 可靠得多。
  try {
    var origMatchMedia = window.matchMedia;
    if (typeof origMatchMedia === 'function') {
      window.matchMedia = function (query) {
        if (typeof query === 'string' && /prefers-reduced-motion/i.test(query)) {
          // 注意分清两个方向：
          //   (prefers-reduced-motion: reduce)         → 应为 true
          //   (prefers-reduced-motion: no-preference)  → 应为 false
          // 两个都返回 true 会让部分网站的判断逻辑反过来。
          return {
            matches: /:\s*reduce/i.test(query),
            media: query,
            onchange: null,
            addListener: function () {},
            removeListener: function () {},
            addEventListener: function () {},
            removeEventListener: function () {},
            dispatchEvent: function () { return false; }
          };
        }
        return origMatchMedia.call(window, query);
      };
    }
  } catch (e) { /* 忽略 */ }

  // —— 5) Web Animations API（element.animate）——
  // 不把它整个接管掉（那样依赖 onfinish 回调的代码会永远等不到），
  // 而是把时长改成 0：动画立刻结束、finish 事件照常触发，
  // fill: forwards 的最终状态也照常保留。
  try {
    if (window.Element && Element.prototype && Element.prototype.animate) {
      var origAnimate = Element.prototype.animate;
      Element.prototype.animate = function (keyframes, options) {
        var opts;
        if (typeof options === 'number') {
          opts = 0;
        } else if (options && typeof options === 'object' &&
                   !(options instanceof Array)) {   // 数组形式是「多组关键帧」，不能拆
          opts = {};
          for (var k in options) {
            if (Object.prototype.hasOwnProperty.call(options, k)) opts[k] = options[k];
          }
          opts.duration = 0;
          opts.delay = 0;
          opts.iterations = 1;
        } else {
          opts = options;
        }
        return origAnimate.call(this, keyframes, opts);
      };
    }
  } catch (e) { /* 忽略 */ }

  // —— 6) requestAnimationFrame 限帧 ——
  //
  // 实现要点（这里踩过坑，写清楚）：
  //
  // 不能按"单个回调"去限帧。如果那样写，一个持续重绘的动画
  // （水波纹背景、光标跟随）会不停占用时间片，把其它回调活活饿死 ——
  // 尤其是很多库用来「下一帧再算布局」的一次性 requestAnimationFrame，
  // 它会永远排不上队，网站直接卡在布局没算的状态。
  //
  // 正确做法是**按帧整批限流**：
  //   · 所有注册的回调都进同一个待执行队列
  //   · 每隔 RAF_MIN_INTERVAL 毫秒把整批一起执行掉
  //   · 时间片没到就把整批一起顺延到下一帧（绝不丢任何一个回调）
  // 这样帧率被压到 30fps，但每个回调都保证会被执行，不会互相饿死。
  try {
    var origRAF = window.requestAnimationFrame;
    var origCAF = window.cancelAnimationFrame;
    if (RAF_MIN_INTERVAL > 0 && typeof origRAF === 'function') {
      var rafSeq = 0;
      var rafReg = {};          // id -> { cb, cancelled }
      var rafPending = [];      // 本轮待执行的回调 id
      var rafScheduled = false;
      var rafLast = 0;

      var nowMs = function () {
        return (window.performance && performance.now)
          ? performance.now() : Date.now();
      };

      var rafSchedule = function () {
        if (rafScheduled) return;
        rafScheduled = true;
        origRAF.call(window, rafFlush);
      };

      var rafFlush = function (timestamp) {
        // 设置页把「Canvas 动画限帧」关掉时，直接按浏览器原生帧率跑
        // —— 仍然整批执行，只是不再等时间片。
        if (toggleOn('data-zibei-raf') &&
            nowMs() - rafLast < RAF_MIN_INTERVAL - 1) {
          // 时间片还没到 —— 整批顺延到下一帧，不丢任何回调
          origRAF.call(window, rafFlush);
          return;
        }
        rafLast = nowMs();
        rafScheduled = false;           // 允许回调内部再注册时重新排程

        var batch = rafPending;
        rafPending = [];
        for (var i = 0; i < batch.length; i++) {
          var st = rafReg[batch[i]];
          if (!st || st.cancelled) continue;
          delete rafReg[batch[i]];
          try {
            st.cb(timestamp);
          } catch (err) {
            // 单个回调抛错不能拖垮整批；异步重抛，保留控制台里的报错
            (function (e) { setTimeout(function () { throw e; }, 0); })(err);
          }
        }

        // 回调执行期间新注册的，排下一轮
        if (rafPending.length > 0) rafSchedule();
      };

      window.requestAnimationFrame = function (callback) {
        var id = ++rafSeq;
        rafReg[id] = { cb: callback, cancelled: false };
        rafPending.push(id);
        rafSchedule();
        return id;
      };

      window.cancelAnimationFrame = function (id) {
        var st = rafReg[id];
        if (st) {
          st.cancelled = true;
          delete rafReg[id];
          return;
        }
        return origCAF.call(window, id);
      };
    }
  } catch (e) { /* 忽略 */ }

  // —— 7) scroll 事件监听器限流 ——
  //
  // 滚动卡顿的另一大来源：网站给 scroll 挂了很重的处理函数
  // （视差、吸顶导航、懒加载判断），每次滚动都跑一遍。
  //
  // 实现上有两个必须注意的点：
  //   · 只包装「函数形式」的监听器；对象形式（带 handleEvent 的）
  //     原样放过，不动它。
  //   · 必须用 WeakMap 记住「原始监听器 → 包装后监听器」的对应关系。
  //     否则网站调 removeEventListener 时找不到当初注册的那个包装函数，
  //     监听器就永远摘不掉 —— 会造成重复触发和内存泄漏。
  try {
    if (SCROLL_MIN_INTERVAL > 0 &&
        window.EventTarget && EventTarget.prototype &&
        EventTarget.prototype.addEventListener) {
      var origAddEL = EventTarget.prototype.addEventListener;
      var origRemoveEL = EventTarget.prototype.removeEventListener;
      var scrollWrapped = new WeakMap();     // 原始监听器 -> 包装后监听器

      EventTarget.prototype.addEventListener = function (type, listener, options) {
        if (type === 'scroll' && typeof listener === 'function' && !listener.__zibeiWrapped) {
          var wrapped = scrollWrapped.get(listener);
          if (!wrapped) {
            var lastCall = 0;
            wrapped = function (ev) {
              var now = (window.performance && performance.now)
                ? performance.now() : Date.now();
              // 设置页把「滚动监听限流」关掉时直接放行
              // 减 1ms 是容差。事件间隔和限流间隔往往正好是同一个值的
              // 倍数（比如都是 1000/60 与 1000/30），浮点误差会让
              // "刚好到点"的那一次判成"还没到"，实际频率掉到 20+Hz。
              // 留 1ms 容差后就稳定在目标频率上了。
              if (toggleOn('data-zibei-scroll') &&
                  now - lastCall < SCROLL_MIN_INTERVAL - 1) return;
              lastCall = now;
              return listener.call(this, ev);
            };
            wrapped.__zibeiWrapped = true;
            scrollWrapped.set(listener, wrapped);
          }
          return origAddEL.call(this, type, wrapped, options);
        }
        return origAddEL.apply(this, arguments);
      };

      EventTarget.prototype.removeEventListener = function (type, listener, options) {
        if (type === 'scroll' && typeof listener === 'function') {
          var wrapped = scrollWrapped.get(listener);
          if (wrapped) return origRemoveEL.call(this, type, wrapped, options);
        }
        return origRemoveEL.apply(this, arguments);
      };
    }
  } catch (e) { /* 忽略 */ }

  /* ==========================================================
   * 控制台自检工具
   * 用法：在页面上按 F12，控制台里执行  __zibei.test()
   * ========================================================== */
  try {
    window.__zibei = {
      get mode() { return getMode(); },
      get modeName() { return MODE_NAMES[getMode()]; },
      get autoCodec() { return getAutoCodec(); },
      get allow() { return allowKeys().slice(); },
      get blocked() { return blockList().slice(); },
      rafFpsLimit: Math.round(1000 / RAF_MIN_INTERVAL),
      scrollHzLimit: Math.round(1000 / SCROLL_MIN_INTERVAL),
      isBlocked: isBlocked,

      // 检查编码拦截是否生效。
      // 期望值随模式变化 —— 每行括号里都写清楚了当前应该是 true 还是 false。
      testCodec: function () {
        var ms = window.MediaSource;
        var mode = getMode();
        var allow = allowKeys();
        var does = function (k) { return allow.indexOf(k) >= 0; };
        var out = {};
        out['当前模式'] = MODE_NAMES[mode];
        if (mode === 'auto') {
          out['自动选定的编码'] = AUTO_NAMES[getAutoCodec()] +
            (getAutoCodec() === 'avc' ? '（尚未探测出结果时的保守兜底也是它）' : '');
        }
        out['放行的编码'] = allow.join(', ');
        out['实际拦截串'] = (blockList().join(', ') || '(空 —— 不拦截任何格式)');
        out['屏蔽 av01（应为 ' + !does('av1') + '）'] =
          isBlocked('video/mp4; codecs="av01.0.05M.08"');
        out['屏蔽 hev1（应为 ' + !does('hevc') + '）'] =
          isBlocked('video/mp4; codecs="hev1.1.6.L93.B0"');
        out['屏蔽 vp09（应为 ' + !does('vp9') + '）'] =
          isBlocked('video/mp4; codecs="vp09.00.51.08"');
        out['屏蔽 vp9 （应为 ' + !does('vp9') + '）'] =
          isBlocked('video/webm; codecs="vp9"');
        out['放行 avc1（恒为 false）'] =
          isBlocked('video/mp4; codecs="avc1.640028"');
        out['放行 aac （恒为 false）'] =
          isBlocked('audio/mp4; codecs="mp4a.40.2"');
        out['isTypeSupported(av01)'] =
          ms ? ms.isTypeSupported('video/mp4; codecs="av01.0.05M.08"') : 'N/A';
        out['isTypeSupported(avc1)（恒为 true）'] =
          ms ? ms.isTypeSupported('video/mp4; codecs="avc1.640028"') : 'N/A';
        return out;
      },

      // 检查动效削减是否生效
      testMotion: function () {
        return {
          'reduce 查询 (应为 true)':
            window.matchMedia('(prefers-reduced-motion: reduce)').matches,
          'no-preference 查询 (应为 false)':
            window.matchMedia('(prefers-reduced-motion: no-preference)').matches,
          '普通媒体查询是否透传 (应为 false)':
            window.matchMedia('(min-width: 999999px)').matches,
          'rAF 帧率上限': (toggleOn('data-zibei-raf')
            ? Math.round(1000 / RAF_MIN_INTERVAL) + ' fps' : '已关闭（原生帧率）'),
          'scroll 监听限流': (toggleOn('data-zibei-scroll')
            ? Math.round(1000 / SCROLL_MIN_INTERVAL) + ' Hz' : '已关闭'),
          'Element.animate 是否已接管':
            (window.Element && Element.prototype.animate &&
             Element.prototype.animate.toString().indexOf('origAnimate') !== -1)
        };
      },

      // 一次性全测
      test: function () {
        var out = {};
        var a = this.testCodec(), b = this.testMotion();
        for (var k in a) out[k] = a[k];
        for (var j in b) out[j] = b[j];
        return out;
      }
    };
  } catch (e) { /* 忽略 */ }

  // —— 只在视频网站的顶层文档打一条日志，避免刷屏 ——
  try {
    if (window.top === window.self && /bilibili|youtube|b23\.tv/.test(location.host)) {
      console.log('[自备] 已生效 @ ' + location.host +
                  ' ｜ 编码模式: ' + MODE_NAMES[getMode()] +
                  (getMode() === 'auto' ? ' → ' + AUTO_NAMES[getAutoCodec()] : '') +
                  ' ｜ 拦截: ' + (blockList().join(', ') || '无') +
                  ' ｜ rAF: ' + (toggleOn('data-zibei-raf')
                    ? Math.round(1000 / RAF_MIN_INTERVAL) + 'fps' : '关闭') +
                  ' ｜ scroll: ' + (toggleOn('data-zibei-scroll')
                    ? Math.round(1000 / SCROLL_MIN_INTERVAL) + 'Hz' : '关闭') +
                  ' ｜ 自检: 执行 __zibei.test()');
    }
  } catch (e) { /* 忽略 */ }
})();
