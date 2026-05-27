#!/usr/bin/env bash

# =========================================================
# XRAY PRODUCTION INSTALL SCRIPT
# 功能：
# - 自动安装 Xray + Nginx
# - VLESS + WebSocket + TLS
# - 动态 WS Path（防扫描）
# - 企业级 Nginx TLS 优化
# - 伪装站点
# - 自动节点输出
# - 全系统兼容（Debian / Ubuntu / CentOS / Fedora / Rocky）
# =========================================================

set -e

# =========================
# 全局配置路径
# =========================
CONFIG_FILE="/usr/local/etc/xray/config.json"
NGINX_FILE="/etc/nginx/conf.d/xray.conf"

# =========================================================
# UI：Logo 输出（纯终端界面）
# =========================================================
show_logo() {

clear

echo "=================================================="
echo "        XRAY INSTALLATION PANEL"
echo "        VLESS + WS + TLS DEPLOY TOOL"
echo "=================================================="
echo
echo "System : $(uname -s) $(uname -m)"
echo "Kernel : $(uname -r)"
echo
echo "=================================================="
echo
}

# =========================================================
# 系统检测（核心兼容模块）
# 作用：
# - 自动识别 Linux 发行版
# - 选择对应包管理器
# =========================================================
detect_os() {

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Cannot detect OS"
    exit 1
fi

case "$OS" in

# Debian / Ubuntu 系列
ubuntu|debian)
    PM="apt"
    INSTALL="apt install -y"
    UPDATE="apt update -y"
    ;;

# CentOS / Rocky / AlmaLinux / RHEL
centos|rocky|almalinux|rhel|ol)
    PM="yum"
    command -v dnf >/dev/null && INSTALL="dnf install -y" || INSTALL="yum install -y"
    UPDATE="yum makecache || dnf makecache"
    ;;

# Fedora 系列
fedora)
    PM="dnf"
    INSTALL="dnf install -y"
    UPDATE="dnf makecache"
    ;;

# 不支持系统直接退出
*)
    echo "Unsupported OS: $OS"
    exit 1
    ;;
esac
}

# =========================================================
# 动态 WebSocket 路径生成（防扫描核心）
# =========================================================
gen_ws_path() {

# 随机生成 10~12 位路径
WS_PATH="/$(head /dev/urandom | tr -dc a-z0-9 | head -c 12)"
}

# =========================================================
# 依赖安装模块
# =========================================================
install_deps() {

echo "[+] Installing system dependencies..."

$UPDATE

# 安装基础依赖（失败不影响流程，做兼容处理）
$INSTALL curl wget unzip nginx ca-certificates openssl || true
}

# =========================================================
# Xray 安装模块
# =========================================================
install_xray() {

echo "[+] Installing Xray core..."

# 官方安装脚本（失败直接退出）
if ! bash <(curl -Ls https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh); then
    echo "[ERROR] Xray installation failed"
    exit 1
fi
}

# =========================================================
# TLS 证书输入模块（手动粘贴）
# =========================================================
tls_input() {

read -rp "Domain: " DOMAIN

mkdir -p /etc/ssl/private

echo "Paste CRT (Ctrl+D to finish):"
cat > /etc/ssl/private/${DOMAIN}.crt

echo "Paste KEY (Ctrl+D to finish):"
cat > /etc/ssl/private/${DOMAIN}.key

# 保护私钥权限
chmod 600 /etc/ssl/private/${DOMAIN}.key
}

# =========================================================
# Xray 配置生成（核心代理配置）
# =========================================================
config_xray() {

# 自动生成 UUID（客户端身份）
UUID=$(cat /proc/sys/kernel/random/uuid)

cat > $CONFIG_FILE <<EOF
{
  "log": {
    "loglevel": "warning"
  },

  "dns": {
    "servers": [
      "1.1.1.1",
      "8.8.8.8",
      "localhost"
    ]
  },

  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 17654,
      "protocol": "vless",

      "settings": {
        "clients": [
          {
            "id": "${UUID}"
          }
        ],
        "decryption": "none"
      },

      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "${WS_PATH}"
        }
      },

      "sniffing": {
        "enabled": true,
        "routeOnly": true,
        "destOverride": [
          "http",
          "tls"
        ]
      },

      "mux": {
        "enabled": true,
        "concurrency": 8,
        "xudpConcurrency": 16
      }
    }
  ],

  "outbounds": [
    {
      "protocol": "freedom"
    },
    {
      "protocol": "blackhole"
    }
  ]
}
EOF
}

