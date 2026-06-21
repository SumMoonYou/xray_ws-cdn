#!/usr/bin/env bash

# ======================================================
# 🚀 Xray 面板
# ======================================================

CONF="/etc/xray/config.json"
CERT_DIR="/etc/xray/cert"
BACKUP_DIR="/etc/xray/backup"
META_FILE="/etc/xray/meta.env"

mkdir -p "$CERT_DIR" "$BACKUP_DIR"

# ================= 颜色 =================
GREEN="\033[32m"
BLUE="\033[36m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"
BOLD="\033[1m"

# ================= Root 检测 =================
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ 请使用 root 运行${RESET}"
    exit 1
fi

# ================= 系统依赖安装 =================
install_pkg() {
    if command -v apt >/dev/null 2>&1; then
        apt update -y >/dev/null 2>&1
        apt install -y "$@" >/dev/null 2>&1

    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y "$@" >/dev/null 2>&1

    elif command -v yum >/dev/null 2>&1; then
        yum install -y "$@" >/dev/null 2>&1

    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache "$@" >/dev/null 2>&1

    else
        echo -e "${RED}❌ 不支持的系统${RESET}"
        exit 1
    fi
}

check_cmd() {
    command -v "$1" >/dev/null 2>&1
}

echo -e "${BLUE}🧠 检查依赖...${RESET}"

for pkg in curl unzip; do
    if ! check_cmd "$pkg"; then
        echo "📦 安装 $pkg"
        install_pkg "$pkg"
    fi
done

# jq（可选但推荐）
if ! check_cmd jq; then
    echo "📦 安装 jq"
    install_pkg jq
fi

echo -e "${GREEN}✔ 依赖检查完成${RESET}"

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
echo -e "${GREEN}   VLESS + WS + TLS${RESET}"
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

backup_conf() {
    [[ -f "$CONF" ]] && cp "$CONF" "$BACKUP_DIR/config_$(date +%F_%H%M%S).json"
}

save_meta() {
    cat > "$META_FILE" <<EOF
DOMAIN=$DOMAIN
PORT=$PORT
EOF
}

load_meta() {
    [[ -f "$META_FILE" ]] && source "$META_FILE"
}

gen_link() {
    echo ""
    echo -e "${YELLOW}🔗 VLESS 链接${RESET}"
    echo ""
    echo "vless://$1@$2:$3?encryption=none&security=tls&type=ws&host=$2&path=/$4&sni=$2#$2"
    echo ""
}

check_service() {
    systemctl is-active --quiet xray
}

# ======================================================
# 📦 安装
# ======================================================
install() {

    echo ""
    echo -e "${BLUE}📦 Xray 安装${RESET}"

    read -p "🌐 域名: " DOMAIN
    read -p "🔌 端口（默认443）: " PORT
    PORT=${PORT:-443}

    UUID=$(gen_uuid)
    PATH_WS=$(gen_path)

    echo "📌 粘贴 fullchain.pem (Ctrl+D结束):"
    cat > "$CERT_DIR/fullchain.pem"

    echo "📌 粘贴 privkey.pem (Ctrl+D结束):"
    cat > "$CERT_DIR/privkey.pem"

    # 证书检查
    if [[ ! -s "$CERT_DIR/fullchain.pem" || ! -s "$CERT_DIR/privkey.pem" ]]; then
        echo -e "${RED}❌ 证书无效${RESET}"
        exit 1
    fi

    backup_conf
    save_meta

    echo "📡 安装 Xray..."

    ARCH=$(uname -m)

    if [[ "$ARCH" == "x86_64" ]]; then
        FILE="Xray-linux-64.zip"
    elif [[ "$ARCH" == "aarch64" ]]; then
        FILE="Xray-linux-arm64-v8a.zip"
    else
        echo "❌ 不支持架构"
        exit 1
    fi

    URL="https://github.com/XTLS/Xray-core/releases/latest/download/$FILE"

    curl -L -o xray.zip "$URL" || {
        echo "❌ 下载失败"
        exit 1
    }

    unzip -o xray.zip -d /usr/local/bin/
    chmod +x /usr/local/bin/xray
    rm -f xray.zip

    mkdir -p /etc/xray

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
        "path": "/$PATH_WS"
      },
      "tlsSettings": {
        "certificates": [{
          "certificateFile": "$CERT_DIR/fullchain.pem",
          "keyFile": "$CERT_DIR/privkey.pem"
        }]
      }
    }
  }],
  "outbounds": [{
    "protocol": "freedom"
  }]
}
EOF

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

    echo -e "${GREEN}🎉 安装完成${RESET}"

    gen_link "$UUID" "$DOMAIN" "$PORT" "$PATH_WS"
}

# ======================================================
# 📄 查看
# ======================================================
show() {

    load_meta

    echo "===================="
    echo "📄 配置"
    echo "===================="

    cat "$CONF" 2>/dev/null || echo "无配置"

    systemctl status xray --no-pager

    if [[ -f "$CONF" ]]; then
        UUID=$(grep '"id"' "$CONF" | head -n1 | cut -d'"' -f4)
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

    if command -v jq >/dev/null 2>&1; then
        jq '.inbounds[0].settings.clients[0].id="'"$UUID"'" | .inbounds[0].streamSettings.wsSettings.path="/'"$PATH_WS"'"' "$CONF" > tmp && mv tmp "$CONF"
    else
        sed -i "s/\"id\": \".*\"/\"id\": \"$UUID\"/" "$CONF"
        sed -i "s#\"path\": \".*\"#\"path\": \"/$PATH_WS\"#" "$CONF"
    fi

    systemctl restart xray

    echo "✔ 已更新"
}

# ======================================================
# 🗑️ 卸载
# ======================================================
uninstall() {

    read -p "确认卸载?(y/n): " c
    [[ "$c" != "y" ]] && return

    systemctl stop xray
    systemctl disable xray

    rm -rf /etc/xray
    rm -f /usr/local/bin/xray
    rm -f /etc/systemd/system/xray.service

    systemctl daemon-reload

    echo "🧹 已清理"
}

# ======================================================
# 🔄 重启
# ======================================================
restart() {
    systemctl restart xray
    check_service && echo "✔ OK" || echo "❌ FAIL"
}

# ================= 主菜单 =================
case $opt in
    1) install ;;
    2) show ;;
    3) modify ;;
    4) uninstall ;;
    5) restart ;;
    0) exit 0 ;;
    *) echo "无效选项" ;;
esac
