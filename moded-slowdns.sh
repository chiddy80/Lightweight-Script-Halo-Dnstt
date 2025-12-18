#!/bin/bash
# DNSTT Installer Script with SSH Fix and MTU 512
# By ChatGPT (customized)

YELLOW='\033[1;33m'
RED='\033[1;31m'
CYAN='\033[1;36m'
GREEN='\033[1;32m'
NC='\033[0m'

is_number() { [[ $1 =~ ^[0-9]+$ ]]; }

if [ "$(whoami)" != "root" ]; then
    echo -e "${RED}Error: Run this script as root.${NC}"
    exit 1
fi

echo -e "${CYAN}Installing DNSTT server...${NC}"

# Dependencies
apt update && apt -y upgrade
apt -y install wget screen lsof iptables-persistent

# Create DNSTT directory
mkdir -p /root/dnstt && cd /root/dnstt

# Download DNSTT server and keys
wget -q https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/dnstt-server -O dnstt-server
wget -q https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/server.key -O server.key
wget -q https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/server.pub -O server.pub
chmod +x dnstt-server

# Ask for Nameserver
echo -e "${YELLOW}Enter your Nameserver domain (e.g., ns.example.com):${NC}"
read -r NS_DOMAIN

# Ask for Target TCP port
while true; do
    read -p "Target TCP port (for tunnel, e.g., 22): " TARGET_PORT
    if is_number "$TARGET_PORT" && [ "$TARGET_PORT" -ge 1 ] && [ "$TARGET_PORT" -le 65535 ]; then break; fi
    echo -e "${RED}Invalid port. Must be 1-65535.${NC}"
done

# IPTables setup for UDP 53 → DNSTT 5300
iptables -I INPUT -p udp --dport 5300 -j ACCEPT
iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300
iptables-save > /etc/iptables/rules.v4

# Run DNSTT in screen with MTU 512
screen -dmS dnstt ./dnstt-server -udp :5300 -mtu 512 -privkey-file server.key "$NS_DOMAIN" 127.0.0.1:"$TARGET_PORT"

# Fix SSH root login & password
echo "[+] Fixing SSH root login & password..."
mkdir -p /etc/ssh/sshd_config.d/disabled
for f in /etc/ssh/sshd_config.d/*.conf; do
    mv "$f" /etc/ssh/sshd_config.d/disabled/ 2>/dev/null
done

cat >/etc/ssh/sshd_config <<'EOF'
Include /etc/ssh/sshd_config.d/*.conf
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
UsePAM yes
KbdInteractiveAuthentication no
EOF

systemctl restart sshd

# Optional: create a new user with sudo
echo -e "${YELLOW}Do you want to create a new user with sudo privileges? (y/n):${NC}"
read -r CREATE_USER
if [[ "$CREATE_USER" == "y" ]]; then
    read -p "Enter username: " NEW_USER
    read -s -p "Enter password: " NEW_PASS
    echo
    useradd -m -s /bin/bash "$NEW_USER"
    echo "$NEW_USER:$NEW_PASS" | chpasswd
    usermod -aG sudo "$NEW_USER"
    echo -e "${GREEN}User $NEW_USER created with sudo privileges.${NC}"
fi

# Show public key info
echo -e "${CYAN}\n[+] DNSTT Public Key:${NC}"
cat server.pub
echo -e "${YELLOW}\nCopy this DNSTT public key and set it on your client."
echo "Your tunnel host is 127.0.0.1:$TARGET_PORT"
echo "Use your root username and password, or the created user, to connect.${NC}"

# Reboot
echo -e "${RED}\nRebooting in 5 seconds...${NC}"
sleep 5
reboot
