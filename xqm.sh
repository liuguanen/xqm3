#!/bin/bash

# Debian Xray 一键安装脚本

set -e

echo "================================================"
echo "          Debian Xray (VMess) 一键安装脚本"
echo "================================================"

# 检查root权限
if [ "$EUID" -ne 0 ]; then 
    echo "请使用 sudo 运行此脚本: sudo bash $0"
    exit 1
fi

# 1. 安装依赖
echo "[1/8] 安装依赖..."
apt-get update
apt-get install -y curl wget unzip

# 2. 安装Xray
echo "[2/8] 安装Xray..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# 3. 获取配置信息
echo ""
echo "================ 配置信息 ================"
read -p "请输入端口 [默认: 50088]: " PORT
PORT=${PORT:-50088}

read -p "请输入UUID [默认随机生成]: " UUID
if [ -z "$UUID" ]; then
    UUID=$(cat /proc/sys/kernel/random/uuid)
    echo "生成UUID: $UUID"
fi

IP=$(curl -s 4.ipw.cn)
echo "服务器IP: $IP"

# 4. 创建配置文件
echo "[3/8] 创建配置文件..."
mkdir -p /usr/local/etc/xray
cat > /usr/local/etc/xray/config.json << EOF
{
    "log": {
        "loglevel": "info",
        "access": "/var/log/xray/access.log",
        "error": "/var/log/xray/error.log"
    },
    "inbounds": [
        {
            "port": $PORT,
            "protocol": "vmess",
            "settings": {
                "clients": [
                    {
                        "id": "$UUID",
                        "alterId": 0,
                        "email": "user@xray.com"
                    }
                ],
                "disableInsecureEncryption": false
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

# 5. 创建日志目录
echo "[4/8] 创建日志目录..."
mkdir -p /var/log/xray
touch /var/log/xray/access.log
touch /var/log/xray/error.log
chown -R nobody:nogroup /var/log/xray
chmod -R 755 /var/log/xray

# 6. 配置防火墙
echo "[5/8] 配置防火墙..."
if command -v ufw >/dev/null 2>&1; then
    ufw allow $PORT/tcp
    ufw reload
elif command -v iptables >/dev/null 2>&1; then
    iptables -A INPUT -p tcp --dport $PORT -j ACCEPT
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
fi

# 7. 重启服务
echo "[6/8] 重启服务..."
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

# 8. 等待启动
echo "[7/8] 等待服务启动..."
sleep 5

# 9. 验证安装
echo "[8/8] 验证安装..."
echo ""
if systemctl is-active --quiet xray; then
    echo "✅ Xray 服务运行正常"
else
    echo "❌ Xray 服务未运行"
    systemctl status xray --no-pager
fi

if netstat -tuln 2>/dev/null | grep ":$PORT" > /dev/null || ss -tuln 2>/dev/null | grep ":$PORT" > /dev/null; then
    echo "✅ 端口 $PORT 监听正常"
else
    echo "⚠ 端口未监听"
fi

# 显示配置信息
echo ""
echo "================================================"
echo "                安装完成！"
echo "================================================"
echo ""
echo "📡 服务器信息:"
echo "  IP地址: $IP"
echo "  端口: $PORT"
echo "  UUID: $UUID"
echo "  加密: auto"
echo "  传输协议: TCP"
echo ""
echo "📱 Hiddify 客户端配置:"
echo "  类型: VMess"
echo "  地址: $IP"
echo "  端口: $PORT"
echo "  用户ID: $UUID"
echo "  额外ID: 0"
echo "  加密: auto"
echo "  传输协议: tcp"
echo ""
echo "🔗 VMess 分享链接:"
VMESS_CONFIG='{"add":"'$IP'","aid":"0","host":"","id":"'$UUID'","net":"tcp","path":"","port":"'$PORT'","ps":"Debian_Xray","tls":"none","type":"none","v":"2"}'
echo "vmess://$(echo -n "$VMESS_CONFIG" | base64 -w 0)"
echo ""
echo "🔧 服务管理命令:"
echo "  启动: systemctl start xray"
echo "  停止: systemctl stop xray"
echo "  重启: systemctl restart xray"
echo "  状态: systemctl status xray"
echo "  日志: journalctl -u xray -f"
echo ""
echo "📊 查看日志:"
echo "  访问日志: tail -f /var/log/xray/access.log"
echo "  错误日志: tail -f /var/log/xray/error.log"
echo ""
echo "⚠ 端口转发提醒:"
echo "  需要在路由器中转发 TCP $PORT 端口"
echo "================================================"

# 测试连接
echo ""
echo "测试连接中..."
if timeout 5 bash -c "echo > /dev/tcp/localhost/$PORT" 2>/dev/null; then
    echo "✅ 本地连接测试成功"
else
    echo "⚠ 本地连接测试失败"
fi