#!/bin/bash

# =========================================
#  SLOWDNS MODED INSTALLER & PANEL
#  Script by esim FREEGB
#  Telegram: https://t.me/esimfreegb
# =========================================

# Colors
GREEN='\033[1;32m'
RED='\033[1;31m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

INFO_FILE="/etc/slowdns-info.conf"

# Root check
[[ $EUID -ne 0 ]] && echo -e "${RED}Run as root${NC}" && exit 1

# -------------------------
# Status check
# -------------------------
check_dnstt_status() {
    if systemctl is-active --quiet dnstt; then
        echo -e "${GREEN}[ON]${NC}"
    else
        echo -e "${RED}[OFF]${NC}"
    fi
}

# -------------------------
# SSH fix
# -------------------------
fix_ssh() {
    mkdir -p /etc/ssh/sshd_config.d/disabled
    mv /etc/ssh/sshd_config.d/*.conf /etc/ssh/sshd_config.d/disabled/ 2>/dev/null

cat >/etc/ssh/sshd_config <<'EOF'
Include /etc/ssh/sshd_config.d/*.conf
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
UsePAM yes
KbdInteractiveAuthentication no
EOF

    systemctl restart ssh
}

# -------------------------
# UDP optimization
# -------------------------
udp_boost() {
cat >/etc/sysctl.d/99-slowdns.conf <<'EOF'
net.core.rmem_max=4194304
net.core.wmem_max=4194304
net.core.netdev_max_backlog=5000
net.ipv4.udp_mem=8388608 12582912 16777216
net.ipv4.udp_rmem_min=16384
net.ipv4.udp_wmem_min=16384
EOF
    sysctl --system >/dev/null
}

# -------------------------
# Install BadVPN
# -------------------------
install_badvpn() {
    wget -qO /usr/bin/badvpn-udpgw https://github.com/ambrop72/badvpn/releases/download/1.999.130/badvpn-udpgw
    chmod +x /usr/bin/badvpn-udpgw

cat >/etc/systemd/system/badvpn.service <<EOF
[Unit]
Description=BadVPN UDPGW
After=network.target

[Service]
ExecStart=/usr/bin/badvpn-udpgw --listen-addr 127.0.0.1:7300
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now badvpn
}

# -------------------------
# Create SSH User
# -------------------------
create_ssh_user() {
    read -p "Username: " u
    id "$u" &>/dev/null && echo -e "${RED}User exists${NC}" && return
    read -s -p "Password: " p; echo
    useradd -m -s /bin/bash "$u"
    echo "$u:$p" | chpasswd
    usermod -aG sudo "$u"
    echo -e "${GREEN}User $u created successfully${NC}"
}

# -------------------------
# Delete SSH User
# -------------------------
delete_ssh_user() {
    users=($(awk -F: '$3>=1000 && $1!="nobody"{print $1}' /etc/passwd))
    [[ ${#users[@]} -eq 0 ]] && echo -e "${RED}No users found${NC}" && return

    for i in "${!users[@]}"; do
        echo "$((i+1)). ${users[$i]}"
    done
    read -p "Select user: " n
    del=${users[$((n-1))]}
    userdel -r "$del" && echo -e "${GREEN}$del deleted${NC}"
}

# -------------------------
# Install SlowDNS
# -------------------------
install_slowdns() {
    apt-get update -y >/dev/null 2>&1
    apt-get install -y wget curl screen iptables-persistent >/dev/null 2>&1

    mkdir -p /root/dnstt
    cd /root/dnstt || exit

    wget -q https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/dnstt-server
    wget -q https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/server.key
    wget -q https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/server.pub
    chmod +x dnstt-server

    read -p "Enter NS Domain: " NS
    echo "1) SSH (22)"
    echo "2) V2Ray (8787)"
    read -p "Choose forwarding port: " psel

    if [[ $psel == "2" ]]; then
        bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
        echo -e "${YELLOW}Complete 3x-ui setup, copy panel info.${NC}"
        read -p "Press Enter to continue..."
        FPORT=8787
    else
        FPORT=22
    fi

cat >/etc/systemd/system/dnstt.service <<EOF
[Unit]
Description=DNSTT Tunnel
After=network.target

[Service]
ExecStart=/root/dnstt/dnstt-server -udp :5300 -mtu 512 -privkey-file /root/dnstt/server.key $NS 127.0.0.1:$FPORT
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now dnstt

    iptables -I INPUT -p udp --dport 5300 -j ACCEPT
    iptables-save > /etc/iptables/rules.v4

    fix_ssh
    udp_boost
    install_badvpn

cat >$INFO_FILE <<EOF
NS_DOMAIN=$NS
FORWARD_PORT=$FPORT
TUNNEL=127.0.0.1:$FPORT
PUBKEY=$(cat /root/dnstt/server.pub)
EOF
}

# -------------------------
# DNSTT Info
# -------------------------
dnstt_info() {
    [[ ! -f $INFO_FILE ]] && echo -e "${RED}Not installed${NC}" && return
    source $INFO_FILE
    echo -e "${CYAN}========= DNSTT INFO =========${NC}"
    echo "NS Domain      : $NS_DOMAIN"
    echo "Tunnel         : $TUNNEL"
    echo "Forward Port   : $FORWARD_PORT"
    echo "Public Key     :"
    echo "$PUBKEY"
    echo
    echo "Use HTTP ASH Tunnel (recommend) ⚡"
    echo "Set segments to 10"
    echo "OR use HTTP Custom ✅"
    echo
    echo "Developer: esim FREEGB"
    echo "Telegram 🇹🇿 : https://t.me/esimfreegb"
}

# -------------------------
# SSH Menu
# -------------------------
ssh_menu() {
while true; do
echo
echo "1. CREATE SSH USER"
echo "2. DELETE SSH USER"
echo "3. CHECK SSH (Coming soon)"
echo "4. BLOCK SSH (Coming soon)"
echo "5. BACK"
read -p "Select: " s
case $s in
1) create_ssh_user ;;
2) delete_ssh_user ;;
5) break ;;
*) echo "Coming soon" ;;
esac
done
}

# -------------------------
# Main Menu
# -------------------------
while true; do
clear
STATUS=$(check_dnstt_status)
echo -e "${CYAN}SLOWDNS MODED PANEL${NC}"
echo
echo -e "1. INSTALL SLOWDNS MODED $STATUS"
echo "2. DNSTT INFO"
echo "3. SSH USER MANAGEMENT"
echo "4. EXIT"
read -p "Select: " m
case $m in
1) install_slowdns ;;
2) dnstt_info; read -p "Press Enter..." ;;
3) ssh_menu ;;
4) exit ;;
esac
done
