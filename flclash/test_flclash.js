// ================================================================
// FlClash 覆写脚本测试
//
// 跑法：node 订阅脚本/test_flclash.js
//
// 重点验两件事 —— 这两件错了 Clash/Mihomo 会直接拒绝加载：
//   1. 分组不能重名
//   2. 分组引用必须都能解析到「真实节点 / 另一个分组 / 内置目标」
// ================================================================

const fs = require("fs");
const path = require("path");

const SRC = path.join(__dirname, "FlClash.js");
const main = eval(fs.readFileSync(SRC, "utf8") + "; main");

let pass = 0, fail = 0;

function check(label, actual, expected) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  const ok = a === e;
  if (ok) { pass++; } else { fail++; }
  console.log(
    "   " + (ok ? "\u2714" : "\u2718") + "  " + label.padEnd(46) +
    " 实际 " + String(a).padEnd(22) + " 期望 " + e
  );
}

const NODES = ["香港01", "香港02", "日本01", "日本02", "美国01", "新加坡01"];

function mkProxy(name) {
  return { name: name, type: "ss", server: "1.2.3.4", port: 443,
           cipher: "aes-128-gcm", password: "x" };
}

function makeConfig(opts) {
  opts = opts || {};
  const proxies = opts.proxies !== undefined ? opts.proxies : NODES.map(mkProxy);
  const groups = opts.groups !== undefined ? opts.groups : [
    { name: "自动选择", type: "url-test", proxies: NODES.slice() },
    { name: "故障转移", type: "fallback", proxies: NODES.slice() },
    { name: "全部节点", type: "select", proxies: NODES.slice() },
  ];
  return { proxies: proxies, "proxy-groups": groups, rules: ["MATCH,DIRECT"] };
}

const BUSINESS = ["AI", "YouTube", "Google", "GitHub", "Netflix", "Spotify",
                  "Steam", "Telegram", "TikTok", "Apple", "Microsoft"];

function byName(out, name) {
  return out["proxy-groups"].filter((g) => g && g.name === name)[0];
}

// ── 公共不变量：无论哪种输入都必须成立 ──

function invariants(label, out) {
  const names = out["proxy-groups"].map((g) => g.name);

  check(label + "：分组名唯一", names.length, new Set(names).size);

  const groupSet = new Set(names);
  const proxySet = new Set((out.proxies || []).map((p) => p.name));
  const BUILTIN = new Set(["DIRECT", "REJECT", "REJECT-DROP",
                           "PASS", "COMPATIBLE", "GLOBAL"]);

  const bad = [];
  out["proxy-groups"].forEach((g) => {
    (g.proxies || []).forEach((ref) => {
      if (!groupSet.has(ref) && !proxySet.has(ref) && !BUILTIN.has(ref)) {
        bad.push(g.name + " \u2192 " + ref);
      }
    });
  });
  check(label + "：分组引用全部可解析", bad, []);

  const badRule = [];
  (out.rules || []).forEach((r) => {
    const p = String(r).split(",");
    if (p[0] === "RULE-SET" && !groupSet.has(p[2])) badRule.push(r);
    if (p[0] === "MATCH" && !groupSet.has(p[1])) badRule.push(r);
  });
  check(label + "：规则目标全部可解析", badRule, []);

  const badRuleSet = [];
  const declared = Object.keys(out["rule-providers"] || {});
  (out.rules || []).forEach((r) => {
    const p = String(r).split(",");
    if (p[0] === "RULE-SET" && declared.indexOf(p[1]) === -1) badRuleSet.push(r);
  });
  check(label + "：RULE-SET 都已在 rule-providers 里声明", badRuleSet, []);
}

console.log("\n\u2550\u2550\u2550\u2550 一、机场自带自动选择组（复用它的名字）\u2550\u2550\u2550\u2550");

{
  const out = main(makeConfig());
  invariants("复用", out);

  check("自动选择组只存在一个", byName(out, "自动选择") !== undefined, true);
  check("自动选择组是 url-test", byName(out, "自动选择").type, "url-test");
  check("自动选择组含全部节点",
        byName(out, "自动选择").proxies.length, NODES.length);

  BUSINESS.forEach((b) => {
    const g = byName(out, b);
    check("分区 " + b + " 第一项是节点选择", g.proxies[0], "节点选择");
    check("分区 " + b + " 末项仍是国内直连",
          g.proxies[g.proxies.length - 1], "国内直连");
  });

  check("分区 AI 的完整选项",
        byName(out, "AI").proxies,
        ["节点选择", "香港", "日本", "新加坡", "美国", "国内直连"]);
}

console.log("\n\u2550\u2550\u2550\u2550 二、机场没有自动选择组（自己建一个）\u2550\u2550\u2550\u2550");

{
  const out = main(makeConfig({
    groups: [{ name: "全部节点", type: "select", proxies: NODES.slice() }],
  }));
  invariants("自建", out);

  const auto = byName(out, "自动选择");
  check("自建了自动选择组", auto !== undefined, true);
  check("自建的是 url-test", auto.type, "url-test");
  check("自建的内容是全部节点", auto.proxies, NODES);
  check("自建组带图标", typeof auto.icon === "string", true);
  check("自建组排在分组列表最前面",
        out["proxy-groups"][0].name, "自动选择");
  check("分区 YouTube 第一项是节点选择",
        byName(out, "YouTube").proxies[0], "节点选择");
}

