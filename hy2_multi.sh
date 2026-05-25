#!/usr/bin/env bash
set -euo pipefail

echo "=========================================================="
echo "      工业级 REALITY 多节点通用部署脚本 (终极稳固版)      "
echo "=========================================================="

export DEBIAN_FRONTEND=noninteractive
apt-get update -y && apt-get install -y curl jq openssl uuid-runtime cron net-tools

# 1. 自动获取准确的公网 IPv4
PUBLIC_IP=$(curl -4 -s --connect-timeout 5 https://api.ip.sb/ip || curl -4 -s --connect-timeout 5 https://ifconfig.me || echo "")
if [ -z "$PUBLIC_IP" ]; then
  echo "[ERROR] 无法获取外部公网 IP，请检查 VPS 网络环境。"
  exit 1
fi

# 2. 自动拉取官方 Xray 核心
if ! command -v xray >/dev/null 2>&1; then
  echo "[*] 正在拉取官方 Xray 核心..."
  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
fi

# 3. 交互式获取域名
if [ -t 0 ]; then
  read -r -p "请输入您在 Cloudflare 解析的域名 (如 vps1.1564151.xyz 或 1564151.xyz): " DOMAIN || true
else
  echo "[ERROR] 必须在交互式终端运行以输入域名"
  exit 1
fi

if [ -z "${DOMAIN:-}" ]; then
  echo "[ERROR] 域名不能为空。"
  exit 1
fi

# 4. 【彻底焊死修复点】用高阶手法完美生成并纯化密钥，绝不留空
UUID="$(uuidgen)"
PORT="443"
SID="$(openssl rand -hex 8)"

# 强行落盘临时文件提取，彻底解决由于系统组件引发的字符截断和空值闪退
/usr/local/bin/xray x25519 > /tmp/xray_keys.txt
PRIVATE_KEY=$(awk '/Private key:/ {print $3}' /tmp/xray_keys.txt | tr -d '[:space:]')
PUBLIC_KEY=$(awk '/Public key:/ {print $3}' /tmp/xray_keys.txt | tr -d '[:space:]')
rm -f /tmp/xray_keys.txt

if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
  echo "[ERROR] 密钥对生成异常，脚本自动终止。"
  exit 1
fi

# 5. 写入纯净无瑕疵的 Xray 配置文件
mkdir -p /usr/local/etc/xray
cat > /usr/local/etc/xray/config.json <<EOF
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
          "dest": "www.microsoft.com:443",
          "serverNames": [
            "www.microsoft.com",
            "${DOMAIN}"
          ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": ["${SID}"]
        },
        "tcpSettings": {
          "sockopt": {
            "tcpKeepAliveIdle": 30
          }
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "direct"
    }
  ]
}
EOF

# 6. 配置并拉起 Systemd 系统服务守护
cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Production Service
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xray
systemctl restart xray

# 7. 配置 5 分钟进程探活自愈看门狗
mkdir -p /usr/local/bin
cat > /usr/local/bin/xray-check.sh <<'EOF'
#!/usr/bin/env bash
if ! pgrep xray >/dev/null; then
  systemctl daemon-reload
  systemctl restart xray
fi
EOF
chmod +x /usr/local/bin/xray-check.sh

CRON_EXISTING="$(crontab -l 2>/dev/null | grep -v "xray-check.sh" | grep -v "reboot" || true)"
TMP_CRON="$(mktemp)"
printf "%s\n" "$CRON_EXISTING" > "$TMP_CRON"
echo "*/5 * * * * /usr/local/bin/xray-check.sh >/dev/null 2>&1" >> "$TMP_CRON"
echo "0 4 * * 1 /sbin/reboot" >> "$TMP_CRON"
crontab "$TMP_CRON"
rm -f "$TMP_CRON"

# 8. 拼装客户端输出
URI="vless://${UUID}@${PUBLIC_IP}:${PORT}?security=reality&encryption=none&pbk=${PUBLIC_KEY}&sni=www.microsoft.com&flow=xtls-rprx-vision&type=tcp&sid=${SID}#Reality_Node_${PUBLIC_IP}"

echo
echo "==================== 工业级多节点通用版部署成功 ===================="
echo "公网IP: $PUBLIC_IP"
echo "绑定的域名: $DOMAIN"
echo "------------------------------------------------------------------"
echo "【📱 Shadowrocket 小火箭专用单行链接】(直接整行复制导入):"
echo "$URI"
echo "------------------------------------------------------------------"
echo "【💻 Clash Verge 专用配置格式】(复制粘贴进 YAML 的 proxies 列表下):"
echo "  - name: \"Reality_Node_${PUBLIC_IP}\""
echo "    type: vless"
echo "    server: $PUBLIC_IP"
echo "    port: 443"
echo "    uuid: $UUID"
echo "    cipher: auto"
echo "    tls: true"
echo "    flow: xtls-rprx-vision"
echo "    servername: www.microsoft.com"
echo "    network: tcp"
echo "    udp: true"
echo "    reality-opts:"
echo "      public-key: $PUBLIC_KEY"
echo "      short-id: $SID"
echo "=================================================================="