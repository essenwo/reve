#!/usr/bin/env bash

# =========================================================
# Xray Reality 工业级自动订阅一键安装脚本 (漏洞全修补终极版)
# =========================================================

set -euo pipefail
clear

echo "================================================="
echo "    Xray Reality Auto Installer (Production)     "
echo "================================================="
echo

# 交互式获取域名 (必须使用你在 Cloudflare 解析好灰色云朵的域名)
if [ -t 0 ]; then
  read -r -p "请输入你在 Cloudflare 解析的域名 (如 vps1.1564151.xyz): " DOMAIN || true
else
  echo "[ERROR] 必须在交互式终端运行"
  exit 1
fi

if [[ -z "$DOMAIN" ]]; then
  echo "域名不能为空"
  exit 1
fi

echo
echo "开始工业级无缝安装..."
sleep 2

# =========================================================
# 基础配置与变量纯化
# =========================================================
UUID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)
PORT=443
SHORT_ID=$(openssl rand -hex 8)
SERVER_NAME="www.apple.com"
XRAY_DIR="/usr/local/etc/xray"

# 随机化本地订阅路径，防止被扫描
SUB_PATH=$(openssl rand -hex 12)
CLASH_PATH=$(openssl rand -hex 12)

# =========================================================
# 环境洗净与依赖安装 (彻底堵死 Needrestart 弹窗漏洞)
# =========================================================
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl wget unzip openssl nginx jq cron ufw net-tools

# 自动获取准确的公网 IPv4
PUBLIC_IP=$(curl -4 -s --connect-timeout 5 https://api.ip.sb/ip || curl -4 -s --connect-timeout 5 https://ifconfig.me || echo "")
if [ -z "$PUBLIC_IP" ]; then
  echo "[ERROR] 无法获取外部公网 IP，请检查 VPS 网络环境。"
  exit 1
fi

# 智能捕获当前正在运行的真实 SSH 端口，防止开启防火墙后将用户锁死
SSH_PORT=$(ss -tlnp | grep sshd | awk '{print $4}' | awk -F':' '{print $NF}' | sort -u | head -n 1 || echo "22")
if [ -z "$SSH_PORT" ]; then
  SSH_PORT="22"
fi

# =========================================================
# 修复端口内讧：修改 Nginx 默认配置，释放 443，只留 80 下发订阅
# =========================================================
cat > /etc/nginx/sites-available/default <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    root /var/www/html;
    index index.html;
    server_name _;
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

# =========================================================
# 开启 BBR 加速
# =========================================================
if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
  cat >> /etc/sysctl.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
  sysctl -p
fi

# =========================================================
# 安装并覆盖官方 Xray 核心 (锁定绝对路径)
# =========================================================
echo "[*] 正在部署官方 Xray 核心..."
mkdir -p /usr/local/bin /usr/local/etc/xray
cd /tmp
wget -O xray.zip https://github.com/XTLS/Xray-core/releases/download/v24.11.21/Xray-linux-64.zip || {
  wget -O xray.zip https://mirror.ghproxy.com/https://github.com/XTLS/Xray-core/releases/download/v24.11.21/Xray-linux-64.zip
}
unzip -o xray.zip -d /usr/local/bin/
chmod +x /usr/local/bin/xray
rm -f xray.zip

XRAY_BIN="/usr/local/bin/xray"

# =========================================================
# 纯绝对路径提取高强度密钥 (绝不留空闪退)
# = "serverNames" 纯净伪装苹果官网，去除私人域名特征 =
# =========================================================
$XRAY_BIN x25519 > /tmp/xray_keys.txt
PRIVATE_KEY=$(awk '/Private key:/ {print $3}' /tmp/xray_keys.txt | tr -d '[:space:]')
PUBLIC_KEY=$(awk '/Public key:/ {print $3}' /tmp/xray_keys.txt | tr -d '[:space:]')
rm -f /tmp/xray_keys.txt

