#!/bin/bash

is_number() {
    [[ $1 =~ ^[0-9]+$ ]]
}

# Colors
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
echo ""
echo -e "$YELLOW VPN Tunnel Installer by AhmedSCRIPT Hacker"
echo "Version : 4.8"
echo -e "$NC"

# Menu
echo "Select an option:"
echo "1. Install DNSTT, DoH and DoT"
echo "0. Exit"

selected_option=-1
while [ $selected_option -lt 0 ] || [ $selected_option -gt 1 ]; do
    echo -e "$YELLOW"
    read -p "Enter number (0-1): " input
    echo -e "$NC"
    if [[ $input =~ ^[0-9]+$ ]]; then
        selected_option=$input
    else
        echo -e "$YELLOW Invalid input. Enter a number.$NC"
    fi
done

if [ "$selected_option" -eq 1 ]; then
    echo -e "$YELLOW Installing DNSTT, DoH and DoT... $NC"
    apt -y update && apt -y upgrade
    apt -y install iptables-persistent wget screen lsof sudo

    # Prepare folder
    rm -rf /root/dnstt
    mkdir /root/dnstt
    cd /root/dnstt

    # Download DNSTT server and keys
    wget -O dnstt-server https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/dnstt-server
    chmod 755 dnstt-server    
    wget -O server.key https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/server.key
    wget -O server.pub https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/server.pub

    # Show public key
    echo -e "$CYAN"
    echo "=============================================="
    echo "YOUR DNSTT PUBLIC KEY:"
    cat server.pub
    echo "=============================================="
    echo -e "$NC"
    read -p "Copy the public key above and press Enter when done"

    # Prompt for Nameserver (without touching environment)
    read -p "Enter your Nameserver domain (e.g., ns.example.com): " ns

    # Setup iptables
    iptables -I INPUT -p udp --dport 5300 -j ACCEPT
    iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300
    iptables-save > /etc/iptables/rules.v4

    # Target port
    while true; do
        read -p "Target TCP Port for tunnel host (127.0.0.1:22 recommended): " target_port
        if is_number "$target_port" && [ "$target_port" -ge 1 ] && [ "$target_port" -le 65535 ]; then
            break
        else
            echo -e "$YELLOW Invalid port number. Enter 1-65535.$NC"
        fi
    done

    # Systemd service with MTU 180
    cat >/etc/systemd/system/dnstt.service <<EOF
[Unit]
Description=DNSTT Tunnel Server
Wants=network.target
After=network.target

[Service]
ExecStart=/root/dnstt/dnstt-server -udp :53 -privkey-file /root/dnstt/server.key $ns 127.0.0.1:$target_port
Restart=always
RestartSec=3
Environment="MTU=1800"

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl start dnstt
    systemctl enable dnstt

    lsof -i :5300

    echo -e "$GREEN DNSTT installation completed! $NC"
    echo -e "$CYAN"
    echo "Your DNSTT public key (copy this for client config):"
    cat /root/dnstt/server.pub
    echo -e "$NC"
    echo "Tunnel host: 127.0.0.1:$target_port"
    echo "You can connect using your root username and password or a sudo user."

    # Create new user
    read -p "Enter the username to create for DNSTT tunnel: " tunnel_user
    read -s -p "Enter password for $tunnel_user: " tunnel_pass
    echo
    useradd -m -s /bin/bash "$tunnel_user"
    echo "$tunnel_user:$tunnel_pass" | chpasswd
    usermod -aG sudo "$tunnel_user"
    echo -e "$GREEN User $tunnel_user created with sudo privileges.$NC"

    # Fix SSH root login
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

    echo -e "$YELLOW Rebooting system in 10 seconds... $NC"
    sleep 10
    reboot
else
    echo -e "$YELLOW Goodbye! $NC"
    exit 0
fi
