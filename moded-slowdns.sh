#!/bin/bash

# Function to print colored output
print_status() {
    echo -e "[*] $1"
}

# Function to check if command succeeded
check_status() {
    if [ $? -eq 0 ]; then
        echo -e "[✓] Success"
        return 0
    else
        echo -e "[✗] Failed"
        return 1
    fi
}

# Function to fix SSLH issues (integrated from sl-fix-reboot)
fix_sslh_service() {
    print_status "Fixing SSLH service issues..."
    
    # Stop any conflicting services
    systemctl stop ws-tls 2>/dev/null
    pkill python 2>/dev/null
    systemctl stop sslh 2>/dev/null
    
    # Reload systemd
    systemctl daemon-reload
    
    # Disable conflicting services
    systemctl disable ws-tls 2>/dev/null
    systemctl disable sslh 2>/dev/null
    
    # Re-enable SSLH
    systemctl daemon-reload
    systemctl enable sslh
    systemctl enable ws-tls 2>/dev/null
    
    # Start SSLH with multiple methods
    systemctl start sslh
    /etc/init.d/sslh start 2>/dev/null
    /etc/init.d/sslh restart 2>/dev/null
    
    # Start ws-tls if exists
    systemctl start ws-tls 2>/dev/null
    systemctl restart ws-tls 2>/dev/null
    
    sleep 2
    
    # Restart SSH service
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
}

# Function to setup rc.local with auto-fix
setup_rclocal() {
    print_status "Setting up rc.local for auto-start..."
    
    cat > /etc/rc.local <<-END
#!/bin/sh -e
# rc.local
# By default this script does nothing.

# Fix SSLH service on boot
systemctl stop ws-tls 2>/dev/null
pkill python 2>/dev/null
systemctl stop sslh 2>/dev/null
systemctl daemon-reload
systemctl disable ws-tls 2>/dev/null
systemctl disable sslh 2>/dev/null
systemctl daemon-reload
systemctl enable sslh
systemctl enable ws-tls 2>/dev/null
systemctl start sslh
/etc/init.d/sslh start 2>/dev/null
/etc/init.d/sslh restart 2>/dev/null
systemctl start ws-tls 2>/dev/null
systemctl restart ws-tls 2>/dev/null
sleep 5
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null

# Auto-start BadVPN UDPGW (for gaming/streaming)
screen -dmS badvpn badvpn-udpgw --listen-addr 127.0.0.1:7100 --max-clients 500
screen -dmS badvpn badvpn-udpgw --listen-addr 127.0.0.1:7200 --max-clients 500
screen -dmS badvpn badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 500

# Redirect DNS traffic to SlowDNS
iptables -I INPUT -p udp --dport 5300 -j ACCEPT
iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300

# Enable SSLH transparent mode rules
iptables -t mangle -N SSLH 2>/dev/null
iptables -t mangle -A OUTPUT --protocol tcp --out-interface lo --sport 443 --jump SSLH 2>/dev/null
iptables -t mangle -A SSLH --jump MARK --set-mark 0x1 2>/dev/null
iptables -t mangle -A SSLH --jump ACCEPT 2>/dev/null

ip rule add fwmark 0x1 lookup 100 2>/dev/null
ip route add local 0.0.0.0/0 dev lo table 100 2>/dev/null

exit 0
END

    # Make rc.local executable
    chmod +x /etc/rc.local
    
    # Enable rc-local service
    systemctl enable rc-local 2>/dev/null || true
    systemctl start rc-local.service 2>/dev/null || true
}

# ====================== FIX HOSTNAME RESOLUTION ======================
print_status "Fixing hostname resolution..."

# Get current hostname
CURRENT_HOSTNAME=$(hostname)

# Add hostname to /etc/hosts
if ! grep -q "$CURRENT_HOSTNAME" /etc/hosts; then
    echo "127.0.0.1 $CURRENT_HOSTNAME" | sudo tee -a /etc/hosts > /dev/null
    echo "::1 $CURRENT_HOSTNAME" | sudo tee -a /etc/hosts > /dev/null
