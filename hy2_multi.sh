#!/usr/bin/env bash
set -euo pipefail

echo "========================================"
echo " VLESS Reality Stable Install Script"
echo "========================================"

export DEBIAN_FRONTEND=noninteractive

apt update -y
apt install -y curl openssl unzip uuid-runtime wget

# 获取公网 IP
PUBLIC_IP=$(curl -4 -s https://api.ip.sb/ip)

if [[ -z "$PUBLIC_IP" ]]; then
  echo "[ERROR] Failed to get public IP"
  exit 1
fi

echo "[INFO] Public IP: $PUBLIC_IP"

# 安装 Xray
if ! command -v xray >/dev/null 2>&1; then

  cd /tmp

  wget -O xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip

  unzip -o xray.zip

  install -m 755 xray /usr/local/bin/xray

  mkdir -p /usr/local/share/xray

  install -m 644 geoip.dat /usr/local/share/xray/geoip.dat
  install -m 644 geosite.dat /usr/local/share/xray/geosite.dat

fi

# 生成 Reality 密钥
KEYS=$(/usr/local/bin/xray x25519)

PRIVATE_KEY=$(echo "$KEYS" | grep PrivateKey | awk '{print $2}')
PUBLIC_KEY=$(echo "$KEYS" | grep PublicKey | awk '{print $2}')

UUID=$(cat /proc/sys/kernel/random/uuid)

SHORT_ID=$(openssl rand -hex 8)

mkdir -p /usr/local/etc/xray

cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
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
            "www.microsoft.com"
          ],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [
            "$SHORT_ID"
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

cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xray
systemctl restart xray

sleep 2

echo
echo "========================================"
echo " Reality Installed Successfully"
echo "========================================"

echo
echo "VLESS URL:"
echo

echo "vless://${UUID}@${PUBLIC_IP}:443?security=reality&encryption=none&pbk=${PUBLIC_KEY}&type=tcp&flow=xtls-rprx-vision&sni=www.microsoft.com&fp=chrome&sid=${SHORT_ID}#Reality"

echo
echo "========================================"