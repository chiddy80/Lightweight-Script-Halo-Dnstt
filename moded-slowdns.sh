#!/bin/bash

# Function to print colored output
print_status() {
    echo -e "[*] $1"
}

# Function to check if command succeeded
check_status() {
    if [ $? -eq 0 ]; then
        echo -e "[✓] Success"
    else
        echo -e "[✗] Failed"
        exit 1
    fi
}

# ====================== NEW ADDITIONS ======================
print_status "Setting up SSLH multiplexer..."

# Install SSLH if not installed
if ! command -v sslh &> /dev/null; then
    print_status "Installing SSLH..."
    apt-get update
    apt-get install -y sslh
    check_status
fi

# Configure SSLH to handle multiple protocols
print_status "Configuring SSLH..."
cat > /etc/default/sslh <<EOF
# Default options for sslh initscript
# sourced by /etc/init.d/sslh

# Disable ipv6?
DISABLE_IPV6=1

# Change this to your user and group
RUN=root

#DAEMON=/usr/sbin/sslh

# What to listen to (can be multiple addresses)
# Here: listen to incoming HTTPS (443) and SSH (22) connections
LISTEN_IP=0.0.0.0
LISTEN_PORT=443

# outgoing connections appear from this ip
#SOURCE_IP=0.0.0.0

# Add other options here (see sslh(8) for more options)
DAEMON_OPTS="--user root --transparent --on-timeout ssl --timeout 3 --listen \$LISTEN_IP:\$LISTEN_PORT \
--ssh 127.0.0.1:22 \
--ssl 127.0.0.1:4443 \
--openvpn 127.0.0.1:1194 \
--anyprot 127.0.0.1:2222"
EOF

print_status "Configuring rc.local for auto-start..."
cat > /etc/rc.local <<-END
#!/bin/sh -e
# rc.local
# By default this script does nothing.

# Auto-start SSLH
systemctl start sslh

# Auto-start BadVPN UDPGW (for gaming/streaming)
screen -dmS badvpn badvpn-udpgw --listen-addr 127.0.0.1:7100 --max-clients 500
screen -dmS badvpn badvpn-udpgw --listen-addr 127.0.0.1:7200 --max-clients 500
screen -dmS badvpn badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 500

# Redirect DNS traffic to SlowDNS
iptables -I INPUT -p udp --dport 5300 -j ACCEPT
iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300

# Enable SSLH transparent mode rules
iptables -t mangle -N SSLH
iptables -t mangle -A OUTPUT --protocol tcp --out-interface lo --sport 443 --jump SSLH
iptables -t mangle -A SSLH --jump MARK --set-mark 0x1
iptables -t mangle -A SSLH --jump ACCEPT

ip rule add fwmark 0x1 lookup 100
ip route add local 0.0.0.0/0 dev lo table 100

exit 0
END

# Make rc.local executable
chmod +x /etc/rc.local

# Enable rc-local service
systemctl enable rc-local
systemctl start rc-local.service

# Disable IPv6
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6
sed -i '$ i\echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6' /etc/rc.local

print_status "Starting SSLH service..."
systemctl enable sslh
systemctl start sslh
check_status
# ====================== END NEW ADDITIONS ======================

print_status "Disabling UFW..."
sudo ufw disable 2>/dev/null
check_status

if systemctl is-active --quiet ufw; then
    print_status "Stopping UFW service..."
    sudo systemctl stop ufw
    check_status
fi

print_status "Disabling UFW from auto-start..."
systemctl disable ufw 2>/dev/null
check_status

print_status "Disabling systemd-resolved..."
if systemctl is-active --quiet systemd-resolved; then
    systemctl stop systemd-resolved
    check_status
fi

sudo systemctl disable systemd-resolved 2>/dev/null
check_status

if [ -L /etc/resolv.conf ]; then
    print_status "Removing resolv.conf symlink..."
    rm -f /etc/resolv.conf
    check_status
fi

print_status "Creating new resolv.conf with Google DNS..."
echo -e "nameserver 8.8.8.8\nnameserver 8.8.4.4" | tee /etc/resolv.conf > /dev/null
check_status

print_status "Configuring SSH for multiple ports..."
# Add multiple SSH ports for different users
SSH_PORTS="22 2222 2223 2224 2225 2226"

for port in $SSH_PORTS; do
    if ! grep -q "Port $port" /etc/ssh/sshd_config; then
        echo "Port $port" | sudo tee -a /etc/ssh/sshd_config > /dev/null
    fi
done

sed -i 's/#AllowTcpForwarding yes/AllowTcpForwarding yes/g' /etc/ssh/sshd_config
check_status

print_status "Restarting SSH service..."
systemctl restart sshd
check_status

print_status "Setting up SlowDNS..."
rm -rf /etc/slowdns
mkdir -p /etc/slowdns
chmod 777 /etc/slowdns

print_status "Downloading SlowDNS files..."
wget -q -O /etc/slowdns/server.key "https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/server.key"
check_status

wget -q -O /etc/slowdns/server.pub "https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/server.pub"
check_status

wget -q -O /etc/slowdns/sldns-server "https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/dnstt-server"
check_status

chmod +x /etc/slowdns/server.key /etc/slowdns/server.pub /etc/slowdns/sldns-server
check_status

