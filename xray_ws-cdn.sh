#!/usr/bin/env bash

# =========================================================
# XRAY PRODUCTION INSTALL SCRIPT
# 功能：
# - Xray + Nginx 一键部署
# - VLESS + WS + TLS
# - 动态 WS Path（防扫描）
# - 企业级 Nginx 优化
# - 多系统兼容
# - 安装 / 查看 / 修改 / 卸载
# =========================================================

set -e

# =========================================================
# 全局配置
# =========================================================
CONFIG_FILE="/usr/local/etc/xray/config.json"
NGINX_FILE="/etc/nginx/conf.d/xray.conf"

# =========================================================
# Logo
# =========================================================
show_logo() {

clear

echo "=================================================="
echo "                                                  "
echo "        ██╗  ██╗██████╗  █████╗ ██╗   ██╗         "
echo "        ╚██╗██╔╝██╔══██╗██╔══██╗╚██╗ ██╔╝         "
echo "         ╚███╔╝ ██████╔╝███████║ ╚████╔╝          "
echo "         ██╔██╗ ██╔══██╗██╔══██║  ╚██╔╝           "
echo "        ██╔╝ ██╗██║  ██║██║  ██║   ██║            "
echo "        ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝            "
echo "                                                  "
echo "              XRAY INSTALL PANEL                  "
echo "         VLESS + WS + TLS DEPLOY TOOL            "
echo "                                                  "
echo "=================================================="
echo
echo "System : $(uname -s) $(uname -m)"
echo "Kernel : $(uname -r)"
echo
echo "=================================================="
echo
}

# =========================================================
# 系统检测
# =========================================================
detect_os() {

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "无法识别系统"
    exit 1
fi

case "$OS" in

ubuntu|debian)
    INSTALL="apt install -y"
    UPDATE="apt update -y"
    ;;

centos|rocky|almalinux|rhel|ol)
    command -v dnf >/dev/null && INSTALL="dnf install -y" || INSTALL="yum install -y"
    UPDATE="yum makecache || dnf makecache"
    ;;

fedora)
    INSTALL="dnf install -y"
    UPDATE="dnf makecache"
    ;;

*)
    echo "不支持当前系统: $OS"
    exit 1
    ;;
esac
}

# =========================================================
# 生成动态 WS Path
# =========================================================
gen_ws_path() {

WS_PATH="/$(head /dev/urandom | tr -dc a-z0-9 | head -c 12)"
}

# =========================================================
# 安装依赖
# =========================================================
install_deps() {

echo
echo "[+] 安装系统依赖..."
echo

$UPDATE

$INSTALL curl wget unzip nginx openssl ca-certificates || true
}

# =========================================================
# 安装 Xray
# =========================================================
install_xray() {

echo
echo "[+] 安装 Xray Core..."
echo

if ! bash <(curl -Ls https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh); then
    echo
    echo "[ERROR] Xray 安装失败"
    exit 1
fi
}

# =========================================================
# 输入 TLS
# =========================================================
tls_input() {

echo "--------------------------------------------------"
echo "请输入域名"
echo "--------------------------------------------------"

read -rp "Domain: " DOMAIN

mkdir -p /etc/ssl/private

echo
echo "--------------------------------------------------"
echo "粘贴 CRT 证书内容（结束按 Ctrl+D）"
echo "--------------------------------------------------"

cat > /etc/ssl/private/${DOMAIN}.crt

echo
echo "--------------------------------------------------"
echo "粘贴 KEY 私钥内容（结束按 Ctrl+D）"
echo "--------------------------------------------------"

cat > /etc/ssl/private/${DOMAIN}.key

chmod 600 /etc/ssl/private/${DOMAIN}.key
}

