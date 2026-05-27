#!/usr/bin/env bash

# =========================================================
# XRAY + NGINX 一键安装脚本
# 功能：
# - VLESS + WS + TLS
# =========================================================

set -e

# =========================================================
# 配置文件路径
# =========================================================
CONFIG_FILE="/usr/local/etc/xray/config.json"
NGINX_FILE="/etc/nginx/conf.d/xray.conf"

# =========================================================
# SSH界面
# =========================================================
show_logo() {

clear

echo "===================================================================="
echo "                                                                    "
echo "   ██╗  ██╗██████╗  █████╗ ██╗   ██╗                               "
echo "   ╚██╗██╔╝██╔══██╗██╔══██╗╚██╗ ██╔╝                               "
echo "    ╚███╔╝ ██████╔╝███████║ ╚████╔╝                                "
echo "    ██╔██╗ ██╔══██╗██╔══██║  ╚██╔╝                                 "
echo "   ██╔╝ ██╗██║  ██║██║  ██║   ██║                                  "
echo "   ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝                                  "
echo "                                                                    "
echo "            XRAY INSTALL PANEL  |  BEAUTY VERSION                  "
echo "                                                                    "
echo "===================================================================="
echo
echo "系统信息 : $(uname -s)"
echo "内核版本 : $(uname -r)"
echo "架构     : $(uname -m)"
echo
echo "===================================================================="
echo
}

# =========================================================
# 系统检测（兼容 Debian / Ubuntu / CentOS）
# =========================================================
detect_os() {

. /etc/os-release

case "$ID" in

ubuntu|debian)
    INSTALL="apt install -y"
    UPDATE="apt update -y"
    ;;

centos|rocky|almalinux|rhel)
    INSTALL="yum install -y"
    UPDATE="yum makecache"
    ;;

*)
    echo "[ERROR] 不支持当前系统"
    exit 1
    ;;
esac
}

# =========================================================
# 随机 WS Path（核心防扫描）
# =========================================================
gen_ws_path() {

# 生成 12位随机字符串
WS_PATH="/$(tr -dc a-z0-9 </dev/urandom | head -c 12)"
}

# =========================================================
# UUID 生成
# =========================================================
gen_uuid() {

UUID=$(cat /proc/sys/kernel/random/uuid)
}

# =========================================================
# 安装依赖
# =========================================================
install_deps() {

echo "[1/6] 安装系统依赖..."

$UPDATE

$INSTALL curl wget unzip nginx openssl ca-certificates -y
}

# =========================================================
# 安装 Xray Core
# =========================================================
install_xray() {

echo "[2/6] 安装 Xray Core..."

bash <(curl -Ls https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh)
}

# =========================================================
# 输入域名 + TLS证书
# =========================================================
tls_input() {

echo "===================================================================="
echo "请输入域名"
echo "===================================================================="

read -rp "Domain: " DOMAIN

mkdir -p /etc/ssl/private

echo
echo "请粘贴 CRT 证书（Ctrl + D结束）"
cat > /etc/ssl/private/${DOMAIN}.crt

echo
echo "请粘贴 KEY 私钥（Ctrl + D结束）"
cat > /etc/ssl/private/${DOMAIN}.key

chmod 600 /etc/ssl/private/${DOMAIN}.key
}

# =========================================================
# Xray 配置（随机WS + VLESS）
# =========================================================
config_xray() {

gen_uuid

gen_ws_path

mkdir -p /usr/local/etc/xray

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
      }
    }
  ],

  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF
}

