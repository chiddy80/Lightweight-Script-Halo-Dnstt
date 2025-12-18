#!/bin/bash
# DNSTT Installer - Clean Version

# Color codes
YELLOW='\033[1;33m'
RED='\033[1;31m'
CYAN='\033[1;36m'
GREEN='\033[1;32m'
NC='\033[0m'

# Check root
if [ "$(whoami)" != "root" ]; then
    echo "Error: This script must be run as root."
    exit 1
fi

# Banner
clear
echo -e "$CYAN   A   $YELLOW SSS  $RED H   H"
echo -e "$CYAN  A A  $YELLOW S    $RED H   H"
echo -e "$CYAN AAAAA $YELLOW SSS  $RED HHHHH"
echo -e "$CYAN A   A $YELLOW     S$RED H   H"
echo -e "$CYAN A   A $YELLOW SSSS $RED H   H"
echo -e "$NC"
echo -e "$YELLOW VPN Tunnel Installer by AhmedSCRIPT Hacker$NC"
echo -e "Version : 4.8\n"

# Menu
echo "1. Install DNSTT Tunnel"
echo "0. Exit"

while true; do
    echo -e "$YELLOW\nSelect a number (0-1):$NC"
    read -r option
    if [[ "$option" =~ ^[0-1]$ ]]; then
        break
    else
        echo -e "$RED Invalid input, try again.$NC"
    fi
done

if [ "$option" -eq 0 ]; then
    exit 0
fi

# Option 1: DNSTT
echo -e "$YELLOW\nInstalling DNSTT, DoH and DoT...$NC"
apt -y update && apt -y upgrade
apt -y install iptables-persistent wget screen lsof

rm -rf /root/dnstt
mkdir -p /root/dnstt
cd /root/dnstt

# Download latest DNSTT files from your GitHub
wget -O dnstt-server https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/dnstt-server
wget -O server.key https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/server.key
wget -O server.pub https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/server.pub

chmod +x dnstt-server

# Show public key
echo -e "$GREEN\n[+] DNSTT Public Key (copy this!)$NC"
cat server.pub
read -p "Press Enter after you copied the pubkey"

# Ask NS and target port
read -p "Enter your Nameserver (NS): " ns

while true; do
    read -p "Target TCP Port (for tunneling): " target_port
    if [[ "$target_port" =~ ^[0-9]+$ ]] && [ "$target_port" -ge 1 ] && [ "$target_port" -le 65535 ]; then
        break
    else
        echo -e "$RED Invalid port, enter 1-65535.$NC"
    fi
done

# IPTables
iptables -I INPUT -p udp --dport 5300 -j ACCEPT
iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300
iptables-save > /etc/iptables/rules.v4

# Background or systemd service
read -p "Run in background (screen) or systemd service? (b/s): " run_mode

if [ "$run_mode" = "b" ]; then
    screen -dmS slowdns ./dnstt-server -udp :5300 -privkey-file server.key "$ns" 127.0.0.1:"$target_port" -mtu 512
    echo -e "$GREEN[+] DNSTT is running in screen session 'slowdns'.$NC"
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
    echo -e "$GREEN[+] DNSTT is running as systemd service 'dnstt'.$NC"
fi

lsof -i :5300
echo -e "$GREEN[+] DNSTT installation completed successfully.$NC"
