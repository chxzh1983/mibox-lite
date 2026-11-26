#!/bin/sh
# mibox-lite boot.sh — 开机自启
# 由 install.sh 写入 cron @reboot:  等 45s (WAN 拨号就绪) → 运行本脚本。
# 职责: 等 WAN 有 IP → 补注册看门狗 cron → 启动 (crash start 做资源解压+配置生成+内核启动)

SCDIR=/data/SClite
[ -d "$SCDIR" ] || exit 0
[ -f "$SCDIR/.stopped" ] && exit 0   # 用户手动停止过, 不自动拉起

# 1) 等 WAN 口有出口 IP (最长 120s)
i=0
while [ "$i" -lt 24 ]; do
    wan_ip=$(ip route 2>/dev/null | grep '^default' | grep -oE 'via [0-9.]+' | awk '{print $2}' | head -n1)
    [ -n "$wan_ip" ] && break
    sleep 5; i=$((i+1))
done
# 无 WAN 也不阻塞, 看门狗 cron 稍后重试

# 2) 自注册看门狗 cron (双保险: 重启后 cron 若被清, 每次开机补回)
crondir() {
    d=$(crond -h 2>&1 | grep -oE 'Default:.*' | awk -F ':' '{print $2}' | tr -d ' ')
    [ -w "$d" ] && { echo "$d"; return; }
    for c in /etc/crontabs /data/etc/crontabs /etc/storage/cron/crontabs /var/spool/cron; do
        [ -w "$c" ] && { echo "$c"; return; }
    done
    return 1
}
reg_cron() {
    if command -v crontab >/dev/null 2>&1; then
        crontab -l 2>/dev/null | grep -q 'SClite/watch.sh' || \
            { ( crontab -l 2>/dev/null
                echo '*/5 * * * * [ -x /data/SClite/crash ] && sh /data/SClite/watch.sh >/dev/null 2>&1 #mibox-lite'
              ) | crontab - 2>/dev/null; }
        return 0
    fi
    cd=$(crondir) || return 0
    [ -f "$cd/root" ] && grep -q 'SClite/watch.sh' "$cd/root" && return 0
    { grep -v 'SClite/watch.sh' "$cd/root" 2>/dev/null
      echo '*/5 * * * * [ -x /data/SClite/crash ] && sh /data/SClite/watch.sh >/dev/null 2>&1 #mibox-lite'
    } > /tmp/sc_cron && cat /tmp/sc_cron > "$cd/root"; rm -f /tmp/sc_cron
}
reg_cron

# 3) 启动
sh "$SCDIR/crash" start >/dev/null 2>&1
exit 0
