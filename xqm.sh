#!/bin/sh

# Alpine Linux Xray 一键安装脚本
# 适用于 Alpine Linux (使用 openrc)

echo "=================================================="
echo "      Alpine Linux Xray (VMess) 一键安装脚本"
echo "=================================================="

# 1. 更新系统
echo "[1/12] 更新系统..."
apk update

# 2. 安装依赖
echo "[2/12] 安装依赖..."
apk add curl wget unzip bash openssl iptables

# 3. 获取最新版本
echo "[3/12] 获取Xray最新版本..."
LATEST_VERSION=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
echo "检测到最新版本: v$LATEST_VERSION"

# 4. 检测架构
ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH="64" ;;
    aarch64) ARCH="arm64-v8a" ;;
    armv7l) ARCH="arm32-v7a" ;;
    *) ARCH="64" ;;
esac
echo "系统架构: $ARCH"

# 5. 下载Xray
echo "[4/12] 下载Xray..."
cd /tmp
wget -q "https://github.com/XTLS/Xray-core/releases/download/v$LATEST_VERSION/Xray-linux-$ARCH.zip"

# 6. 安装Xray
echo "[5/12] 安装Xray..."
unzip -q -o "Xray-linux-$ARCH.zip" -d /usr/local/bin/
chmod +x /usr/local/bin/xray

# 7. 配置信息
echo ""
echo "================ 配置信息 ================"
read -p "请输入端口 [默认: 50088]: " PORT
PORT=${PORT:-50088}

UUID=$(cat /proc/sys/kernel/random/uuid)
IP=$(curl -s 4.ipw.cn)
echo "服务器IP: $IP"
echo "自动生成UUID: $UUID"

# 8. 创建配置文件
echo "[6/12] 创建配置文件..."
mkdir -p /usr/local/etc/xray
cat > /usr/local/etc/xray/config.json << EOF
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "port": $PORT,
            "protocol": "vmess",
            "settings": {
                "clients": [
                    {
                        "id": "$UUID",
                        "alterId": 0
                    }
                ]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "none",
                "tcpSettings": {
                    "header": {
                        "type": "none"
                    }
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "settings": {}
        }
    ]
}
EOF

# 9. 创建openrc启动脚本
echo "[7/12] 创建启动脚本..."
cat > /etc/init.d/xray << 'EOF'
#!/sbin/openrc-run

name="Xray Proxy Server"
description="Xray Proxy Service"

command="/usr/local/bin/xray"
command_args="run -config /usr/local/etc/xray/config.json"
command_user="nobody:nobody"
pidfile="/var/run/xray.pid"
command_background=true

depend() {
    need net
    after firewall
}

start_pre() {
    checkpath -f -m 0644 -o nobody:nobody /var/log/xray.log
}

start_post() {
    sleep 2
    if [ -f "$pidfile" ]; then
        echo "✓ Xray 启动成功"
    else
        echo "✗ Xray 启动失败"
        return 1
    fi
}
EOF

chmod +x /etc/init.d/xray

# 10. 添加开机启动
echo "[8/12] 设置开机启动..."
rc-update add xray default 2>/dev/null || true

# 11. 启动服务
echo "[9/12] 启动服务..."
rc-service xray start

# 12. 配置防火墙
echo "[10/12] 配置防火墙..."
iptables -A INPUT -p tcp --dport $PORT -j ACCEPT
iptables-save > /etc/iptables/rules.v4 2>/dev/null || true

# 等待服务启动
echo "[11/12] 等待服务启动..."
sleep 5

# 13. 验证安装
echo "[12/12] 验证安装..."
echo ""
echo "检查服务状态:"
rc-service xray status

echo ""
echo "检查端口监听:"
if netstat -tuln 2>/dev/null | grep ":$PORT" > /dev/null; then
    echo "✓ 端口 $PORT 监听正常"
else
    echo "⚠ 端口未监听，尝试手动检查:"
    ps aux | grep xray | grep -v grep
fi

# 14. 显示配置信息
echo ""
echo "=================================================="
echo "                安装完成！"
echo "=================================================="
echo ""
echo "📡 服务器信息:"
echo "  IP地址: $IP"
echo "  端口: $PORT"
echo "  UUID: $UUID"
echo "  加密: auto"
echo "  传输协议: TCP"
echo "  伪装类型: none"
echo ""
echo "📱 Hiddify 客户端配置:"
echo "  1. 打开 Hiddify App"
echo "  2. 点击右下角 + 号"
echo "  3. 选择 '手动输入'"
echo "  4. 类型选择 'VMess'"
echo "  5. 填写以下信息:"
echo "     - 地址: $IP"
echo "     - 端口: $PORT"
echo "     - 用户ID: $UUID"
echo "     - 额外ID: 0"
echo "     - 加密: auto"
echo "     - 传输协议: tcp"
echo ""
echo "🔗 VMess 分享链接:"
VMESS_CONFIG='{"add":"'$IP'","aid":"0","host":"","id":"'$UUID'","net":"tcp","path":"","port":"'$PORT'","ps":"Alpine_Xray","tls":"none","type":"none","v":"2"}'
echo "vmess://$(echo -n "$VMESS_CONFIG" | base64 -w 0)"
echo ""
echo "🔧 服务管理命令:"
echo "  启动: rc-service xray start"
echo "  停止: rc-service xray stop"
echo "  重启: rc-service xray restart"
echo "  状态: rc-service xray status"
echo "  开机禁用: rc-update del xray"
echo ""
echo "⚠ 端口转发提醒:"
echo "  需要在路由器中转发 TCP $PORT 端口"
echo "  目标IP: 本服务器的内网IP地址"
echo "=================================================="

# 15. 测试连接
echo ""
echo "测试连接中..."
sleep 2
if nc -z localhost $PORT 2>/dev/null; then
    echo "✅ 本地连接测试成功"
else
    echo "⚠ 本地连接测试失败"
fi