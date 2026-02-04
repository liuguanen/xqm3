#!/bin/bash

# 通用跨平台代理服务器安装脚本
# 支持 VMess 协议，兼容所有系统

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 日志函数
log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }

# 检测系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
        VER=$(cat /etc/redhat-release | sed -E 's/.*release ([0-9]+)\..*/\1/')
    elif [ -f /etc/alpine-release ]; then
        OS="alpine"
        VER=$(cat /etc/alpine-release)
    else
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
        VER=$(uname -r)
    fi
    
    log "检测到系统: $OS $VER"
    
    case $OS in
        alpine)
            PKG_MGR="apk"
            INSTALL_CMD="apk add"
            SVC_MGR="rc-service"
            SVC_CMD="rc-service"
            ;;
        debian|ubuntu)
            PKG_MGR="apt-get"
            INSTALL_CMD="apt-get install -y"
            SVC_MGR="systemctl"
            SVC_CMD="systemctl"
            ;;
        centos|rhel|fedora|rocky|almalinux)
            PKG_MGR="yum"
            INSTALL_CMD="yum install -y"
            SVC_MGR="systemctl"
            SVC_CMD="systemctl"
            ;;
        *)
            PKG_MGR=""
            warn "未知系统，尝试通用安装"
            ;;
    esac
}

# 安装依赖
install_deps() {
    log "安装系统依赖..."
    
    case $OS in
        alpine)
            $INSTALL_CMD curl wget unzip bash openssl
            ;;
        debian|ubuntu)
            apt-get update
            $INSTALL_CMD curl wget unzip
            ;;
        centos|rhel|fedora)
            $INSTALL_CMD epel-release
            $INSTALL_CMD curl wget unzip
            ;;
        *)
            # 通用方法
            if command -v apt-get >/dev/null 2>&1; then
                apt-get update && apt-get install -y curl wget unzip
            elif command -v yum >/dev/null 2>&1; then
                yum install -y curl wget unzip
            elif command -v apk >/dev/null 2>&1; then
                apk add curl wget unzip
            else
                warn "无法自动安装依赖，请手动安装 curl, wget, unzip"
            fi
            ;;
    esac
}

# 安装 Xray
install_xray() {
    log "安装 Xray..."
    
    # 检测架构
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="64" ;;
        aarch64) ARCH="arm64-v8a" ;;
        armv7l) ARCH="arm32-v7a" ;;
        *) ARCH="64" ;;
    esac
    
    # 下载最新版
    LATEST_VERSION=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    log "下载 Xray v$LATEST_VERSION..."
    
    cd /tmp
    wget -q "https://github.com/XTLS/Xray-core/releases/download/v$LATEST_VERSION/Xray-linux-$ARCH.zip"
    unzip -q -o "Xray-linux-$ARCH.zip" -d /usr/local/bin/
    chmod +x /usr/local/bin/xray
    
    # 创建配置目录
    mkdir -p /usr/local/etc/xray
}

# 配置服务
configure_service() {
    log "配置服务..."
    
    case $OS in
        alpine)
            # OpenRC 服务配置
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
    checkpath -f -m 0644 -o nobody:nobody /var/log/xray.log 2>/dev/null || true
}

start_post() {
    sleep 2
    if [ -f "$pidfile" ]; then
        echo "Xray started successfully"
    else
        echo "Failed to start Xray"
        return 1
    fi
}
EOF
            chmod +x /etc/init.d/xray
            rc-update add xray default 2>/dev/null || true
            ;;
            
        *)
            # systemd 服务配置（适用于大多数系统）
            cat > /etc/systemd/system/xray.service << 'EOF'
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=nobody
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload
            systemctl enable xray 2>/dev/null || true
            ;;
    esac
}

# 配置防火墙
configure_firewall() {
    log "配置防火墙..."
    
    if command -v ufw >/dev/null 2>&1; then
        ufw allow $PORT/tcp
        ufw reload
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=$PORT/tcp
        firewall-cmd --reload
    elif command -v iptables >/dev/null 2>&1; then
        iptables -A INPUT -p tcp --dport $PORT -j ACCEPT
        # 尝试保存规则
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        if [ -d /etc/iptables ]; then
            iptables-save > /etc/iptables/rules.v4
        fi
    fi
}