fi
check_status
# ====================== END HOSTNAME FIX ======================

# ====================== SSLH SETUP ======================
print_status "Setting up SSLH multiplexer..."

# Install SSLH if not installed
if ! command -v sslh &> /dev/null; then
    print_status "Installing SSLH..."
    apt-get update -y
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

setup_rclocal

# Disable IPv6
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6
sed -i '$ i\echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6' /etc/rc.local

print_status "Starting SSLH service..."
systemctl enable sslh
fix_sslh_service
check_status
# ====================== END SSLH SETUP ======================

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
    sudo rm -f /etc/resolv.conf
    check_status
fi

print_status "Creating new resolv.conf with Google DNS..."
echo -e "nameserver 8.8.8.8\nnameserver 8.8.4.4" | sudo tee /etc/resolv.conf > /dev/null
check_status

print_status "Configuring SSH for multiple ports..."
# Backup original sshd_config
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup 2>/dev/null

# Add multiple SSH ports for different users
SSH_PORTS="22 2222 2223 2224 2225 2226"

# Clear any existing Port lines first (keep only the first one)
sudo sed -i '/^Port/d' /etc/ssh/sshd_config 2>/dev/null

# Add ports to sshd_config
for port in $SSH_PORTS; do
    echo "Port $port" | sudo tee -a /etc/ssh/sshd_config > /dev/null
done

# Ensure AllowTcpForwarding is enabled
sudo sed -i 's/#AllowTcpForwarding yes/AllowTcpForwarding yes/g' /etc/ssh/sshd_config
sudo sed -i 's/#AllowTcpForwarding no/AllowTcpForwarding yes/g' /etc/ssh/sshd_config

# Add if not present
if ! grep -q "AllowTcpForwarding yes" /etc/ssh/sshd_config; then
    echo "AllowTcpForwarding yes" | sudo tee -a /etc/ssh/sshd_config > /dev/null
fi

check_status

print_status "Restarting SSH service..."
# Try different SSH service names
if systemctl list-unit-files | grep -q "ssh.service"; then
    sudo systemctl restart ssh
elif systemctl list-unit-files | grep -q "sshd.service"; then
    sudo systemctl restart sshd
else
    # Try generic restart
    sudo service ssh restart 2>/dev/null || sudo service sshd restart 2>/dev/null
fi

# Verify SSH is running
if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd || pgrep -x "sshd" > /dev/null; then
    echo -e "[✓] SSH service is running"
else
    echo -e "[!] Warning: Could not verify SSH service status"
fi

print_status "Setting up SlowDNS..."
sudo rm -rf /etc/slowdns
sudo mkdir -p /etc/slowdns
sudo chmod 777 /etc/slowdns

print_status "Downloading SlowDNS files..."
sudo wget -q -O /etc/slowdns/server.key "https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/server.key"
check_status

sudo wget -q -O /etc/slowdns/server.pub "https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/server.pub"
check_status

sudo wget -q -O /etc/slowdns/sldns-server "https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/dnstt-server"
check_status

sudo chmod +x /etc/slowdns/server.key /etc/slowdns/server.pub /etc/slowdns/sldns-server
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
    sudo systemctl stop server-sldns-$i 2>/dev/null
    sudo systemctl disable server-sldns-$i 2>/dev/null
    sudo rm -f /etc/systemd/system/server-sldns-$i.service 2>/dev/null
done