# =========================================================
# Nginx 配置（与WS同步）
# =========================================================
config_nginx() {

mkdir -p /etc/nginx/conf.d

cat > $NGINX_FILE <<EOF
server {

    listen 80;
    server_name ${DOMAIN};

    return 301 https://\$host\$request_uri;
}

server {

    listen 443 ssl;
    http2 on;

    server_name ${DOMAIN};

    ssl_certificate /etc/ssl/private/${DOMAIN}.crt;
    ssl_certificate_key /etc/ssl/private/${DOMAIN}.key;

    ssl_protocols TLSv1.2 TLSv1.3;

    root /var/www/html;

    # =====================================================
    # WebSocket 代理（随机路径）
    # =====================================================
    location ${WS_PATH} {

        # 非WS请求直接拒绝
        if (\$http_upgrade != "websocket") {
            return 444;
        }

        # 转发到 Xray
        proxy_pass http://127.0.0.1:17654;

        proxy_http_version 1.1;

        # WebSocket升级头
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";

        # 保留真实信息
        proxy_set_header Host \$host;

        # 性能优化
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    # 伪装站
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
}

# =========================================================
# 伪装网站（美化UI）
# =========================================================
fake_site() {

mkdir -p /var/www/html

cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>System Status</title>

<style>
body{
    background: linear-gradient(120deg,#f6f9fc,#eef2f7);
    font-family: Arial;
    text-align:center;
    padding-top:140px;
}

.card{
    width:420px;
    margin:auto;
    background:white;
    padding:40px;
    border-radius:14px;
    box-shadow:0 15px 40px rgba(0,0,0,0.12);
}

h1{
    color:#222;
}

p{
    color:#777;
}
</style>

</head>

<body>

<div class="card">
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

systemctl enable nginx xray >/dev/null 2>&1

systemctl restart nginx
systemctl restart xray
}

# =========================================================
# 安装完成信息
# =========================================================
show_result() {

clear

echo "===================================================================="
echo "                           安装完成"
echo "===================================================================="
echo
echo "域名     : ${DOMAIN}"
echo "UUID     : ${UUID}"
echo "WS Path  : ${WS_PATH}"
echo
echo "--------------------------------------------------------------------"
echo "节点链接"
echo "--------------------------------------------------------------------"
echo

echo "vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=${WS_PATH}#${DOMAIN}"

echo
echo "===================================================================="
echo "状态：Xray + Nginx 已运行"
echo "===================================================================="
echo

read -n 1 -s -r -p "按任意键返回菜单..."
menu
}

# =========================================================
# 查看节点
# =========================================================
show_node() {

DOMAIN=$(grep server_name $NGINX_FILE | awk '{print $2}' | head -n1 | sed 's/;//')
UUID=$(grep '"id"' $CONFIG_FILE | cut -d '"' -f4)
PATHX=$(grep '"path"' $CONFIG_FILE | cut -d '"' -f4)

clear

echo "===================================================================="
echo "                           节点信息"
echo "===================================================================="
echo
echo "域名     : $DOMAIN"
echo "UUID     : $UUID"
echo "WS Path  : $PATHX"
echo
echo "--------------------------------------------------------------------"
echo "节点链接"
echo "--------------------------------------------------------------------"
echo

echo "vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=${PATHX}#${DOMAIN}"

echo
read -n 1 -s -r -p "返回..."
menu
}

# =========================================================
# 修改 UUID
# =========================================================
modify_uuid() {

NEW_UUID=$(cat /proc/sys/kernel/random/uuid)

sed -i "s/\"id\": \".*\"/\"id\": \"${NEW_UUID}\"/" $CONFIG_FILE

systemctl restart xray

echo
echo "新的 UUID：$NEW_UUID"
echo

read -n 1 -s -r -p "返回..."
menu
}

# =========================================================
# 卸载
# =========================================================
uninstall() {

systemctl stop nginx xray
systemctl disable nginx xray

bash <(curl -Ls https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh) remove || true

rm -rf /usr/local/etc/xray
rm -rf /etc/nginx/conf.d/xray.conf

echo "已卸载完成"

read -n 1 -s -r -p "返回..."
menu
}

# =========================================================
# 菜单
# =========================================================
menu() {

show_logo

echo "===================================================================="
echo " [1] 安装 Xray + Nginx"
echo " [2] 查看节点信息"
echo " [3] 修改 UUID"
echo " [4] 卸载环境"
echo " [0] 退出"
echo "===================================================================="

read -rp "请选择: " opt

case $opt in
1) install ;;
2) show_node ;;
3) modify_uuid ;;
4) uninstall ;;
0) exit 0 ;;
*) menu ;;
esac
}

# =========================================================
# 启动菜单
# =========================================================
menu
