#!/usr/bin/env bash

# =========================================================
# 项目名称：Xray + Nginx VLESS WS TLS 一键部署脚本
# 功能说明：
#   - 安装 Xray-core（VLESS + WebSocket）
#   - 安装 Nginx（TLS 443 反代）
#   - 手动导入 SSL 证书
#   - 自动生成 UUID
#   - 提供安装 / 卸载菜单
#
# 架构：
#   Client → Nginx(443 TLS) → WebSocket → Xray(127.0.0.1:17654)
#
# 优点：
#   - 流量伪装为 HTTPS
#   - Xray 不暴露公网端口
#   - 支持高并发 WebSocket
# =========================================================

set -e

# =========================================================
# 颜色定义（仅用于终端输出美化）
# =========================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# =========================================================
# Root 权限检查
# =========================================================
[[ $EUID -ne 0 ]] && echo -e "${RED}请使用 root 运行${NC}" && exit 1


# =========================================================
# 安装函数
# =========================================================
install_xray() {

echo -e "${GREEN}======================================"
echo " Xray VLESS WS TLS 自动安装"
echo -e "======================================${NC}"

# =========================================================
# 用户输入域名（用于 TLS + SNI + Host）
# =========================================================
read -rp "请输入域名: " DOMAIN

# =========================================================
# SSL 证书导入
# 注意：
#   必须是 PEM 格式：
#   -----BEGIN CERTIFICATE-----
# =========================================================
echo
echo -e "${YELLOW}请粘贴 TLS 证书内容（Ctrl+D 结束）${NC}"
mkdir -p /etc/ssl/private
cat > /etc/ssl/private/${DOMAIN}.crt

# =========================================================
# SSL 私钥导入
# 注意：
#   必须与证书匹配，否则 Nginx 无法启动
# =========================================================
echo
echo -e "${YELLOW}请粘贴 TLS 私钥内容（Ctrl+D 结束）${NC}"
cat > /etc/ssl/private/${DOMAIN}.key

# 私钥权限必须限制（防泄露）
chmod 600 /etc/ssl/private/${DOMAIN}.key


# =========================================================
# 安装系统依赖
# =========================================================
echo -e "${GREEN}安装基础依赖...${NC}"
apt update -y
apt install -y curl wget unzip nginx uuid-runtime


# =========================================================
# 安装 Xray-core
# 官方脚本自动安装 systemd 服务
# =========================================================
echo -e "${GREEN}安装 Xray-core...${NC}"
bash <(curl -Ls https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh)


# =========================================================
# 生成唯一用户 UUID（客户端身份标识）
# =========================================================
UUID=$(cat /proc/sys/kernel/random/uuid)


# =========================================================
# Xray 配置文件
# =========================================================
mkdir -p /usr/local/etc/xray

cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {

    // 日志级别说明：
    // warning：仅记录警告及错误（推荐生产环境）
    "loglevel": "warning"
  },

  "dns": {

    // DNS over HTTPS（防污染解析）
    "servers": [

      "https+local://1.1.1.1/dns-query",  // Cloudflare DNS
      "https+local://8.8.8.8/dns-query",  // Google DNS
      "https+local://9.9.9.9/dns-query",  // Quad9 DNS
      "localhost"                          // 本地解析
    ]
  },

  "inbounds": [

    {
      // 只监听本机（安全设计）
      // 外网不可直接访问 Xray
      "listen": "127.0.0.1",

      // Xray 内部端口（仅 Nginx 可访问）
      "port": 17654,

      // 使用 VLESS 协议（轻量无加密协议）
      "protocol": "vless",

      "settings": {

        "clients": [

          {
            // 客户端身份 ID
            "id": "$UUID"
          }
        ],

        // VLESS 必须 none（TLS 交给 Nginx）
        "decryption": "none"
      },

      "streamSettings": {

        // WebSocket 传输层
        "network": "ws",

        "wsSettings": {

          // WebSocket 路径（必须与 Nginx 一致）
          "path": "/stream",

          // 高并发优化
          "maxConcurrentStreams": 128
        }
      },

      "sniffing": {

        // 流量协议识别（用于分流/伪装）
        "enabled": true,

        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],

  "outbounds": [

    {
      // 正常出站（直连互联网）
      "protocol": "freedom",
      "tag": "direct"
    },

    {
      // 黑洞出口（丢弃流量）
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF


# =========================================================
# Nginx 配置（核心反代层）
# =========================================================
echo -e "${GREEN}配置 Nginx...${NC}"

rm -f /etc/nginx/sites-enabled/default

cat > /etc/nginx/conf.d/xray.conf <<EOF

# =========================================================
# HTTP → HTTPS 强制跳转
# =========================================================
server {
    listen 80;
    server_name ${DOMAIN};

    return 301 https://\$host\$request_uri;
}

# =========================================================
# HTTPS 主站 + WS 入口
# =========================================================
server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    # SSL 证书路径
    ssl_certificate /etc/ssl/private/${DOMAIN}.crt;
    ssl_certificate_key /etc/ssl/private/${DOMAIN}.key;

    # TLS 安全协议
    ssl_protocols TLSv1.2 TLSv1.3;

    # SSL 性能优化
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    # 加密套件
    ssl_ciphers HIGH:!aNULL:!MD5;

    # 伪装网站目录
    root /var/www/html;
    index index.html;

    # =====================================================
    # WebSocket 核心入口（/stream）
    # =====================================================
    location /stream {

        # 非 WebSocket 请求直接拒绝（减少扫描）
        if (\$http_upgrade != "websocket") {
            return 444;
        }

        # 转发到本地 Xray
        proxy_pass http://127.0.0.1:17654;

        # WebSocket 必须 HTTP/1.1
        proxy_http_version 1.1;

        # 升级协议头
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";

        # 原始请求信息透传
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # =================================================
        # 性能优化
        # =================================================

        # 禁用缓存（降低延迟）
        proxy_buffering off;
        proxy_request_buffering off;

        # WebSocket 长连接
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;

        # TCP 优化
        tcp_nodelay on;

        # 防止大请求阻塞 WS
        client_max_body_size 1m;

        # 后端连接超时
        proxy_connect_timeout 10s;

        # SSL session 复用（提升握手性能）
        proxy_ssl_session_reuse on;
    }
}
EOF


# =========================================================
# 伪装网站（防扫描）
# =========================================================
mkdir -p /var/www/html

cat > /var/www/html/index.html <<EOF
<html>
<head>
<title>Welcome</title>
</head>
<body>
<h1>nginx running</h1>
</body>
</html>
EOF


# =========================================================
# 配置检查
# =========================================================
echo -e "${GREEN}检查配置...${NC}"

nginx -t

# Xray 配置语法检查
/usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json


# =========================================================
# 启动服务
# =========================================================
systemctl enable nginx
systemctl restart nginx

systemctl enable xray
systemctl restart xray


# =========================================================
# 防火墙放行
# =========================================================
if command -v ufw >/dev/null 2>&1; then
    ufw allow 80/tcp || true
    ufw allow 443/tcp || true
fi


# =========================================================
# 生成客户端链接
# =========================================================
VLESS_LINK="vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=%2Fstream#${DOMAIN}"


# =========================================================
# 输出结果
# =========================================================
echo
echo -e "${GREEN}======================================"
echo " 安装完成"
echo -e "======================================${NC}"

echo -e "${YELLOW}域名:${NC} ${DOMAIN}"
echo -e "${YELLOW}UUID:${NC} ${UUID}"
echo -e "${YELLOW}端口:${NC} 443 (TLS)"
echo -e "${YELLOW}协议:${NC} VLESS + WS"
echo -e "${YELLOW}路径:${NC} /stream"

echo
echo -e "${GREEN}VLESS 链接:${NC}"
echo "${VLESS_LINK}"
}


# =========================================================
# 卸载函数（彻底清理）
# =========================================================
uninstall_xray() {

echo -e "${RED}开始卸载 Xray + Nginx...${NC}"

systemctl stop xray 2>/dev/null || true
systemctl disable xray 2>/dev/null || true

# 卸载 Xray-core
bash <(curl -Ls https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh) remove || true

systemctl stop nginx 2>/dev/null || true

# 清理配置
rm -rf /usr/local/etc/xray
rm -rf /usr/local/share/xray
rm -rf /var/log/xray

rm -f /etc/nginx/conf.d/xray.conf

# 清理网站
rm -rf /var/www/html/*

# 删除证书
rm -f /etc/ssl/private/*.crt
rm -f /etc/ssl/private/*.key

# 卸载 nginx
apt remove --purge -y nginx
apt autoremove -y

systemctl daemon-reload

echo -e "${GREEN}卸载完成${NC}"
}


# =========================================================
# 主菜单入口
# =========================================================
menu() {

echo
echo "======================================"
echo " 1. 安装 Xray VLESS WS TLS"
echo " 2. 卸载 Xray + Nginx"
echo "======================================"

read -rp "请选择: " num

case "$num" in
    1) install_xray ;;
    2) uninstall_xray ;;
    *) echo "输入错误" ;;
esac
}

# =========================================================
# 启动菜单
# =========================================================
menu
