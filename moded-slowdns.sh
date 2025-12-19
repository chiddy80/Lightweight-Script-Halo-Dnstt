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

print_status "Removing password complexity module..."
sudo apt-get remove -y libpam-pwquality 2>/dev/null || true

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
echo "Checking service status..."
for ((i=1; i<=NUM_TUNNELS; i++)); do
    echo ""
    echo "=== Tunnel $i Status ==="
    systemctl status server-sldns-$i --no-pager -l | head -10
done