console.log("\n\u2550\u2550\u2550\u2550 三、机场自动选择组叫别的名字\u2550\u2550\u2550\u2550");

{
  const out = main(makeConfig({
    groups: [{ name: "Auto Select", type: "url-test", proxies: NODES.slice() }],
  }));
  invariants("别名", out);

  check("沿用机场的英文名，不另建", byName(out, "Auto Select") !== undefined, true);
  check("没有多出一个叫「自动选择」的", byName(out, "自动选择"), undefined);
  check("分区 Netflix 第一项也是节点选择",
        byName(out, "Netflix").proxies[0], "节点选择");
}

console.log("\n\u2550\u2550\u2550\u2550 四、边界：没有节点 / 没有分组\u2550\u2550\u2550\u2550");

{
  const out = main(makeConfig({ proxies: [], groups: [] }));
  invariants("空订阅", out);

  check("没有节点时不硬造自动选择组", byName(out, "自动选择"), undefined);
  check("空订阅时分区只有节点选择 + 国内直连",
        byName(out, "AI").proxies, ["节点选择", "国内直连"]);
  check("没崩，分组仍然产出", out["proxy-groups"].length > 0, true);
}

{
  const only = ["香港01"];
  const out = main(makeConfig({
    proxies: only.map(mkProxy),
    groups: [],
  }));
  invariants("单节点", out);

  check("只有一个节点也能建 url-test",
        byName(out, "自动选择").proxies, only);
}

console.log("\n\u2550\u2550\u2550\u2550 五、广告拦截必须保持关闭\u2550\u2550\u2550\u2550");

{
  const cfg = makeConfig();
  cfg.hosts = { "ads.example.com": "0.0.0.0" };
  cfg["sub-rules"] = { "广告": ["DOMAIN-SUFFIX,doubleclick.net"] };
  cfg.rules = ["RULE-SET,Advertising,REJECT", "MATCH,DIRECT"];
  cfg["rule-providers"] = { "Advertising": { type: "http", url: "x", path: "y" } };

  const out = main(cfg);
  invariants("清广告", out);

  check("hosts 被清空", out.hosts, {});
  check("sub-rules 被清空", out["sub-rules"], {});
  check("旧规则被整体替换，不含 Advertising",
        out.rules.filter((r) => r.indexOf("Advertising") !== -1), []);
  check("最终规则里没有任何 REJECT",
        out.rules.filter((r) => r.indexOf("REJECT") !== -1), []);
}

console.log("\n\u2550\u2550\u2550\u2550 五点五、IP 检测必须跟随主选择器\u2550\u2550\u2550\u2550");

{
  const out = main(makeConfig());
  const nt = out.rules.filter((r) => r.indexOf("NetworkTest") !== -1)[0];

  check("NetworkTest 指向节点选择（不是独立分组）",
        nt, "RULE-SET,NetworkTest,节点选择");
  check("「网络检测」独立分组已移除",
        out["proxy-groups"].filter((g) => g.name === "网络检测").length, 0);
  check("rule-providers 里 NetworkTest 仍保留",
        typeof out["rule-providers"]["NetworkTest"], "object");
}

console.log("\n\u2550\u2550\u2550\u2550 五点六、节点选择：唯一的主控开关\u2550\u2550\u2550\u2550");

{
  const out = main(makeConfig());
  const ns = byName(out, "节点选择");

  check("节点选择组存在", ns !== undefined, true);
  check("节点选择是 select（可手选）", ns.type, "select");
  check("第一项是自动选择，默认行为不变", ns.proxies[0], "自动选择");
  check("后面列出全部节点", ns.proxies.slice(1), NODES);
  check("节点选择带图标", typeof ns.icon, "string");

  check("MATCH 指向节点选择",
        out.rules.filter((r) => r.indexOf("MATCH") === 0)[0], "MATCH,节点选择");
  check("NetworkTest 也指向节点选择",
        out.rules.filter((r) => r.indexOf("NetworkTest") !== -1)[0],
        "RULE-SET,NetworkTest,节点选择");

  check("旧的「一键代理」已不存在", byName(out, "一键代理"), undefined);

  // 一个节点都没有时，这个组也必须合法存在 ——
  // 否则 MATCH 会指向不存在的分组，Clash 直接拒绝加载
  const empty = main(makeConfig({ proxies: [], groups: [] }));
  const nsEmpty = byName(empty, "节点选择");
  check("空订阅时节点选择仍存在", nsEmpty !== undefined, true);
  check("空订阅时退回 DIRECT", nsEmpty.proxies, ["DIRECT"]);
  check("空订阅时 MATCH 仍然可解析",
        empty.rules.filter((r) => r.indexOf("MATCH") === 0)[0], "MATCH,节点选择");
}

console.log("\n\u2550\u2550\u2550\u2550 六、地区分组不受影响\u2550\u2550\u2550\u2550");

{
  const out = main(makeConfig());
  const hk = byName(out, "香港");
  check("地区组仍是 url-test", hk.type, "url-test");
  check("地区组只含本地区节点", hk.proxies, ["香港01", "香港02"]);
  check("地区组里没有自动选择",
        hk.proxies.indexOf("自动选择") === -1, true);
  check("旧的「一键代理」已彻底移除", byName(out, "一键代理"), undefined);
}

console.log("\n\u2550\u2550\u2550\u2550 结果：" + pass + " 通过 / " + fail + " 失败 \u2550\u2550\u2550\u2550\n");
process.exit(fail === 0 ? 0 : 1);
