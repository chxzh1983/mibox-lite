#!/bin/sh
# mibox-lite fw.sh — iptables 注入 (LAN 透明代理 + DNS 劫持)
# 由 ShellCrash fw_iptables/fw_stop 裁剪, MiWiFi AX3600 场景
# 用法: sh fw.sh {start|stop|status}

SCDIR=/data/SClite
CFG=$SCDIR/config
[ -f "$CFG" ] && . "$CFG" 2>/dev/null
[ -z "$mix_port" ] && mix_port=7890
[ -z "$redir_port" ] && redir_port=7892
[ -z "$dns_port" ] && dns_port=1053
[ -z "$db_port" ] && db_port=9999
[ -z "$self_proxy" ] && self_proxy=OFF
[ -z "$dns_hijack" ] && dns_hijack=ON

IPT="iptables -w"
command -v iptables >/dev/null 2>&1 || { echo "无 iptables"; exit 1; }

# LAN 源网段 (RFC1918, 动态, 不依赖接口名)
LAN_NETS="192.168.0.0/16 10.0.0.0/8 172.16.0.0/12"
MARK=255   # 必须与 sing-box 配置 default_mark 一致, 防代理流量回环

start_fw() {
    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
    # 幂等: 先清掉本工具自己加的规则, 再重建
    for c in mibox mibox_dns mibox_out; do
        for net in $LAN_NETS; do
            $IPT -t nat -D PREROUTING -s $net -p tcp -j $c 2>/dev/null
            $IPT -t nat -D PREROUTING -s $net -p udp -j $c 2>/dev/null
        done
        $IPT -t nat -D OUTPUT -o lo -p tcp -j $c 2>/dev/null
        $IPT -t nat -D OUTPUT -o lo -p udp -j $c 2>/dev/null
        $IPT -t nat -F $c 2>/dev/null
    done
    $IPT -t nat -D OUTPUT -o lo -p udp --dport 53 -j mibox_dns 2>/dev/null
    wan_if=$(ip route 2>/dev/null | grep '^default' | awk '{print $5}' | head -n1)
    [ -n "$wan_if" ] && {
        $IPT -t filter -D INPUT -i $wan_if -p udp --dport 53 -j REJECT 2>/dev/null
        $IPT -t filter -D INPUT -i $wan_if -p tcp --dport 53 -j REJECT 2>/dev/null
    }
    # 主链
    $IPT -t nat -N mibox 2>/dev/null
    for net in $LAN_NETS; do
        $IPT -t nat -I PREROUTING -s $net -p tcp -j mibox 2>/dev/null
        $IPT -t nat -I PREROUTING -s $net -p udp -j mibox 2>/dev/null
    done
    # 防回环: sing-box 打 mark 的流量直接返回
    $IPT -t nat -A mibox -m mark --mark $MARK -j RETURN 2>/dev/null
    # 目标为局域网的地址不进代理 (否则面板/SSH/米家设备会被劫走)
    $IPT -t nat -A mibox -d 192.168.0.0/16 -j RETURN 2>/dev/null
    $IPT -t nat -A mibox -d 10.0.0.0/8 -j RETURN 2>/dev/null
    $IPT -t nat -A mibox -d 172.16.0.0/12 -j RETURN 2>/dev/null
    # 面板/代理自身端口除外
    $IPT -t nat -A mibox -p tcp --dport "$db_port" -j RETURN 2>/dev/null
    $IPT -t nat -A mibox -p tcp --dport "$mix_port" -j RETURN 2>/dev/null
    # fake-ip 段必须重新进代理
    $IPT -t nat -A mibox -d 198.18.0.0/15 -j REDIRECT --to-ports "$redir_port" 2>/dev/null
    # 其余 LAN 流量 -> redirect-in
    $IPT -t nat -A mibox -j REDIRECT --to-ports "$redir_port" 2>/dev/null

    # 本机流量 (可选)
    if [ "$self_proxy" = ON ]; then
        $IPT -t nat -N mibox_out 2>/dev/null
        $IPT -t nat -I OUTPUT -o lo -j mibox_out 2>/dev/null
        $IPT -t nat -A mibox_out -m mark --mark $MARK -j RETURN 2>/dev/null
        $IPT -t nat -A mibox_out -p tcp --dport "$db_port" -j RETURN 2>/dev/null
        $IPT -t nat -A mibox_out -p tcp --dport "$mix_port" -j RETURN 2>/dev/null
        $IPT -t nat -A mibox_out -d 198.18.0.0/15 -j REDIRECT --to-ports "$redir_port" 2>/dev/null
        $IPT -t nat -A mibox_out -j REDIRECT --to-ports "$redir_port" 2>/dev/null
    fi

    # DNS 劫持: LAN 53 -> dns-in
    if [ "$dns_hijack" = ON ]; then
        $IPT -t nat -N mibox_dns 2>/dev/null
        for net in $LAN_NETS; do
            $IPT -t nat -I PREROUTING -s $net -p udp --dport 53 -j mibox_dns 2>/dev/null
            $IPT -t nat -I PREROUTING -s $net -p tcp --dport 53 -j mibox_dns 2>/dev/null
        done
        $IPT -t nat -A mibox_dns -j REDIRECT --to-ports "$dns_port" 2>/dev/null
        # 本机 DNS 也走 (lo)
        $IPT -t nat -I OUTPUT -o lo -p udp --dport 53 -j mibox_dns 2>/dev/null
        # 拒绝 WAN 侧外部 DNS 查询 (防绕过)
        wan_if=$(ip route 2>/dev/null | grep '^default' | awk '{print $5}' | head -n1)
        [ -n "$wan_if" ] && {
            $IPT -t filter -I INPUT -i $wan_if -p udp --dport 53 -j REJECT 2>/dev/null
            $IPT -t filter -I INPUT -i $wan_if -p tcp --dport 53 -j REJECT 2>/dev/null
        }
    fi
    echo "防火墙已注入 (LAN代理$([ "$self_proxy" = ON ] && echo '+本机') + DNS劫持$([ "$dns_hijack" = ON ] && echo 开 || echo 关))"
    return 0
}

