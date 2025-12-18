#!/bin/bash
set -e

# ================= COLORS =================
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

# ================= ROOT CHECK =================
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

clear
echo -e "$CYAN"
echo "=================================="
echo "        DNSTT SERVER INSTALLER     "
echo "=================================="
echo -e "$NC"

# ================= INSTALL PACKAGES =================
apt update -y && apt upgrade -y
echo -e "$YELLOW Installing required packages... $NC"
apt install -y wget screen lsof iptables iptables-persistent

# ================= FETCH DNSTT BIN & KEYS =================
mkdir -p /root/dnstt
cd /root/dnstt

echo -e "$YELLOW Downloading DNSTT server and keys... $NC"

wget -q https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/dnstt-server
wget -q https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/server.key
wget -q https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/server.pub

chmod +x dnstt-server

echo -e "$YELLOW"
echo "==== PUBLIC KEY (COPY THIS) ===="
cat server.pub
echo "================================"
echo -e "$NC"
read -p "Press ENTER after copying the pubkey above"

# ================= USER INPUT =================
read -p "Enter your DNS domain (example: ns.yourdomain.com): " NS
read -p "Enter target local port (example: SSH/WS/SSL): " TARGET_PORT

# ================= IPTABLES =================
echo -e "$YELLOW Configuring iptables rules... $NC"
iptables -I INPUT -p udp --dport 5300 -j ACCEPT
iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300

# Save iptables rules
iptables-save > /etc/iptables/rules.v4
echo -e "$YELLOW Iptables rules saved. $NC"

# ================= SYSTEMD SERVICE =================
cat >/etc/systemd/system/dnstt.service <<EOF
[Unit]
Description=DNSTT Tunnel Server
After=network.target

[Service]
ExecStart=/root/dnstt/dnstt-server -udp :5300 -privkey-file /root/dnstt/server.key $NS 127.0.0.1:$TARGET_PORT
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable dnstt
systemctl start dnstt

echo -e "$CYAN"
echo "=================================="
echo "   DNSTT INSTALLED SUCCESSFULLY"
echo "   UDP 53 → 5300"
echo "   DNS Domain : $NS"
echo "   Forward to : 127.0.0.1:$TARGET_PORT"
echo "=================================="
echo -e "$NC"

lsof -i :5300