cd ~ || exit 1

print_status "Configuring SlowDNS service..."
read -p "Enter nameserver: " NAMESERVER

if [ -z "$NAMESERVER" ]; then
    echo "[!] Error: Nameserver cannot be empty!"
    exit 1
fi

print_status "How many tunnels do you want to create? (Each for different users)"
read -p "Enter number of tunnels (1-10): " NUM_TUNNELS

if ! [[ "$NUM_TUNNELS" =~ ^[1-9]$|^10$ ]]; then
    echo "[!] Error: Please enter a number between 1-10!"
    exit 1
fi

# Remove existing services
for i in {1..10}; do
    systemctl stop server-sldns-$i 2>/dev/null
    systemctl disable server-sldns-$i 2>/dev/null
    rm -f /etc/systemd/system/server-sldns-$i.service 2>/dev/null
done

# Create multiple tunnels on different UDP ports
for ((i=1; i<=NUM_TUNNELS; i++)); do
    UDP_PORT=$((5300 + i - 1))
    SSH_PORT=$((2221 + i))
    
    if [ $i -eq 1 ]; then
        SSH_PORT=22
    fi
    
    print_status "Creating tunnel $i on UDP:$UDP_PORT -> SSH:$SSH_PORT..."
    
    tee /etc/systemd/system/server-sldns-$i.service > /dev/null <<EOF
[Unit]
Description=DNSTT Tunnel $i (UDP:$UDP_PORT -> SSH:$SSH_PORT)
After=network.target

[Service]
Type=simple
ExecStart=/etc/slowdns/sldns-server -udp :$UDP_PORT -mtu 512 -privkey-file /etc/slowdns/server.key $NAMESERVER 127.0.0.1:$SSH_PORT
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 /etc/systemd/system/server-sldns-$i.service
    
    print_status "Starting tunnel $i..."
    systemctl daemon-reload
    systemctl enable server-sldns-$i
    systemctl start server-sldns-$i
    check_status
    
    echo "Tunnel $i: UDP:$UDP_PORT → SSH:$SSH_PORT"
done

# ====================== ADDITIONAL FIXES ======================
print_status "Setting up SSLH fix for reboot issues..."

# Download and install the SSLH fix script
cd /usr/bin || exit 1
wget -q -O sl-fix "https://raw.githubusercontent.com/athumani2580/DNS/main/sslh-fix/sl-fix"
chmod +x sl-fix

# Download the SSLH fix reboot script
wget -q -O sslh-fix-reboot "https://raw.githubusercontent.com/athumani2580/DNS/main/sslh-fix/sslh-fix-reboot.sh"
chmod +x sslh-fix-reboot

cd ~ || exit 1

# Install BadVPN for UDP gaming/streaming
print_status "Installing BadVPN UDPGW..."
wget -q -O /usr/bin/badvpn-udpgw "https://raw.githubusercontent.com/daybreakersx/premscript/master/badvpn-udpgw64"
chmod +x /usr/bin/badvpn-udpgw
check_status

# Add iptables rules for DNS redirection
print_status "Setting iptables rules for DNS..."
iptables -I INPUT -p udp --dport 5300 -j ACCEPT
iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300

# Save iptables rules
apt-get install -y iptables-persistent
iptables-save > /etc/iptables/rules.v4
# ====================== END ADDITIONAL FIXES ======================

print_status "Setting firewall rules..."
# Allow all UDP ports for SlowDNS
for ((i=1; i<=NUM_TUNNELS; i++)); do
    UDP_PORT=$((5300 + i - 1))
    ufw allow $UDP_PORT/udp 2>/dev/null
done

# Allow all SSH ports
for port in $SSH_PORTS; do
    ufw allow $port/tcp 2>/dev/null
done

# Allow SSLH port
ufw allow 443/tcp 2>/dev/null

print_status "Removing password complexity module..."
sudo apt-get remove -y libpam-pwquality 2>/dev/null || true

print_status "Running final SSLH fix..."
/usr/bin/sslh-fix-reboot
check_status

echo ""
echo "========================================"
echo "Setup completed successfully!"
echo "========================================"
echo ""
echo "Multiple tunnels created:"

for ((i=1; i<=NUM_TUNNELS; i++)); do
    UDP_PORT=$((5300 + i - 1))
    SSH_PORT=$((2221 + i))
    if [ $i -eq 1 ]; then
        SSH_PORT=22
    fi
    echo "Tunnel $i: UDP:$UDP_PORT → SSH:$SSH_PORT"
done

echo ""
echo "Share these with your users:"
echo "Nameserver: $NAMESERVER"
echo "Public Key:"
cat /etc/slowdns/server.pub
echo ""
echo "SSLH is running on port 443 (handles SSH/SSL/OpenVPN)"
echo "SlowDNS is running on UDP ports 5300-53XX"
echo ""
echo "Checking service status..."
for ((i=1; i<=NUM_TUNNELS; i++)); do
    echo ""
    echo "=== Tunnel $i Status ==="
    systemctl status server-sldns-$i --no-pager -l | head -10
done

echo ""
echo "=== SSLH Status ==="
systemctl status sslh --no-pager -l | head -10