stop_fw() {
    for c in mibox mibox_dns mibox_out; do
        $IPT -t nat -D PREROUTING -i br-0 -p tcp -j $c 2>/dev/null
        for net in $LAN_NETS; do
            $IPT -t nat -D PREROUTING -s $net -p tcp -j $c 2>/dev/null
            $IPT -t nat -D PREROUTING -s $net -p udp -j $c 2>/dev/null
        done
        $IPT -t nat -D OUTPUT -o lo -p tcp -j $c 2>/dev/null
        $IPT -t nat -F $c 2>/dev/null
        $IPT -t nat -X $c 2>/dev/null
    done
    $IPT -t nat -D OUTPUT -o lo -p udp --dport 53 -j mibox_dns 2>/dev/null
    wan_if=$(ip route 2>/dev/null | grep '^default' | awk '{print $5}' | head -n1)
    [ -n "$wan_if" ] && {
        $IPT -t filter -D INPUT -i $wan_if -p udp --dport 53 -j REJECT 2>/dev/null
        $IPT -t filter -D INPUT -i $wan_if -p tcp --dport 53 -j REJECT 2>/dev/null
    }
    echo "防火墙已清理"
    return 0
}

case "${1:-status}" in
    start) start_fw ;;
    stop) stop_fw ;;
    status)
        echo "mibox nat 规则: $($IPT -t nat -S mibox 2>/dev/null | grep -c mibox) 条"
        echo "内核: $(pidof CrashCore >/dev/null 2>&1 && echo 运行中 || echo 停止)"
        ;;
    *) echo "用法: sh fw.sh {start|stop|status}";;
esac
