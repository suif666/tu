# FlClash 覆写脚本（自建）

`flclash-override.js` 是 FlClash / Mihomo 的订阅覆写脚本，填在客户端「覆写」里。
本目录是它依赖的两个远程资源，**已从上游 `n0de-sudo/Perfect-Rules` 搬到自己仓库**，
上游怎么改都不会再影响我们。

## 文件

| 路径 | 用途 |
|---|---|
| `flclash/rules/*.yaml` | 16 个规则集，脚本引用其中 12 个 |
| `flclash/icons/*.png`  | 23 个分组图标，脚本引用其中 21 个 |

## 规则集是什么

每个文件都是 `behavior: classical` 的 payload 列表。绝大部分只有一行：

    payload:
      - GEOSITE,netflix

即「把 Netflix 的域名交给 Mihomo 内置的 geosite 数据库匹配」。
**真正的域名库在客户端里，不在这个仓库里** —— 这里能改的是
「用哪个 category、走哪个分组」，不是域名清单本身。

少部分是手写域名：`github.yaml`、`network-test.yaml`、`Steam_Download.yaml`。

## 怎么改

- **换分流**：改 `GEOSITE,<category>` 里的 category 名
- **加域名**：往 payload 里加 `DOMAIN,xxx` 或 `DOMAIN-SUFFIX,xxx`
- **加规则集**：新建 yaml，再在 `flclash-override.js` 的
  `config["rule-providers"]` 和 `config["rules"]` 里各加一条

## 注意

- **`ads.yaml` 故意没搬**（内容是 `GEOSITE,category-ads-all`），
  那正是机场用来拦广告的规则集。脚本的 `rules` 里没有任何 `REJECT`，
  加上开头清空了 `hosts` / `sub-rules`，所以广告拦截是关掉的。
- 上游的 `crypto.yaml` / `disney.yaml` / `software.yaml` / `Steam_Download.yaml`
  没被脚本引用，一并搬来备用。
- 图标 `Direct.png` / `Speedtest.png` 暂时没被引用，留着备用。

## 更新方式

改完推到 `main`，客户端重新应用一次覆写即可。
jsDelivr 的 `@main` 有缓存，刚推完可能还是旧的；要立刻生效用钉 commit 地址。
