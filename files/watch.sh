#!/bin/sh
# mibox-lite watch.sh — 看门狗 (由 crontab 每 5 分钟调用, 安装时注册到 /etc/crontabs/root)
# 职责: 内核掉线 → 自动重启; 闪存资源被 OTA 清掉 → 重装; 120s 冷却防风暴。
# 注意: 代理节点全挂时内核不会退出 (走 final 兜底直连), 本看门狗只处理"进程死亡"场景。

SCDIR=/data/SClite
[ -d "$SCDIR" ] || exit 0

# 用户手动停止 (.stopped) → 不拉起
[ -f "$SCDIR/.stopped" ] && exit 0

# 内核在跑 → 无事
pidof CrashCore >/dev/null 2>&1 && exit 0

# 冷却: 距上次尝试超过 120s 才重启
now=$(date +%s 2>/dev/null || echo 0)
last=$(cat "$SCDIR/.wd_last" 2>/dev/null || echo 0)
if [ "$now" -gt 0 ] && [ $((now - last)) -lt 120 ]; then
    exit 0
fi
echo "$now" > "$SCDIR/.wd_last" 2>/dev/null

# 内核包被清 (小米 OTA 会清 /data 部分文件) → 重装资源
if [ ! -f "$SCDIR/CrashCore.tgz" ]; then
    sh "$SCDIR/crash" install-prepare >/dev/null 2>&1
fi

# 重新注入防火墙 + 拉内核 (代理挂时 fw 保持, 流量 final=DIRECT 直连兜底)
sh "$SCDIR/fw.sh" start >/dev/null 2>&1
sh "$SCDIR/crash" service-rebuild >/dev/null 2>&1
exit 0
