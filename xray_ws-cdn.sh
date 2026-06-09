#!/usr/bin/env bash

# ===================================================================
# XRAY + NGINX 一键安装脚本（VLESS + WS + TLS）
# -------------------------------------------------------------------
# 版本: v3.0.0 修正版（兼容不带 HTTP/2 的 Nginx）
# 作者: 自动化整合
# 功能: 自动安装 Xray + Nginx，配置随机 WS Path，TLS 证书
# ===================================================================

set -e

# ===================================================================
# 脚本版本号
# ===================================================================
SCRIPT_VERSION="v3.0.0"

# ===================================================================
# 配置文件路径
# ===================================================================
CONFIG_FILE="/usr/local/etc/xray/config.json"
NGINX_FILE="/etc/nginx/conf.d/xray.conf"

# ===================================================================
# 显示 Logo 美化界面
# ===================================================================
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
    echo " 脚本版本 : ${SCRIPT_VERSION}"
    echo " 系统信息 : $(uname -s)"
    echo " 内核版本 : $(uname -r)"
    echo " 系统架构 : $(uname -m)"
    echo
    echo "===================================================================="
    echo
}

# ===================================================================
# 系统检测（Debian/Ubuntu/CentOS/Rocky/AlmaLinux）
# ===================================================================
detect_os() {
    . /etc/os-release
    case "$ID" in
        ubuntu|debian)
            PKG_INSTALL="apt install -y"
            PKG_UPDATE="apt update -y"
            ;;
        centos|rocky|almalinux|rhel)
            PKG_INSTALL="yum install -y"
            PKG_UPDATE="yum makecache"
            ;;
        *)
            echo "[ERROR] 当前系统不受支持"
            exit 1
            ;;
    esac
}

# ===================================================================
# 生成随机 WS Path（12 位随机字符）
# ===================================================================
gen_ws_path() {
    WS_PATH="/$(tr -dc a-z0-9 </dev/urandom | head -c 12)"
}

# ===================================================================
# 生成 UUID
# ===================================================================
gen_uuid() {
    UUID=$(cat /proc/sys/kernel/random/uuid)
}

# ===================================================================
# 安装系统依赖（curl/wget/unzip/nginx/openssl/ca-certificates）
# ===================================================================
install_deps() {
    echo "[1/6] 安装系统依赖..."
    echo
    $PKG_UPDATE
    $PKG_INSTALL curl wget unzip nginx openssl ca-certificates
}

# ===================================================================
# 安装 Xray Core
# ===================================================================
install_xray() {
    echo "[2/6] 安装 Xray Core..."
    echo
    bash <(curl -Ls https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh)
}

# ===================================================================
# 输入域名及 TLS 证书
# ===================================================================
tls_input() {
    echo "===================================================================="
    echo " 请输入域名"
    echo "===================================================================="
    read -rp "Domain: " DOMAIN

    mkdir -p /etc/ssl/private

    echo
    echo "请粘贴 CRT 证书内容（Ctrl+D 结束）"
    cat > /etc/ssl/private/${DOMAIN}.crt

    echo
    echo "请粘贴 KEY 私钥内容（Ctrl+D 结束）"
    cat > /etc/ssl/private/${DOMAIN}.key

    chmod 600 /etc/ssl/private/${DOMAIN}.key
}

# ===================================================================
# 配置 Xray
# ===================================================================
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
    "servers": ["1.1.1.1","8.8.8.8","localhost"]
  },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 17654,
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "${UUID}"}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "${WS_PATH}"}
      }
    }
  ],
  "outbounds": [{"protocol": "freedom"}]
}
EOF
}

