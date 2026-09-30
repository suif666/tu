/* ============================================================
 * 强制 H.264 —— 让网站以为浏览器不支持 AV1 / HEVC / VP9
 *
 * 原理：
 *   播放器在决定发哪种编码给你之前，会先问浏览器一句
 *   「你支持 av01 吗？」（通过 MediaSource.isTypeSupported /
 *   HTMLMediaElement.canPlayType）。这里把这些问询的答案改成
 *   「不支持」，播放器就会退回 H.264。
 *
 *   而 H.264 在 2011–2015 年的 Intel Mac（Haswell / Ivy Bridge /
 *   Sandy Bridge）上有 GPU 硬件解码，CPU 占用极低；
 *   AV1 / HEVC / VP9 在这些机器上只能纯 CPU 软解，1080p60 扛不住。
 *
 * 只改编码协商，不动画面质量，不收集任何数据。
 * ============================================================ */
(function () {
  'use strict';

  // 屏蔽列表，全部小写。
  // 注意 vp9 / vp09 两种写法都要列：vp9 并不是 vp09 的子串
  // （vp09 中间多一个 0），漏掉哪个都会放过对应的流。
  //   av01           AV1        —— B站 / YouTube 新默认，软解最重
  //   hev1 / hvc1    HEVC/H.265 —— B站高码率 / 大会员
  //   dvh1 / dvhe    Dolby Vision —— 基于 HEVC，老机器同样解不动
  //   vp09 / vp9     VP9        —— YouTube 默认
  //   vp08 / vp8     VP8        —— 很老的格式
  var BLOCK = ['av01', 'hev1', 'hvc1', 'dvh1', 'dvhe', 'vp09', 'vp9', 'vp08', 'vp8'];

  // 注意：必须用「包含」判断，不能用「开头」判断。
  // 真实的 MIME 串长这样：
  //     video/mp4; codecs="av01.0.05M.08"
  //                 ^^^^^ 开头是 video/，所以前缀匹配永远不成立。
  function isBlocked(type) {
    if (typeof type !== 'string') return false;
    var t = type.trim().toLowerCase();
    for (var i = 0; i < BLOCK.length; i++) {
      if (t.indexOf(BLOCK[i]) !== -1) return true;
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
  // B站 bpx-player 和 YouTube 主要靠这个做判断
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

  // —— 控制台自检工具 ——
  // 在视频页面按 F12 打开控制台，执行：  __forceH264.test()
  try {
    window.__forceH264 = {
      blocked: BLOCK.slice(),
      isBlocked: isBlocked,
      test: function () {
        var ms = window.MediaSource;
        return {
          '屏蔽 av01 (应为 true)':  isBlocked('video/mp4; codecs="av01.0.05M.08"'),
          '屏蔽 hev1 (应为 true)':  isBlocked('video/mp4; codecs="hev1.1.6.L93.B0"'),
          '屏蔽 vp09 (应为 true)':  isBlocked('video/mp4; codecs="vp09.00.51.08"'),
          '放行 avc1 (应为 false)': isBlocked('video/mp4; codecs="avc1.640028"'),
          'isTypeSupported(av01) (应为 false)':
            ms ? ms.isTypeSupported('video/mp4; codecs="av01.0.05M.08"') : 'N/A',
          'isTypeSupported(avc1) (应为 true)':
            ms ? ms.isTypeSupported('video/mp4; codecs="avc1.640028"') : 'N/A'
        };
      }
    };
  } catch (e) { /* 忽略 */ }

  // —— 只在视频网站的顶层文档打一条日志，避免刷屏 ——
  try {
    if (window.top === window.self && /bilibili|youtube|b23\.tv/.test(location.host)) {
      console.log('[强制H264] 已生效 @ ' + location.host +
                  ' ｜ 已屏蔽: ' + BLOCK.join(', ') +
                  ' ｜ 自检: 执行 __forceH264.test()');
    }
  } catch (e) { /* 忽略 */ }
})();
