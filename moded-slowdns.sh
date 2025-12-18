#!/bin/bash

# ==============================
# DNSTT Installer & Dashboard
# ==============================

# Colors
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
GREEN='\033[1;32m'
RED='\033[1;31m'
NC='\033[0m'

# Check root
if [ "$(whoami)" != "root" ]; then
    echo -e "${RED}Error: Run as root${NC}"
    exit 1
fi

# Number check
is_number() { [[ $1 =~ ^[0-9]+$ ]]; }

DNSTT_DIR="/root/dnstt"
INFO_FILE="$DNSTT_DIR/install.info"
SYSTEMD_FILE="/etc/systemd/system/dnstt.service"

# Fix SSH root & password login
echo "[+] Fixing SSH root & password login..."
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
systemctl restart ssh

# UDP Performance Tweaks
sudo tee /etc/sysctl.d/99-slowdns.conf << 'EOF'
net.core.rmem_max=4194304
net.core.wmem_max=4194304
net.core.netdev_max_backlog=5000
net.ipv4.udp_mem=8388608 12582912 16777216
net.ipv4.udp_rmem_min=16384
net.ipv4.udp_wmem_min=16384
EOF
sudo sysctl --system

# Menu
while true; do
    clear
    echo -e "${CYAN}===== DNSTT Installer & Dashboard =====${NC}"
    echo -e "${YELLOW}Script by esim FREEGB (t.me/esimfreegb)${NC}"
    echo ""
    echo "1. Install DNSTT (UDP 5300)"
    echo "2. DNSTT Info"
    echo "3. Exit"
    echo ""
    read -p "Choose an option: " option

    case $option in
        1)
            echo -e "${YELLOW}Installing DNSTT...${NC}"
            apt update && apt upgrade -y
            apt install -y wget screen lsof iptables-persistent curl

            # Prepare folder
            rm -rf $DNSTT_DIR
            mkdir -p $DNSTT_DIR
            cd $DNSTT_DIR

            # Download DNSTT
            wget -O dnstt-server https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/dnstt-server
            wget -O server.key https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/server.key
            wget -O server.pub https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/server.pub
            chmod +x dnstt-server

            # Ask NS and ports
            read -p "Enter your Nameserver (NS domain): " NS_DOMAIN

            while true; do
                read -p "Enter forwarding port (SSH 22 or V2Ray 8787): " FWD_PORT
                if is_number "$FWD_PORT" && [ "$FWD_PORT" -ge 1 ] && [ "$FWD_PORT" -le 65535 ]; then
                    break
                else
                    echo -e "${RED}Invalid input.${NC}"
                fi
            done

            # Auto-install 3x-ui if 8787
            if [ "$FWD_PORT" -eq 8787 ]; then
                echo -e "${YELLOW}Installing 3x-ui...${NC}"
                bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
                echo -e "${GREEN}Complete 3x-ui setup. Copy your username/password and web URL. Press Enter to continue.${NC}"
                read
            fi

            # Configure iptables
            iptables -I INPUT -p udp --dport 5300 -j ACCEPT
            iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300
            iptables-save > /etc/iptables/rules.v4

            # Systemd service
            cat >$SYSTEMD_FILE <<EOF
[Unit]
Description=DNSTT Tunnel Server
Wants=network.target
After=network.target

[Service]
ExecStart=$DNSTT_DIR/dnstt-server -udp :5300 -privkey-file $DNSTT_DIR/server.key $NS_DOMAIN 127.0.0.1:$FWD_PORT -mtu 512
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

            systemctl daemon-reload
            systemctl enable dnstt
            systemctl start dnstt

            # Store install info
            echo "NS_DOMAIN=$NS_DOMAIN" > $INFO_FILE
            echo "FWD_PORT=$FWD_PORT" >> $INFO_FILE
            echo "PUBKEY=$(cat $DNSTT_DIR/server.pub)" >> $INFO_FILE
            echo "TUNNEL=127.0.0.1:$FWD_PORT" >> $INFO_FILE

            # Optional BadVPN install
            echo -e "${YELLOW}Do you want to install BadVPN UDPGW on port 7300? (y/n)${NC}"
            read bport
            if [ "$bport" = "y" ]; then
                mkdir -p /root/badvpn && cd /root/badvpn
                wget https://raw.githubusercontent.com/ASHANTENNA/VPNScript/main/badvpn-udpgw
                chmod +x badvpn-udpgw
                cat >/etc/systemd/system/badvpn.service <<EOF
[Unit]
Description=Badvpn UDPGW Server
Wants=network.target
After=network.target
[Service]
ExecStart=/root/badvpn/badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 1000 --max-connections-for-client 10 --loglevel 0
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
                systemctl daemon-reload
                systemctl enable badvpn
                systemctl start badvpn
            fi

            echo -e "${GREEN}DNSTT installed successfully.${NC}"
            echo -e "You can now check status with: ${CYAN}systemctl status dnstt${NC}"
            read -p "Press Enter to return to menu..."
            ;;
        2)
            # -----------------------------
            # DNSTT Info Dashboard
            # -----------------------------
            if [ ! -f $INFO_FILE ]; then
                echo -e "${RED}No installation info found.${NC}"
                read -p "Press Enter to return to menu..."
                continue
            fi

            source $INFO_FILE

            echo -e "${CYAN}==============================${NC}"
            echo -e "${CYAN}     DNSTT Tunnel Info        ${NC}"
            echo -e "${CYAN}==============================${NC}"
            echo -e "${YELLOW}NS / Domain       : ${GREEN}$NS_DOMAIN${NC}"
            echo -e "${YELLOW}DNSTT Public Key  : ${GREEN}$PUBKEY${NC}"
            echo -e "${YELLOW}Forwarding Port   : ${GREEN}$FWD_PORT${NC}"
            echo -e "${YELLOW}Tunnel Address    : ${GREEN}$TUNNEL${NC}"
            echo -e "${CYAN}Note: You can change forwarding port in the systemd service and restart.${NC}"
            echo -e "${CYAN}Check DNSTT status: systemctl status dnstt${NC}"
            echo -e "${CYAN}==============================${NC}"
            read -p "Press Enter to return to menu..."
            ;;
        3)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option.${NC}"
            ;;
    esac
done