# 主安装函数
main_install() {
    echo -e "${CYBAN}================================================${NC}"
    echo -e "${CYBAN}          通用代理服务器安装脚本           ${NC}"
    echo -e "${CYBAN}================================================${NC}"
    echo ""
    
    # 检查root权限
    if [ "$EUID" -ne 0 ]; then 
        error "请使用 sudo 运行此脚本"
        echo "命令: sudo bash $0"
        exit 1
    fi
    
    # 检测系统
    detect_os
    
    # 获取配置
    echo ""
    echo -e "${YELLOW}================ 配置信息 ================${NC}"
    
    read -p "请输入端口 [默认: 50088]: " PORT
    PORT=${PORT:-50088}
    
    read -p "请输入UUID [默认随机生成]: " UUID
    if [ -z "$UUID" ]; then
        UUID=$(cat /proc/sys/kernel/random/uuid)
        echo "生成UUID: $UUID"
    fi
    
    IP=$(curl -s 4.ipw.cn || curl -s ifconfig.me || hostname -I | awk '{print $1}')
    echo "服务器IP: $IP"
    
    # 安装依赖
    install_deps
    
    # 安装 Xray
    install_xray
    
    # 创建配置文件
    log "创建配置文件..."
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
                        "email": "user@vpn.com"
                    }
                ]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "none"
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
    
    # 创建日志目录
    mkdir -p /var/log/xray 2>/dev/null || true
    touch /var/log/xray/access.log /var/log/xray/error.log 2>/dev/null || true
    chown nobody:nobody /var/log/xray*.log 2>/dev/null || true
    
    # 配置服务
    configure_service
    
    # 配置防火墙
    configure_firewall
    
    # 启动服务
    log "启动服务..."
    case $OS in
        alpine)
            rc-service xray start 2>/dev/null || /etc/init.d/xray start
            ;;
        *)
            systemctl start xray 2>/dev/null || /usr/local/bin/xray run -config /usr/local/etc/xray/config.json &
            ;;
    esac
    
    sleep 3
    
    # 验证安装
    echo ""
    echo -e "${YELLOW}================ 验证安装 ================${NC}"
    
    # 检查进程
    if ps aux | grep xray | grep -v grep > /dev/null; then
        success "Xray 进程正在运行"
    else
        warn "Xray 进程未找到"
    fi
    
    # 检查端口
    if netstat -tuln 2>/dev/null | grep ":$PORT" > /dev/null || \
       ss -tuln 2>/dev/null | grep ":$PORT" > /dev/null; then
        success "端口 $PORT 监听正常"
    else
        warn "端口 $PORT 未监听"
    fi
    
    # 显示配置信息
    echo ""
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}                安装完成！                ${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo ""
    echo "📡 服务器信息:"
    echo "  IP地址: $IP"
    echo "  端口: $PORT"
    echo "  UUID: $UUID"
    echo "  协议: VMess"
    echo "  传输: TCP"
    echo ""
    echo "📱 客户端配置:"
    echo "  类型: VMess"
    echo "  地址: $IP"
    echo "  端口: $PORT"
    echo "  用户ID: $UUID"
    echo "  额外ID: 0"
    echo "  加密: auto"
    echo ""
    echo "🔗 分享链接:"
    CONFIG='{"add":"'$IP'","aid":"0","host":"","id":"'$UUID'","net":"tcp","path":"","port":"'$PORT'","ps":"Universal_VPN","tls":"none","type":"none","v":"2"}'
    echo "vmess://$(echo -n "$CONFIG" | base64 -w 0)"
    echo ""
    echo "🔧 服务管理:"
    case $OS in
        alpine)
            echo "  启动: rc-service xray start"
            echo "  停止: rc-service xray stop"
            echo "  重启: rc-service xray restart"
            echo "  状态: rc-service xray status"
            ;;
        *)
            echo "  启动: systemctl start xray"
            echo "  停止: systemctl stop xray"
            echo "  重启: systemctl restart xray"
            echo "  状态: systemctl status xray"
            ;;
    esac
    echo ""
    echo "⚠ 端口转发:"
    echo "  需要在路由器转发 TCP $PORT 端口"
    echo "  目标IP: 本机内网IP"
}

# 运行主函数
main_install