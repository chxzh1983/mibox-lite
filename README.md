# mibox-lite

小米 MiWiFi（AX3600，无 USB 口）上的**单内核 sing-box 精简代理 + 广告拦截**方案。
由官方 ShellCrash 裁剪而来（保留 sing-box 内核 + zashboard 面板 + 订阅导入 + 广告拦截 + CN 分流 + 自启/看门狗），砍掉双内核、多设备适配、TG 机器人、多级交互菜单。

**一条命令安装，安装完成后全程通过网页面板管理，无交互菜单。**

## 特性

| 能力 | 实现 |
|---|---|
| 代理内核 | sing-box 1.13.14（ShellCrash 定制版，~9MB UPX，含 clash_api） |
| 网页面板 | zashboard，`http://192.168.31.1:9999/ui`（端口/密钥见 `crash status`） |
| 订阅导入 | `crash sub URL`：subconverter 转 sing-box outbounds，面板负责切节点/看流量 |
| 广告拦截 | 内核下载 ApolloRioo 广告域名 JSON → 本地编译 srs → route 层 rule_set 命中 REJECT 出站 |
| CN 分流 | ShellCrash 官方 srs_geosite_cn / srs_geoip_cn（与内核版本配套） |
| 透明代理 | iptables PREROUTING 重定向 + DNS 劫持 53→1053 + mark 255 防回环 |
| 自启 | cron `@reboot`（MiWiFi 持久 `/etc/crontabs/root`），boot.sh 等 WAN 就绪后拉起 |
| 看门狗 | cron `*/5`，120s 冷却，`.stopped` 手动停止标记，内核缓存丢失时自动重下 |
| 小闪存 | 资源存 `/data/SClite`（tgz/json/srs，~17MB），内核解压到 `/tmp/SClite` 运行 |

## 目录结构（路由器上）

```
/data/SClite/            闪存持久区
├── crash                主 CLI（430 行）
├── fw.sh                iptables 注入/移除
├── boot.sh              开机自启（cron @reboot 调用）
├── watch.sh             看门狗（cron */5 调用）
├── config               运行时配置（端口/密钥/adblock 开关，install 时写入 repo= 仓库源）
├── CrashCore.tgz        内核缓存（9MB）
├── nodes.json           订阅导入后的节点片段
├── rules/               adblock.source.json + 编译出的 adblock.srs + CN srs
└── ui/                  zashboard 面板（已 sed 改写为本机 IP）
/tmp/SClite/            运行态（重启自动清空重建）
├── CrashCore            解压后的内核
└── fragments/           base.json + nodes.json（run -C 合并目录）
```

## 安装

前置：**先卸载官方 ShellCrash**（`crashtool uninstall` 或官方菜单），释放 /data 空间。

把本仓库推送到你的 GitHub 仓库（目录结构：`install.sh` + `files/crash` + `files/fw.sh` + `files/boot.sh` + `files/watch.sh`），然后：

**第 0 步：改仓库地址** —— 编辑 `install.sh` 顶部：

```sh
: "${REPO:=OWNER/REPO}"    # ← 改成 你的用户名/仓库名
```

**第 1 步：路由器上执行（已开 SSH）**

```sh
# 带订阅 URL 安装（国内下载失败就用 jsdelivr 版）
sh -c "$(curl -fsSL https://raw.githubusercontent.com/OWNER/REPO/main/install.sh)" "https://你的订阅地址"

# 或先装后导入
sh -c "$(curl -fsSL https://testingcf.jsdelivr.net/gh/OWNER/REPO@main/install.sh)"
sh /data/SClite/crash sub "https://你的订阅地址"
```

安装过程：下载 4 个脚本 → 内核/面板/广告规则 → 注册 cron 自启+看门狗 → 立即启动。全程无交互。

## 日常使用

```sh
sh /data/SClite/crash status        # 状态总览（面板地址/密钥/节点数/规则缓存）
sh /data/SClite/crash start|stop|restart
sh /data/SClite/crash sub "URL"     # 重新导入/更换订阅
sh /data/SClite/crash ads on|off|update   # 广告拦截开关/强制刷新
sh /data/SClite/crash update        # 强制重下内核/面板/规则
sh /data/SClite/crash scripts      # 从你的 GitHub 仓库拉最新脚本
sh /data/SClite/crash uninstall    # 完整卸载（cron/防火墙/文件）
```

面板（zashboard）里可以：切节点、切策略组、看流量、改全局/规则/直连模式。
订阅 URL 只能命令行导入（clash_api 只读），导入后面板全功能可用。

## 卸载后空间

`crash uninstall` 会删除 `/data/SClite`、`/tmp/SClite` 与 cron 条目，
恢复约 17MB 闪存。

## 已知限制 / 注意事项

1. **首次部署务必在路由器上验证**：`sh -n` 语法检查、base.json+nodes.json 合并、
   ApolloRioo JSON 编译 srs（1.13.14 内核 `rule-set compile`，v4 失败自动回退 v3）。
2. 广告拦截在 **route 层**（命中 REJECT 出站），不是 DNS 层 block server
   （sing-box 1.13.14 兼容性不确定，故未采用）。
3. AnyTLS 节点 sing-box 不支持，订阅里有会被 subconverter 跳过
   （同一批服务器的 vless/hysteria2/tuic 节点通常已覆盖）。
4. 面板密钥每次安装随机生成，查看：`sh /data/SClite/crash status`。
5. 小米自带广告过滤仍保留，作为 sing-box 之外的兜底。
6. MiWiFi 重启后 /etc 重置，但 `/etc/crontabs/root` 持久，自启靠它；
   boot.sh 会等待 WAN 拿到 IP（最长 120s）后再拉内核。

## 上游

- 内核/面板/CN srs：juewuy/ShellCrash（GPL-3.0）
- 广告规则：ApolloRioo/AdBlock_Rule_For_Sing-box
- 订阅转换：subconverter 公共实例（api.v1.mk / sub.jwsc.eu.org / url.v1.mk）
