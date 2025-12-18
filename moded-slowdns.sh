#!/bin/bash

# Color codes
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
GREEN='\033[1;32m'
RED='\033[1;31m'
NC='\033[0m'

# Check root
if [ "$(whoami)" != "root" ]; then
    echo -e "${RED}Error: This script must be run as root.${NC}"
    exit 1
fi

# Function to check if input is a number
is_number() {
    [[ $1 =~ ^[0-9]+$ ]]
}

# Clear screen and show banner
clear
echo -e "${CYAN}=== DNSTT Protocol Installer ===${NC}"
echo -e "${YELLOW}VPN Tunnel Installer by AhmedSCRIPT Hacker${NC}"
echo -e "${GREEN}Version: 4.8${NC}"
echo ""

# Menu (only DNSTT)
echo "1. Install DNSTT, DoH and DoT"
echo "0. Exit"
selected_option=-1
while [ $selected_option -lt 0 ] || [ $selected_option -gt 1 ]; do
    echo -e "${YELLOW}Select a number (0-1):${NC}"
    read input
    if [[ $input =~ ^[0-9]+$ ]]; then
        selected_option=$input
    else
        echo -e "${RED}Invalid input. Please enter a number.${NC}"
    fi
done

if [ "$selected_option" -eq 0 ]; then
    echo "Exiting..."
    exit 0
fi

# -----------------------------
# DNSTT Install
# -----------------------------
echo -e "${YELLOW}Installing DNSTT...${NC}"

apt update && apt upgrade -y
apt install -y wget screen lsof iptables-persistent

# Prepare directories
rm -rf /root/dnstt
mkdir -p /root/dnstt
cd /root/dnstt

# Download DNSTT binaries and keys
wget -O dnstt-server https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/dnstt-server
wget -O server.key https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/server.key
wget -O server.pub https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/server.pub
chmod +x dnstt-server

# Show pubkey to user
echo -e "${CYAN}Your DNSTT Public Key:${NC}"
cat server.pub
read -p "Copy the pubkey above and press Enter when done"

# Ask for NS and target port
read -p "Enter your Nameserver (NS): " ns
while true; do
    read -p "Enter target TCP port (e.g., 22 for SSH): " target_port
    if is_number "$target_port" && [ "$target_port" -ge 1 ] && [ "$target_port" -le 65535 ]; then
        break
    else
        echo -e "${RED}Invalid input. Enter a number 1-65535.${NC}"
    fi
done

# Configure iptables
iptables -I INPUT -p udp --dport 5300 -j ACCEPT
iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300
iptables-save > /etc/iptables/rules.v4

# Ask user if run in background or as systemd
read -p "Run DNSTT in background (screen) or foreground service? (b/f): " run_mode

if [ "$run_mode" = "b" ]; then
    screen -dmS dnstt ./dnstt-server -udp :5300 -privkey-file server.key $ns 127.0.0.1:$target_port -mtu 512
    echo -e "${GREEN}DNSTT running in background screen.${NC}"
else
    cat >/etc/systemd/system/dnstt.service <<EOF
[Unit]
Description=DNSTT Tunnel Server
Wants=network.target
After=network.target

[Service]
ExecStart=/root/dnstt/dnstt-server -udp :5300 -privkey-file /root/dnstt/server.key $ns 127.0.0.1:$target_port -mtu 512
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable dnstt
    systemctl start dnstt
    echo -e "${GREEN}DNSTT running as systemd service.${NC}"
fi

# Show status
lsof -i :5300
echo -e "${CYAN}DNSTT installation completed.${NC}"