# =========================================================
# Nginx 配置（企业级优化）
# =========================================================
config_nginx() {

# 删除默认站点（避免冲突）
rm -f /etc/nginx/sites-enabled/default

cat > $NGINX_FILE <<EOF
server {

    # HTTP 强制跳转 HTTPS
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {

    # HTTPS + HTTP/2
    listen 443 ssl http2;
    server_name ${DOMAIN};

    # TLS 证书
    ssl_certificate /etc/ssl/private/${DOMAIN}.crt;
    ssl_certificate_key /etc/ssl/private/${DOMAIN}.key;

    # TLS 优化
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;

    # SSL session 优化
    ssl_session_cache shared:SSL:50m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    # 证书验证加速
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 1.1.1.1 8.8.8.8;

    # 禁用压缩（WebSocket 推荐）
    gzip off;

    # TCP 性能优化
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;

    keepalive_timeout 60s;
    keepalive_requests 1000;

    # 网站根目录（伪装站）
    root /var/www/html;

    # ==============================
    # WebSocket 转发（核心入口）
    # ==============================
    location ${WS_PATH} {

        # 防止非 WebSocket 请求
        if (\$http_upgrade != "websocket") {
            return 444;
        }

        # 转发到 Xray
        proxy_pass http://127.0.0.1:17654;

        proxy_http_version 1.1;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;

        # 禁用缓冲（降低延迟）
        proxy_buffering off;
        proxy_read_timeout 3600s;
    }

    # 伪装站点
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
}

# =========================================================
# 伪装网站（降低特征识别）
# =========================================================
fake_site() {

mkdir -p /var/www/html

cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Service</title>

<style>
body {
    font-family: Arial;
    text-align: center;
    padding-top: 80px;
    background: #f4f4f4;
}

.box {
    background: white;
    padding: 40px;
    width: 60%;
    margin: auto;
    border-radius: 10px;
}
</style>

</head>

<body>
<div class="box">
<h1>Service Running</h1>
<p>System is operating normally</p>
</div>
</body>
</html>
EOF
}

# =========================================================
# 服务启动与健康检查
# =========================================================
start_services() {

systemctl enable nginx xray
systemctl restart nginx xray

# 检查 nginx 是否启动成功
systemctl is-active --quiet nginx || {
    echo "[ERROR] Nginx failed to start"
    exit 1
}

# 检查 xray 是否启动成功
systemctl is-active --quiet xray || {
    echo "[ERROR] Xray failed to start"
    exit 1
}
}

# =========================================================
# 输出节点信息
# =========================================================
show_result() {

clear

echo "=================================================="
echo "           INSTALLATION COMPLETED"
echo "=================================================="
echo
echo "DOMAIN : $DOMAIN"
echo "UUID   : $UUID"
echo "PATH   : $WS_PATH"
echo
echo "--------------------------------------------------"
echo "NODE LINK"
echo "--------------------------------------------------"
echo
echo "vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=${WS_PATH}#${DOMAIN}"
echo
echo "=================================================="
}

# =========================================================
# 主流程
# =========================================================
main() {

show_logo          # 显示安装界面
detect_os          # 系统检测
tls_input          # 输入域名 + 证书
gen_ws_path        # 生成动态 WS 路径

install_deps       # 安装依赖
install_xray       # 安装 Xray

config_xray        # 写入 Xray 配置
config_nginx       # 写入 Nginx 配置
fake_site          # 创建伪装网站

start_services     # 启动服务

show_result        # 输出节点信息
}

main