cat > ${XRAY_DIR}/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${SERVER_NAME}:443",
          "xver": 0,
          "serverNames": [
            "${SERVER_NAME}"
          ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [
            "${SHORT_ID}"
          ]
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

# =========================================================
# 配置并启动服务
# =========================================================
cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Production Service
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=${XRAY_BIN} run -config /usr/local/etc/xray/config.json
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xray
systemctl restart xray

# =========================================================
# 部署 Nginx 伪装静态页面
# =========================================================
rm -rf /var/www/html/*
cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head><title>Welcome</title></head>
<body><h1>Welcome to nginx!</h1></body>
</html>
EOF

systemctl restart nginx
systemctl enable nginx

# =========================================================
# 安全防火墙：精准防守，严禁锁死当前自定义 SSH 端口
# =========================================================
ufw disable || true
ufw default deny incoming
ufw default allow outgoing
ufw allow ${SSH_PORT}/tcp comment 'Secure SSH Port'
ufw allow 80/tcp comment 'Nginx Sub Port'
ufw allow 443/tcp comment 'Xray Reality Port'
echo "y" | ufw enable

# =========================================================
# 5分钟看门狗自愈脚本
# =========================================================
mkdir -p /usr/local/bin
cat > /usr/local/bin/xray-check.sh <<EOF
#!/usr/bin/env bash
if ! pgrep xray >/dev/null; then
  systemctl daemon-reload
  systemctl restart xray
fi
EOF
chmod +x /usr/local/bin/xray-check.sh

CRON_EXISTING="$(crontab -l 2>/dev/null | grep -v "xray-check.sh" || true)"
TMP_CRON="$(mktemp)"
printf "%s\n" "$CRON_EXISTING" > "$TMP_CRON"
echo "*/5 * * * * /usr/local/bin/xray-check.sh >/dev/null 2>&1" >> "$TMP_CRON"
crontab "$TMP_CRON"
rm -f "$TMP_CRON"

# =========================================================
# 下发自动化订阅文件 (100% 安全本地无源离线打包)
# =========================================================
VLESS_LINK="vless://${UUID}@${PUBLIC_IP}:${PORT}?security=reality&sni=${SERVER_NAME}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&flow=xtls-rprx-vision#Reality_${DOMAIN}"

mkdir -p /var/www/html/sub

# 1. 手机小火箭 Base64 订阅
echo "${VLESS_LINK}" | base64 -w 0 > /var/www/html/sub/${SUB_PATH}

# 2. 电脑 Clash Verge YAML 订阅
cat > /var/www/html/sub/${CLASH_PATH} <<EOF
mixed-port: 7890
allow-lan: true
mode: rule

proxies:
  - name: "Reality_${DOMAIN}"
    type: vless
    server: ${PUBLIC_IP}
    port: ${PORT}
    uuid: ${UUID}
    network: tcp
    tls: true
    flow: xtls-rprx-vision
    servername: ${SERVER_NAME}
    client-fingerprint: chrome
    reality-opts:
      public-key: ${PUBLIC_KEY}
      short-id: ${SHORT_ID}

proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - "Reality_${DOMAIN}"

rules:
  - MATCH,PROXY
EOF

chmod -R 755 /var/www/html

# =========================================================
# 完工信息纯净输出
# =========================================================
clear
echo "================================================="
echo "            工业级自动订阅系统 部署完成"
echo "================================================="
echo
echo "服务器公网 IP : ${PUBLIC_IP}"
echo "当前安全连接端口 : ${SSH_PORT} (已全自动放行，绝无锁死风险)"
echo "------------------------------------------------_"
echo
echo "================================================="
echo " 1. 【📱 Shadowrocket 小火箭】一键订阅链接"
echo "================================================="
echo "http://${DOMAIN}/sub/${SUB_PATH}"
echo "(直接复制此链接，填入小火箭的 [添加订阅] 中即可拉取)"
echo
echo "================================================="
echo " 2. 【💻 Clash Verge Rev / Meta】电脑端一键订阅链接"
echo "================================================="
echo "http://${DOMAIN}/sub/${CLASH_PATH}"
echo "(直接复制此链接，填入 Clash Verge 的 [Profiles] 复制并导入即可)"
echo "================================================="
