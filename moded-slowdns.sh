#!/bin/bash

# ===================================================
# Fast DNSTT Installer (Optimized)
# ===================================================

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# =================== COLORS ===================
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RED='\033[1;31m'
NC='\033[0m'

# =================== CHECK ROOT ===================
if [[ "$(id -u)" -ne 0 ]]; then
    echo -e "${RED}Error: Run this script as root!${NC}"
    exit 1
fi

# =================== FUNCTIONS ===================
print_status() { echo -e "[*] $1"; }
check_status() { if [ $? -eq 0 ]; then echo -e "[✓] Success"; else echo -e "[✗] Failed"; exit 1; fi; }
is_number() { [[ $1 =~ ^[0-9]+$ ]]; }

# =================== CLEAR SCREEN ===================
clear
echo -e "${CYAN}=== Fast DNSTT Installer ===${NC}"
echo -e "${YELLOW}Author: Custom Script${NC}"
echo -e "${GREEN}Version: 2.0${NC}"
echo ""

# =================== STEP 0: FIREWALL/DNS ===================
print_status "Disabling firewalls and systemd-resolved..."
ufw disable 2>/dev/null || true
systemctl stop ufw 2>/dev/null || true
systemctl disable ufw 2>/dev/null || true
systemctl stop systemd-resolved 2>/dev/null || true
systemctl disable systemd-resolved 2>/dev/null || true
[[ -L /etc/resolv.conf ]] && rm -f /etc/resolv.conf
echo -e "nameserver 8.8.8.8\nnameserver 8.8.4.4" > /etc/resolv.conf
chmod 644 /etc/resolv.conf
check_status

# =================== STEP 1: SSH OPTIMIZATION ===================
print_status "Optimizing SSH for VPN tunneling..."
cp -f /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
sed -i 's/#AllowTcpForwarding yes/AllowTcpForwarding yes/g' /etc/ssh/sshd_config
sed -i '/^KexAlgorithms/d;/^Ciphers/d;/^MACs/d' /etc/ssh/sshd_config

cat >> /etc/ssh/sshd_config << EOF

# VPN Client Optimized SSH
KexAlgorithms curve25519-sha256,ecdh-sha2-nistp256,diffie-hellman-group-exchange-sha256
Ciphers aes128-ctr,aes256-ctr,chacha20-poly1305@openssh.com
MACs hmac-sha2-256,hmac-sha2-512
EOF

systemctl restart ssh
check_status

# =================== STEP 2: FAST DEPENDENCY INSTALL ===================
print_status "Installing required packages..."
apt update -qq && apt upgrade -y -qq
apt install -y -qq wget screen lsof iptables-persistent
check_status

# =================== STEP 3: DNSTT SETUP ===================
print_status "Setting up DNSTT..."
rm -rf /root/dnstt
mkdir -p /root/dnstt
cd /root/dnstt || exit 1

# Use parallel wget for speed, quiet mode
print_status "Downloading DNSTT binaries and keys..."
wget -q -O dnstt-server "https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/dnstt-server" &
wget -q -O server.key "https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/server.key" &
wget -q -O server.pub "https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/server.pub" &
wait
chmod +x dnstt-server server.key server.pub
check_status

echo -e "${CYAN}DNSTT Public Key:${NC}"
cat server.pub
read -p "Copy the public key and press Enter..."

# =================== STEP 4: USER CONFIG ===================
while true; do
    read -p "Enter your Nameserver (NS): " ns
    [[ -n "$ns" ]] && break
done

while true; do
    read -p "Enter target TCP port (1-65535, e.g., 22): " target_port
    if is_number "$target_port" && [ "$target_port" -ge 1 ] && [ "$target_port" -le 65535 ]; then
        break
    fi
done

# =================== STEP 5: IPTABLES ===================
print_status "Configuring iptables..."
iptables -I INPUT -p udp --dport 53 -j ACCEPT
iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300
iptables -I INPUT -p tcp --dport "$target_port" -j ACCEPT
iptables-save > /etc/iptables/rules.v4
check_status

# =================== STEP 6: SYSTEMD SERVICE ===================
print_status "Creating DNSTT systemd service..."
cat >/etc/systemd/system/dnstt.service << EOF
[Unit]
Description=DNSTT Tunnel Server
Wants=network.target
After=network.target

[Service]
ExecStart=/root/dnstt/dnstt-server -udp :5300 -mtu 512 -privkey-file /root/dnstt/server.key $ns 127.0.0.1:$target_port
Restart=always
RestartSec=2
User=root
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

chmod 644 /etc/systemd/system/dnstt.service
systemctl daemon-reload
systemctl enable --now dnstt
check_status

# =================== STEP 7: STATUS ===================
print_status "Checking DNSTT status..."
lsof -i :5300 || true
systemctl status dnstt --no-pager -l

echo -e "${GREEN}DNSTT installation completed successfully!${NC}"
echo -e "${YELLOW}Nameserver: $ns | Target Port: $target_port${NC}"
echo -e "${CYAN}Public Key:${NC} $(cat /root/dnstt/server.pub | tr -d '\n')"
