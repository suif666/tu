/* ============================================================
 * [自备] —— 设备解码能力探测
 *
 * 由 bridge.js（内容脚本，隔离世界）和 popup.js（设置小窗）共用。
 *
 * 为什么用 mediaCapabilities.decodingInfo 而不是 isTypeSupported：
 *   只有 decodingInfo 会返回 powerEfficient —— 也就是「是否真的走
 *   硬件解码」。isTypeSupported 对纯软件解码的格式一样返回 true，
 *   分不出这台机器到底扛不扛得住。
 *
 * 为什么在隔离世界探测是准的：
 *   隔离世界和网页的 MAIN world 是两套独立的 JS 全局/原型。inject.js
 *   在 MAIN world 覆写的 MediaSource 不会影响隔离世界，所以这里读到
 *   的永远是**浏览器原生能力** —— 正是我们要的。
 * ============================================================ */
(function () {
  'use strict';

  var W = 1920, H = 1080, BITRATE = 10326000, FPS = 60;

  var CANDIDATES = [
    { key: 'av1',  name: 'AV1',           mime: 'video/mp4; codecs="av01.0.05M.08"' },
    { key: 'hevc', name: 'HEVC / H.265',  mime: 'video/mp4; codecs="hev1.1.6.L120.B0"' },
    { key: 'avc',  name: 'H.264 / AVC',   mime: 'video/mp4; codecs="avc1.640028"' },
    { key: 'vp9',  name: 'VP9',           mime: 'video/mp4; codecs="vp09.00.51.08"' }
  ];

  // 首选顺序：有硬解时，按压缩率从高到低挑（越靠前越省流量）
  var HW_ORDER = ['av1', 'hevc', 'avc', 'vp9'];

  // 一个硬解都没有时，按「纯 CPU 软解的开销」从低到高挑
  // （软解 H.264 最省，AV1 最重 —— 顺序和上面正好相反）
  var SW_ORDER = ['avc', 'vp9', 'hevc', 'av1'];

  function probeOne(c) {
    var nativeOk = false;
    try {
      nativeOk = !!(window.MediaSource && MediaSource.isTypeSupported(c.mime));
    } catch (e) { /* 忽略 */ }

    var p;
    if (navigator.mediaCapabilities && navigator.mediaCapabilities.decodingInfo) {
      p = navigator.mediaCapabilities.decodingInfo({
        type: 'file',
        video: {
          contentType: c.mime,
          width: W, height: H,
          bitrate: BITRATE, framerate: FPS
        }
      }).then(function (r) {
        return {
          key: c.key, name: c.name, mime: c.mime,
          supported: !!r.supported,
          smooth: !!r.smooth,
          efficient: r.powerEfficient === true
        };
      });
    } else {
      p = Promise.resolve({
        key: c.key, name: c.name, mime: c.mime,
        supported: nativeOk, smooth: null, efficient: null
      });
    }
    return p.catch(function () {
      return {
        key: c.key, name: c.name, mime: c.mime,
        supported: nativeOk, smooth: null, efficient: null
      };
    });
  }

  // 决策规则：先看谁有硬解；都没有硬解才退而求其次选 CPU 开销最低的
  function pickBest(report) {
    var i, k;
    for (i = 0; i < HW_ORDER.length; i++) {
      k = HW_ORDER[i];
      if (report[k] && report[k].supported && report[k].efficient === true) return k;
    }
    for (i = 0; i < SW_ORDER.length; i++) {
      k = SW_ORDER[i];
      if (report[k] && report[k].supported) return k;
    }
    return 'avc';   // 兜底
  }

  function probe() {
    return Promise.all(CANDIDATES.map(probeOne)).then(function (list) {
      var report = {};
      list.forEach(function (r) { report[r.key] = r; });
      return { list: list, report: report, best: pickBest(report), at: Date.now() };
    });
  }

  window.__zibeiProbe = {
    CANDIDATES: CANDIDATES,
    HW_ORDER: HW_ORDER,
    SW_ORDER: SW_ORDER,
    pickBest: pickBest,
    probe: probe
  };
})();