# =========================================================
# 配置 Xray
# =========================================================
config_xray() {

UUID=$(cat /proc/sys/kernel/random/uuid)

mkdir -p /usr/local/etc/xray

cat > $CONFIG_FILE <<EOF
{
  "log": {
    "loglevel": "warning"
  },

  "dns": {
    "servers": [
      "https+local://1.1.1.1/dns-query",
      "https+local://8.8.8.8/dns-query",
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
          "path": "${WS_PATH}",
          "maxConcurrentStreams": 128
        }
      },

      "sniffing": {
        "enabled": true,
        "routeOnly": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
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
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF
}

# =========================================================
# 配置 Nginx
# =========================================================
config_nginx() {

mkdir -p /etc/nginx/conf.d

rm -f /etc/nginx/sites-enabled/default

cat > $NGINX_FILE <<EOF
server {

    listen 80;
    server_name ${DOMAIN};

    return 301 https://\$host\$request_uri;
}

server {

    listen 443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate /etc/ssl/private/${DOMAIN}.crt;
    ssl_certificate_key /etc/ssl/private/${DOMAIN}.key;

    ssl_protocols TLSv1.2 TLSv1.3;

    ssl_session_cache shared:SSL:50m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    ssl_prefer_server_ciphers off;

    ssl_stapling on;
    ssl_stapling_verify on;

    resolver 1.1.1.1 8.8.8.8;

    gzip off;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;

    keepalive_timeout 60s;
    keepalive_requests 1000;

    root /var/www/html;

    location ${WS_PATH} {

        if (\$http_upgrade != "websocket") {
            return 444;
        }

        proxy_pass http://127.0.0.1:17654;

        proxy_http_version 1.1;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_buffering off;
        proxy_request_buffering off;

        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;

        proxy_connect_timeout 10s;

        proxy_ssl_session_reuse on;
    }

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
}

# =========================================================
# 创建伪装站
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
body{
    font-family:Arial;
    background:#f4f4f4;
    text-align:center;
    padding-top:80px;
}

.box{
    background:white;
    width:60%;
    margin:auto;
    padding:40px;
    border-radius:10px;
    box-shadow:0 0 10px rgba(0,0,0,.1);
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
# 启动服务
# =========================================================
start_services() {

echo
echo "[+] 启动服务..."
echo

systemctl enable nginx xray >/dev/null 2>&1
systemctl restart nginx xray

systemctl is-active --quiet nginx || {
    echo
    echo "[ERROR] Nginx 启动失败"
    nginx -t
    exit 1
}

systemctl is-active --quiet xray || {
    echo
    echo "[ERROR] Xray 启动失败"
    exit 1
}
}

# =========================================================
# 安装
# =========================================================
install() {

show_logo

detect_os

tls_input

gen_ws_path

install_deps

install_xray

config_xray

config_nginx

fake_site

start_services

show_result
}

# =========================================================
# 查看节点
# =========================================================
show_node() {

DOMAIN=$(grep server_name $NGINX_FILE | head -n1 | awk '{print $2}' | sed 's/;//')

UUID=$(grep '"id"' $CONFIG_FILE | head -n1 | cut -d '"' -f4)

PATHX=$(grep -oP 'location \K/[a-z0-9]+' $NGINX_FILE | head -n1)

clear

echo "=================================================="
echo "                   节点信息"
echo "=================================================="
echo
echo "域名:"
echo "  $DOMAIN"
echo
echo "UUID:"
echo "  $UUID"
echo
echo "WS Path:"
echo "  $PATHX"
echo
echo "--------------------------------------------------"
echo "节点链接"
echo "--------------------------------------------------"
echo

echo "vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=${PATHX}#${DOMAIN}"

echo
echo "=================================================="
echo

read -n 1 -s -r -p "按任意键返回菜单..."
menu
}

# =========================================================
# 修改配置
# =========================================================
modify_config() {

clear

echo "=================================================="
echo "                 修改节点配置"
echo "=================================================="
echo
echo "  [1] 重新生成 UUID"
echo "  [2] 重新生成 WS Path"
echo "  [3] 返回主菜单"
echo
echo "=================================================="

read -rp "请选择: " m

case $m in

1)

NEW_UUID=$(cat /proc/sys/kernel/random/uuid)

sed -i "s/\"id\": \".*\"/\"id\": \"${NEW_UUID}\"/" $CONFIG_FILE

systemctl restart xray

echo
echo "新的 UUID:"
echo
echo "$NEW_UUID"
echo
;;

2)

NEW_PATH="/$(head /dev/urandom | tr -dc a-z0-9 | head -c 12)"

# 获取旧 PATH
OLD_PATH=$(grep -oP 'location \K/[a-z0-9]+' $NGINX_FILE | head -n1)

# 修改 Xray 配置
sed -i "s|\"path\": \".*\"|\"path\": \"${NEW_PATH}\"|" $CONFIG_FILE

# 精准替换 Nginx WS 路径
sed -i "s|location ${OLD_PATH} {|location ${NEW_PATH} {|" $NGINX_FILE

# 检测 Nginx 配置
if ! nginx -t; then

    echo
    echo "[ERROR] Nginx 配置错误"
    echo

    # 回滚
    sed -i "s|\"path\": \"${NEW_PATH}\"|\"path\": \"${OLD_PATH}\"|" $CONFIG_FILE
    sed -i "s|location ${NEW_PATH} {|location ${OLD_PATH} {|" $NGINX_FILE

    exit 1
fi

systemctl restart nginx
systemctl restart xray

echo
echo "新的 WS Path:"
echo
echo "$NEW_PATH"
echo
;;

3)
menu
;;

*)
echo "输入错误"
;;

esac

read -n 1 -s -r -p "按任意键返回菜单..."
menu
}