# ===================================================================
# 配置 Nginx（兼容无 HTTP/2）
# ===================================================================
config_nginx() {
    mkdir -p /etc/nginx/conf.d
    cat > $NGINX_FILE <<EOF
server {
    # HTTP 自动跳转 HTTPS
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    # HTTPS
    listen 443 ssl;

    server_name ${DOMAIN};

    # TLS 证书
    ssl_certificate /etc/ssl/private/${DOMAIN}.crt;
    ssl_certificate_key /etc/ssl/private/${DOMAIN}.key;

    # TLS 协议
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;

    # 网站目录
    root /var/www/html;
    index index.html;

    # =====================================================
    # WebSocket 代理（随机路径）
    # =====================================================
    location ${WS_PATH} {
        proxy_pass http://127.0.0.1:17654;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }

    # =====================================================
    # 伪装站
    # =====================================================
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
}

# ===================================================================
# 创建伪装网站
# ===================================================================
fake_site() {
    mkdir -p /var/www/html
    cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>System Status</title>
<style>
body{background:#f5f7fa;font-family:Arial;text-align:center;padding-top:140px;}
.card{width:420px;margin:auto;background:white;padding:40px;border-radius:14px;box-shadow:0 10px 30px rgba(0,0,0,0.1);}
h1{color:#222;}
p{color:#666;}
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

# ===================================================================
# 启动服务并设置开机自启
# ===================================================================
start_services() {
    echo "[3/6] 启动服务..."
    systemctl enable nginx xray >/dev/null 2>&1
    systemctl restart nginx
    systemctl restart xray
}

# ===================================================================
# 显示安装结果与节点信息
# ===================================================================
show_result() {
    clear
    echo "===================================================================="
    echo "                           安装完成"
    echo "===================================================================="
    echo
    echo " 域名     : ${DOMAIN}"
    echo " UUID     : ${UUID}"
    echo " WS Path  : ${WS_PATH}"
    echo
    echo "--------------------------------------------------------------------"
    echo " 节点链接"
    echo "--------------------------------------------------------------------"
    echo
    echo "vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=${WS_PATH}#${DOMAIN}"
    echo
    echo "===================================================================="
    echo " Xray + Nginx 已成功运行"
    echo "===================================================================="
    echo
    read -n 1 -s -r -p "按任意键返回菜单..."
    menu
}

# ===================================================================
# 查看节点信息
# ===================================================================
show_node() {
    DOMAIN=$(grep server_name $NGINX_FILE | awk '{print $2}' | head -n1 | sed 's/;//')
    UUID=$(grep '"id"' $CONFIG_FILE | cut -d '"' -f4)
    PATHX=$(grep '"path"' $CONFIG_FILE | cut -d '"' -f4)

    clear
    echo "===================================================================="
    echo "                           节点信息"
    echo "===================================================================="
    echo
    echo " 域名     : ${DOMAIN}"
    echo " UUID     : ${UUID}"
    echo " WS Path  : ${PATHX}"
    echo
    echo "--------------------------------------------------------------------"
    echo " 节点链接"
    echo "--------------------------------------------------------------------"
    echo
    echo "vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=${PATHX}#${DOMAIN}"
    echo
    echo "===================================================================="
    echo
    read -n 1 -s -r -p "按任意键返回菜单..."
    menu
}

# ===================================================================
# 修改 UUID
# ===================================================================
modify_uuid() {
    NEW_UUID=$(cat /proc/sys/kernel/random/uuid)
    sed -i "s/\"id\": \".*\"/\"id\": \"${NEW_UUID}\"/" $CONFIG_FILE
    systemctl restart xray
    echo
    echo "新的 UUID: ${NEW_UUID}"
    echo
    read -n 1 -s -r -p "按任意键返回菜单..."
    menu
}

# ===================================================================
# 卸载 Xray + Nginx
# ===================================================================
uninstall() {
    echo "正在卸载..."
    systemctl stop nginx xray || true
    systemctl disable nginx xray || true
    bash <(curl -Ls https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh) remove || true
    rm -rf /usr/local/etc/xray
    rm -f /etc/nginx/conf.d/xray.conf
    echo "卸载完成"
    read -n 1 -s -r -p "按任意键返回菜单..."
    menu
}

# ===================================================================
# 安装流程
# ===================================================================
install() {
    show_logo
    detect_os
    tls_input
    install_deps
    install_xray
    config_xray
    config_nginx
    fake_site
    start_services
    show_result
}

# ===================================================================
# 主菜单
# ===================================================================
menu() {
    show_logo
    echo "===================================================================="
    echo " [1] 安装 Xray + Nginx"
    echo " [2] 查看节点信息"
    echo " [3] 修改 UUID"
    echo " [4] 卸载环境"
    echo " [0] 退出脚本"
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

# ===================================================================
# 启动菜单
# ===================================================================
menu