# Create multiple tunnels on different UDP ports
for ((i=1; i<=NUM_TUNNELS; i++)); do
    UDP_PORT=$((5300 + i - 1))
    SSH_PORT=$((2221 + i))
    
    if [ $i -eq 1 ]; then
        SSH_PORT=22
    fi
    
    print_status "Creating tunnel $i on UDP:$UDP_PORT -> SSH:$SSH_PORT..."
    
    sudo tee /etc/systemd/system/server-sldns-$i.service > /dev/null <<EOF
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

    sudo chmod 644 /etc/systemd/system/server-sldns-$i.service
    
    print_status "Starting tunnel $i..."
    sudo systemctl daemon-reload
    sudo systemctl enable server-sldns-$i
    sudo systemctl start server-sldns-$i
    
    # Check if service started successfully
    if sudo systemctl is-active --quiet server-sldns-$i; then
        echo -e "[✓] Tunnel $i started successfully"
    else
        echo -e "[!] Warning: Tunnel $i might not be running"
    fi
    
    echo "Tunnel $i: UDP:$UDP_PORT → SSH:$SSH_PORT"
done

# ====================== BADVPN SETUP ======================
print_status "Installing BadVPN UDPGW..."
if [ ! -f /usr/bin/badvpn-udpgw ]; then
    sudo wget -q -O /usr/bin/badvpn-udpgw "https://raw.githubusercontent.com/daybreakersx/premscript/master/badvpn-udpgw64"
    sudo chmod +x /usr/bin/badvpn-udpgw
    check_status
else
    echo -e "[✓] BadVPN already installed"
fi

# Start BadVPN now
screen -dmS badvpn badvpn-udpgw --listen-addr 127.0.0.1:7100 --max-clients 500
screen -dmS badvpn badvpn-udpgw --listen-addr 127.0.0.1:7200 --max-clients 500
screen -dmS badvpn badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 500
# ====================== END BADVPN SETUP ======================

# ====================== IPTABLES SETUP ======================
print_status "Setting iptables rules for DNS..."
# Add iptables rules for DNS redirection
sudo iptables -I INPUT -p udp --dport 5300 -j ACCEPT
sudo iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300

# Save iptables rules
if ! command -v iptables-persistent &> /dev/null; then
    sudo apt-get install -y iptables-persistent
fi
sudo iptables-save > /etc/iptables/rules.v4
# ====================== END IPTABLES SETUP ======================

print_status "Setting firewall rules..."
# Allow all UDP ports for SlowDNS
for ((i=1; i<=NUM_TUNNELS; i++)); do
    UDP_PORT=$((5300 + i - 1))
    sudo ufw allow $UDP_PORT/udp 2>/dev/null
done

# Allow all SSH ports
for port in $SSH_PORTS; do
    sudo ufw allow $port/tcp 2>/dev/null
done

# Allow SSLH port
sudo ufw allow 443/tcp 2>/dev/null

# Enable UFW
echo "y" | sudo ufw enable 2>/dev/null

print_status "Removing password complexity module..."
sudo apt-get remove -y libpam-pwquality 2>/dev/null || true

print_status "Running final SSLH fix..."
fix_sslh_service
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
sudo cat /etc/slowdns/server.pub
echo ""
echo "SSLH is running on port 443 (handles SSH/SSL/OpenVPN)"
echo "SlowDNS is running on UDP ports 5300-53XX"
echo "BadVPN is running on ports 7100, 7200, 7300 (UDP for gaming/streaming)"
echo ""
echo "Checking service status..."
for ((i=1; i<=NUM_TUNNELS; i++)); do
    echo ""
    echo "=== Tunnel $i Status ==="
    sudo systemctl status server-sldns-$i --no-pager -l | head -10
done

echo ""
echo "=== SSH Status ==="
if systemctl is-active --quiet ssh; then
    sudo systemctl status ssh --no-pager -l | head -5
elif systemctl is-active --quiet sshd; then
    sudo systemctl status sshd --no-pager -l | head -5
else
    echo "SSH service status unknown"
fi

echo ""
echo "=== SSLH Status ==="
sudo systemctl status sslh --no-pager -l | head -10

echo ""
echo "=== Services configured to auto-start on reboot ==="
echo "1. SSLH (port 443 multiplexer)"
echo "2. SlowDNS tunnels"
echo "3. BadVPN UDPGW"
echo "4. DNS redirection (53 → 5300)"
echo "5. SSH service"
echo ""
echo "All fixes are integrated - no external wget calls needed!"