# =========================================================
# 卸载
# =========================================================
uninstall() {

clear

echo "=================================================="
echo "                   卸载环境"
echo "=================================================="
echo

read -rp "确认卸载？[y/N]: " confirm

[[ ! "$confirm" =~ ^[Yy]$ ]] && menu

systemctl stop nginx xray >/dev/null 2>&1 || true
systemctl disable nginx xray >/dev/null 2>&1 || true

bash <(curl -Ls https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh) remove || true

rm -rf /usr/local/etc/xray
rm -rf /usr/local/share/xray
rm -rf /var/log/xray

rm -f $NGINX_FILE

echo
echo "卸载完成"
echo

read -n 1 -s -r -p "按任意键返回菜单..."
menu
}

# =========================================================
# 安装结果
# =========================================================
show_result() {

clear

echo "=================================================="
echo "                安装完成"
echo "=================================================="
echo

echo "域名:"
echo "  ${DOMAIN}"
echo

echo "UUID:"
echo "  ${UUID}"
echo

echo "WS Path:"
echo "  ${WS_PATH}"
echo

echo "--------------------------------------------------"
echo "节点链接"
echo "--------------------------------------------------"
echo

echo "vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=${WS_PATH}#${DOMAIN}"

echo
echo "=================================================="
echo "状态: Xray + Nginx 运行正常"
echo "=================================================="
echo

read -n 1 -s -r -p "按任意键返回菜单..."
menu
}

# =========================================================
# 主菜单
# =========================================================
menu() {

show_logo

echo "=================================================="
echo "                    主菜单"
echo "=================================================="
echo
echo "  [1] 安装 Xray + Nginx"
echo "  [2] 查看节点信息"
echo "  [3] 修改节点配置"
echo "  [4] 卸载环境"
echo "  [0] 退出脚本"
echo
echo "=================================================="

read -rp "请输入选项: " opt

case $opt in
    1)
        install
        ;;
    2)
        show_node
        ;;
    3)
        modify_config
        ;;
    4)
        uninstall
        ;;
    0)
        exit 0
        ;;
    *)
        echo
        echo "输入错误"
        sleep 1
        menu
        ;;
esac
}

# =========================================================
# 启动菜单
# =========================================================
menu
