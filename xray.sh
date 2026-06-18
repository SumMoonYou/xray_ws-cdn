#!/usr/bin/env bash

# ======================================================
# 🚀 Xray 面板
# ======================================================

CONF="/etc/xray/config.json"
CERT_DIR="/etc/xray/cert"
BACKUP_DIR="/etc/xray/backup"

mkdir -p "$CERT_DIR" "$BACKUP_DIR"

# ================= 颜色 =================
GREEN="\033[32m"
BLUE="\033[36m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"
BOLD="\033[1m"

# ================= 大LOGO =================
clear
echo -e "${BLUE}${BOLD}"
cat << "EOF"
██╗  ██╗██████╗  █████╗ ██╗  ██╗
╚██╗██╔╝██╔══██╗██╔══██╗╚██╗██╔╝
 ╚███╔╝ ██████╔╝███████║ ╚███╔╝ 
 ██╔██╗ ██╔══██╗██╔══██║ ██╔██╗ 
██╔╝ ██╗██║  ██║██║  ██║██╔╝ ██╗
╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝
      🚀 XRAY CONTROL PANEL
EOF
echo -e "${RESET}"

echo -e "${GREEN}========================================${RESET}"
echo -e "${GREEN}   VLESS + WS + TLS（性能优化版）${RESET}"
echo -e "${GREEN}========================================${RESET}"

echo ""
echo "1) 📦 安装"
echo "2) 📄 查看"
echo "3) ⚙️ 修改"
echo "4) 🗑️ 卸载"
echo "5) 🔄 重启"
echo "0) 🚪 退出"
echo ""

read -p "👉 请选择: " opt

# ================= 工具 =================
gen_uuid() {
    cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen
}

gen_path() {
    tr -dc a-z0-9 </dev/urandom | head -c 10
}

gen_link() {
    echo ""
    echo -e "${YELLOW}========================================${RESET}"
    echo -e "${YELLOW}🔗 VLESS 链接${RESET}"
    echo -e "${YELLOW}========================================${RESET}"
    echo ""
    echo "vless://$1@$2:$3?encryption=none&security=tls&type=ws&host=$2&path=/$4&sni=$2#$2"
    echo ""
}

backup_conf() {
    [[ -f "$CONF" ]] && cp "$CONF" "$BACKUP_DIR/config_$(date +%F_%H%M%S).json"
}

check_service() {
    systemctl is-active --quiet xray
}

# ======================================================
# 📦 安装
# ======================================================
install() {

    echo ""
    echo -e "${BLUE}========================================${RESET}"
    echo -e "${GREEN}📦 Xray 安装向导${RESET}"
    echo -e "${BLUE}========================================${RESET}"

    read -p "🌐 域名: " DOMAIN
    read -p "🔌 端口（默认443）: " PORT
    PORT=${PORT:-443}

    UUID=$(gen_uuid)
    PATH_WS=$(gen_path)

    echo ""
    echo -e "${GREEN}📌 粘贴 fullchain.pem（Ctrl+D结束）：${RESET}"
    cat > "$CERT_DIR/fullchain.pem"

    echo ""
    echo -e "${GREEN}📌 粘贴 privkey.pem（Ctrl+D结束）：${RESET}"
    cat > "$CERT_DIR/privkey.pem"

    backup_conf

    echo ""
    echo -e "${BLUE}📡 安装 Xray-core...${RESET}"

    ARCH=$(uname -m)

    if [[ "$ARCH" == "x86_64" ]]; then
        FILE="Xray-linux-64.zip"
    elif [[ "$ARCH" == "aarch64" ]]; then
        FILE="Xray-linux-arm64-v8a.zip"
    else
        echo -e "${RED}❌ 不支持架构${RESET}"
        exit 1
    fi

    URL="https://github.com/XTLS/Xray-core/releases/latest/download/${FILE}"

    echo "⬇️ $URL"

    curl -L --fail -o xray.zip "$URL"

    if [[ ! -s xray.zip ]]; then
        echo -e "${RED}❌ 下载失败${RESET}"
        exit 1
    fi

    unzip -o xray.zip -d /usr/local/bin/
    chmod +x /usr/local/bin/xray
    rm -f xray.zip

    # ======================================================
    # ⚡ 性能优化配置
    # ======================================================
    cat > "$CONF" <<EOF
{
  "log": {
    "loglevel": "warning"
  },

  "inbounds": [{
    "port": $PORT,
    "protocol": "vless",
    "settings": {
      "clients": [{
        "id": "$UUID"
      }],
      "decryption": "none"
    },

    "streamSettings": {
      "network": "ws",
      "security": "tls",

      "wsSettings": {
        "path": "/$PATH_WS",
        "maxEarlyData": 2048
      },

      "tlsSettings": {
        "alpn": ["http/1.1"],
        "certificates": [{
          "certificateFile": "$CERT_DIR/fullchain.pem",
          "keyFile": "$CERT_DIR/privkey.pem"
        }]
      }
    },

    "sniffing": {
      "enabled": false
    }
  }],

  "outbounds": [{
    "protocol": "freedom"
  }]
}
EOF

    # systemd 优化
    cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
ExecStart=/usr/local/bin/xray run -config $CONF
Restart=always
LimitNOFILE=100000

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable xray >/dev/null 2>&1
    systemctl restart xray

    echo ""
    echo -e "${GREEN}🎉 安装完成！${RESET}"

    gen_link "$UUID" "$DOMAIN" "$PORT" "$PATH_WS"
}

# ======================================================
# 📄 查看
# ======================================================
show() {

    echo ""
    echo "===================================="
    echo "📄 当前配置"
    echo "===================================="

    cat "$CONF" 2>/dev/null || echo "无配置"

    echo ""
    systemctl status xray --no-pager || true

    if [[ -f "$CONF" ]]; then
        UUID=$(grep '"id"' "$CONF" | head -n1 | cut -d'"' -f4)
        PORT=$(grep '"port"' "$CONF" | head -n1 | grep -o '[0-9]*')
        PATH_WS=$(grep '"path"' "$CONF" | head -n1 | cut -d'"' -f4)

        gen_link "$UUID" "$DOMAIN" "$PORT" "$PATH_WS"
    fi
}

# ======================================================
# ⚙️ 修改
# ======================================================
modify() {

    [[ ! -f "$CONF" ]] && return

    UUID=$(gen_uuid)
    PATH_WS=$(gen_path)

    backup_conf

    sed -i "s/\"id\": \".*\"/\"id\": \"$UUID\"/" "$CONF"
    sed -i "s#\"path\": \".*\"#\"path\": \"/$PATH_WS\"#" "$CONF"

    systemctl restart xray

    echo "✔ UUID已更新"
}

# ======================================================
# 🗑️ 卸载
# ======================================================
uninstall() {

    read -p "确认卸载Xray?(y/n): " c
    [[ "$c" != "y" ]] && return

    systemctl stop xray || true
    systemctl disable xray || true

    rm -rf /etc/xray
    rm -f /usr/local/bin/xray
    rm -f /etc/systemd/system/xray.service

    systemctl daemon-reload

    echo "🧹 已彻底清理完成"
}

# ======================================================
# 🔄 重启
# ======================================================
restart() {
    systemctl restart xray
    check_service && echo "✔ OK" || echo "❌ FAIL"
}

# ================= 主 =================
case $opt in
    1) install ;;
    2) show ;;
    3) modify ;;
    4) uninstall ;;
    5) restart ;;
    0) exit 0 ;;
    *) echo "无效选项" ;;
esac
