# mibox-lite 使用说明

小米 MiWiFi（AX3600）上的 sing-box 代理 + 广告拦截，一条命令安装，面板管理。

## 安装

1. 先卸载官方 ShellCrash（官方菜单 → 卸载），释放 /data 空间
2. SSH 登录路由器，执行：

```sh
sh -c "$(curl -fsSL https://testingcf.jsdelivr.net/gh/chxzh1983/mibox-lite@main/install.sh)" "你的订阅URL"
```

不带订阅 URL 也可以，装完再导入：

```sh
sh /data/SClite/crash sub "你的订阅URL"
```

安装成功后，终端会打印面板地址。

## 面板

浏览器打开（IP 和端口见 `crash status` 输出，默认 `http://192.168.31.1:9999/ui`，密钥同输出）。

面板里可以：切换节点、切换策略组、查看流量、改全局/规则/直连模式。
订阅 URL 只能通过命令导入，导入后面板全功能可用。

## 常用命令

```sh
sh /data/SClite/crash status          # 状态总览（内核/面板/节点/规则）
sh /data/SClite/crash start           # 启动
sh /data/SClite/crash stop           # 停止（看门狗不再拉起，重启路由后会自启）
sh /data/SClite/crash restart        # 重启
sh /data/SClite/crash sub "URL"      # 导入/更换订阅
sh /data/SClite/crash ads on|off     # 广告拦截开/关
sh /data/SClite/crash ads update     # 刷新广告规则
sh /data/SClite/crash update         # 重下内核/面板/规则（内核有新版本时）
sh /data/SClite/crash scripts        # 拉取本仓库最新脚本（GitHub 更新后同步到路由器）
sh /data/SClite/crash uninstall      # 完整卸载
```

## 行为说明

- **开机自启**：路由器重启后约 45 秒自动启动，无需操作
- **看门狗**：每 5 分钟巡检，内核挂掉自动拉起；`stop` 后不会拉起
- **广告拦截**：默认开启，命中广告域名的流量直接拒绝
- **CN 分流**：中国大陆网站直连，其余走订阅节点
- 未导入订阅时：final=直连，只有广告拦截生效

## 排错

- 装完打不开面板：`sh /data/SClite/crash status` 看密钥；确认面板地址 IP 是路由器 LAN IP
- 节点不通：面板里换节点；确认订阅有效（`crash sub "URL"` 重新导入）
- 想看内核日志：`cat /tmp/SClite/sb.log`
- 订阅导入失败：公共 subconverter 实例可能不可用，等几小时再试或 `ads update` 思路相同可重试
- 完全恢复原状：`sh /data/SClite/crash uninstall`
