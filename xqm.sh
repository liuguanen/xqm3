#!/bin/bash

# Xray-core 一键安装脚本
# 100% 能工作，支持 Hiddify

set -e

echo "========================================================"
echo "          Xray-core (VMess) 一键安装脚本"
echo "========================================================"

# 安装依赖
apt-get update -y
apt-get install -y curl wget unzip

# 安装 Xray
echo "安装 Xray-core..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# 获取配置
PUBLIC_IP=$(curl -s 4.ipw.cn)
echo "服务器IP: $PUBLIC_IP"

read -p "请输入端口 [默认: 443]: " PORT
PORT=${PORT:-443}

read -p "请输入UUID [默认随机生成]: " UUID
if [ -z "$UUID" ]; then
    UUID=$(cat /proc/sys/kernel/random/uuid)
    echo "生成UUID: $UUID"
fi

# 创建 Xray 配置
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
                        "alterId": 0,
                        "email": "user@example.com"
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
        },
        {
            "protocol": "blackhole",
            "settings": {},
            "tag": "blocked"
        }
    ],
    "routing": {
        "rules": [
            {
                "type": "field",
                "ip": [
                    "geoip:private"
                ],
                "outboundTag": "blocked"
            }
        ]
    }
}
EOF

# 重启服务
systemctl restart xray
systemctl enable xray

# 配置防火墙
if command -v ufw >/dev/null 2>&1; then
    ufw allow $PORT/tcp
    ufw reload
else
    iptables -A INPUT -p tcp --dport $PORT -j ACCEPT
fi

sleep 3

echo ""
echo "========================================================"
echo "                   安装完成！"
echo "========================================================"
echo ""
echo "✅ 服务器地址: $PUBLIC_IP"
echo "✅ 端口: $PORT"
echo "✅ UUID: $UUID"
echo "✅ 加密: auto"
echo "✅ 传输协议: tcp"
echo "✅ 伪装类型: none"
echo ""
echo "📱 Hiddify 客户端配置:"
echo "1. 打开 Hiddify App"
echo "2. 点击右下角 + 号"
echo "3. 选择 '手动输入'"
echo "4. 类型选择 'VMess'"
echo "5. 填写以下信息:"
echo "   - 地址: $PUBLIC_IP"
echo "   - 端口: $PORT"
echo "   - 用户ID: $UUID"
echo "   - 额外ID: 0"
echo "   - 加密: auto"
echo "   - 传输协议: tcp"
echo ""
echo "🔗 VMess 链接:"
echo "vmess://$(echo -n '{"add":"'$PUBLIC_IP'","aid":"0","host":"","id":"'$UUID'","net":"tcp","path":"","port":"'$PORT'","ps":"Xray_Server","tls":"none","type":"none","v":"2"}' | base64 -w 0)"
echo ""
echo "🔧 服务管理:"
echo "启动: systemctl start xray"
echo "停止: systemctl stop xray"
echo "状态: systemctl status xray"
echo "日志: journalctl -u xray -f"
echo ""
echo "检查服务状态..."
if systemctl is-active --quiet xray; then
    echo "✅ Xray 服务运行正常"
    
    if netstat -tuln | grep ":$PORT" > /dev/null; then
        echo "✅ 端口 $PORT 监听正常"
    else
        echo "⚠ 端口未监听，但服务在运行"
    fi
else
    echo "❌ 服务未运行"
    echo "尝试重启: systemctl restart xray"
fi

echo ""
read -p "按回车键退出..."