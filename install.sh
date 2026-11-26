#!/bin/sh
# mibox-lite install.sh — 小米 MiWiFi (AX3600) 一键安装入口
# 用法 (路由器上执行, 需已开 SSH):
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/OWNER/REPO/main/install.sh)" "你的订阅URL(可省略)"
#   国内网络下载 GitHub 文件失败时:
#   sh -c "$(curl -fsSL https://testingcf.jsdelivr.net/gh/OWNER/REPO@main/install.sh)" "你的订阅URL(可省略)"
#
# 前置: 先卸载官方 ShellCrash (crashtool uninstall / 官方菜单), 释放 /data 空间
# 自启模型: cron @reboot (MiWiFi 持久 /etc/crontabs/root, 官方 ShellCrash 保守模式同款),
#           看门狗 cron */5. 不用 UCI/procd (procd respawn 会循环重拉一次性脚本).

# ======== 改成你自己的 用户名/仓库名 (也可用 env REPO 覆盖) ========
: "${REPO:=OWNER/REPO}"
: "${BRANCH:=main}"
# ==============================================================

SCDIR=/data/SClite

log()  { printf '\033[32m[mibox-lite]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[mibox-lite]\033[0m 警告: %s\033[0m\n' "$*"; }
die()  { printf '\033[31m[mibox-lite] 错误: %s\033[0m\n' "$*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || die "缺少 curl/wget"

# --- 环境检查: MiWiFi ---
[ -d /data ] || die "未检测到 /data 目录, 这不是 MiWiFi 固件"
[ -w /data ] || die "/data 不可写"
[ -d /data/clash ] && warn "检测到官方 ShellCrash 目录 /data/clash, 建议先卸载"

# --- 取文件 (jsdelivr -> ghproxy -> raw 依次尝试) ---
fetch() { # $1=仓库相对路径 $2=本地输出
    f=$1; out=$2
    for base in \
        "https://testingcf.jsdelivr.net/gh/$REPO@$BRANCH/$f" \
        "https://ghproxy.com/https://raw.githubusercontent.com/$REPO/$BRANCH/$f" \
        "https://raw.githubusercontent.com/$REPO/$BRANCH/$f"; do
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL --connect-timeout 20 -o "$out" "$base" && return 0
        else
            wget -q -T 20 -O "$out" "$base" && return 0
        fi
        rm -f "$out" 2>/dev/null
    done
    return 1
}

log "开始安装, 仓库: $REPO@$BRANCH"
mkdir -p "$SCDIR/configs" || die "创建 $SCDIR 失败"

i=0
for f in crash fw.sh boot.sh watch.sh; do
    fetch "files/$f" "$SCDIR/$f" || die "下载 files/$f 失败, 请检查网络或将 REPO 改为你的仓库"
    i=$((i+1))
done
log "脚本已就位 ($i/4)"
# 语法自检 (sh -n, 只检查不执行)
for f in crash fw.sh boot.sh watch.sh; do
    sh -n "$SCDIR/$f" || die "$f 语法检查未通过, 中止安装"
done

# --- 写入 repo 源 (crash scripts 自更新脚本用) ---
echo "repo='https://raw.githubusercontent.com/$REPO/$BRANCH'" > "$SCDIR/config"

# --- 下载内核/面板/广告列表, 编译广告 srs ---
sh "$SCDIR/crash" install-prepare || die "资源下载失败"

# --- cron 目录探测 (与 ShellCrash 同款: crond -h 读 Default 目录) ---
crondir() {
    d=$(crond -h 2>&1 | grep -oE 'Default:.*' | awk -F ':' '{print $2}' | tr -d ' ')
    [ -n "$d" ] && [ -w "$d" ] && { echo "$d"; return 0; }
    for c in /etc/crontabs /data/etc/crontabs /etc/storage/cron/crontabs /var/spool/cron; do
        [ -w "$c" ] && { echo "$c"; return 0; }
    done
    return 1
}
cd=$(crondir) || { warn "未找到可写 crontab 目录"; }

# --- 自启 + 看门狗 cron (写 crontabs/root 持久文件) ---
if [ -n "$cd" ]; then
    grep -v 'SClite' "$cd/root" > /tmp/sc_cron 2>/dev/null
    echo "@reboot sleep 45 && sh $SCDIR/boot.sh >/dev/null 2>&1 #mibox-lite" >> /tmp/sc_cron
    echo '*/5 * * * * [ -x /data/SClite/crash ] && sh /data/SClite/watch.sh >/dev/null 2>&1 #mibox-lite' >> /tmp/sc_cron
    cat /tmp/sc_cron > "$cd/root"; rm -f /tmp/sc_cron
    log "cron 已注册: @reboot 自启 + */5 看门狗 ($cd/root)"
    # 立即生效 (crond 可能不热加载 crontab 文件)
    [ -x /etc/init.d/cron ] && /etc/init.d/cron restart >/dev/null 2>&1 || true
else
    warn "看门狗/自启未注册, 重启后需手动: sh $SCDIR/crash start"
fi

# --- 立即启动 ---
sh "$SCDIR/crash" start || warn "首次启动未完成, 请稍后执行: sh $SCDIR/crash start"

# --- 可选: 直接带订阅 URL 安装 ---
if [ -n "$1" ]; then
    log "导入订阅: $1"
    sh "$SCDIR/crash" sub "$1" || warn "订阅导入失败, 稍后可执行: sh $SCDIR/crash sub \"URL\""
fi

log "安装完成!"
log "面板: http://192.168.31.1:9999/ui   (密钥见: sh /data/SClite/crash status)"
log "常用命令: sh /data/SClite/crash {status|start|stop|sub URL|ads|update|scripts|uninstall}"
exit 0
