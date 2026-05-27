# 🚀 XRAY + NGINX 一键安装脚本

## 生产级 Xray + Nginx 一键安装脚本，支持：

- VLESS + WS + TLS
- 随机 WebSocket Path（防扫描）
- 自动伪装站点
- 美化 SSH 安装界面
- UUID 一键修改
- Debian / Ubuntu / CentOS 兼容

## ✨ 功能特点

### ✔ 协议支持

- VLESS
- WebSocket
- TLS 1.2 / TLS 1.3

### ✔ 安全优化

- 随机 WS Path
- 非 WebSocket 请求直接 444
- TLS 强制 HTTPS
- WebSocket 长连接优化
- 防扫描结构

### ✔ Nginx 优化

- HTTP/2
- WebSocket Upgrade
- 长连接优化
- 低延迟代理
- 禁用缓冲

### ✔ Xray 优化

- warning 日志级别
- 本地监听
- DNS 优化
- 稳定生产配置

## 📦 支持系统

| 系统        | 支持 |
| ----------- | ---- |
| Debian      | ✔    |
| Ubuntu      | ✔    |
| CentOS 7+   | ✔    |
| Rocky Linux | ✔    |
| AlmaLinux   | ✔    |

🖥 安装界面
====================================================================

```
====================================================================

   ██╗  ██╗██████╗  █████╗ ██╗   ██╗
   ╚██╗██╔╝██╔══██╗██╔══██╗╚██╗ ██╔╝
    ╚███╔╝ ██████╔╝███████║ ╚████╔╝
    ██╔██╗ ██╔══██╗██╔══██║  ╚██╔╝
   ██╔╝ ██╗██║  ██║██║  ██║   ██║
   ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝

            XRAY INSTALL PANEL

====================================================================

====================================================================
```

🚀 安装方法

```bash
bash -c "$(curl -L https://raw.githubusercontent.com/SumMoonYou/xray_ws-cdn/refs/heads/main/xray_ws-cdn.sh)" @ install
```

## 📋 安装流程

### 脚本会自动：

- 检测系统
- 安装依赖
- 安装 Xray
- 配置 Nginx
- 输入域名
- 粘贴 TLS 证书
- 启动服务
- 输出节点链接

## 🔐 TLS 证书

### 安装时会提示：

请粘贴 CRT 证书
请粘贴 KEY 私钥

### 📡 节点格式

```
vless://UUID@domain.com:443?encryption=none&security=tls&type=ws&host=domain.com&path=/randompath#domain
```

### ⚙ 默认配置

| 项目    | 默认值      |
| ------- | ----------- |
| 协议    | VLESS       |
| 传输    | WebSocket   |
| TLS     | 开启        |
| 端口    | 443         |
| WS Path | 随机生成    |
| Nginx   | 开启 HTTP/2 |

### 📂 目录结构

```
/usr/local/etc/xray/config.json
/etc/nginx/conf.d/xray.conf
/var/www/html/
/etc/ssl/private/
```

### 🛠 菜单功能

```
[1] 安装 Xray + Nginx
[2] 查看节点信息
[3] 修改 UUID
[4] 卸载环境
[0] 退出脚本
```

### 🔄 修改 UUID

#### 脚本支持：

- 自动生成新 UUID
- 自动重启 Xray
- 节点链接同步更新

#### 不会影响：

- 域名
- TLS
- WS Path
- Nginx

### 🗑 卸载

#### 支持：

- 停止服务
- 删除 Xray
- 删除配置文件
- 删除 Nginx 配置

### 🚀 性能优化

#### Nginx

- HTTP/2
- 长连接
- WebSocket Upgrade
- 低延迟代理
- 关闭缓冲

#### Xray

- 本地监听
- warning 日志
- DNS 优化
