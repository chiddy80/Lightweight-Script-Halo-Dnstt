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

cd ~ || exit 1

print_status "Configuring SSH..."
echo "Port 22" | sudo tee -a /etc/ssh/sshd_config > /dev/null
sed -i 's/#AllowTcpForwarding yes/AllowTcpForwarding yes/g' /etc/ssh/sshd_config
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

# Validate nameserver input
if [ -z "$NAMESERVER" ]; then
    echo "[!] Error: Nameserver cannot be empty!"
    exit 1
fi

# Create service file
tee /etc/systemd/system/server-sldns.service > /dev/null << EOF
[Unit]
Description=DNSTT by mrchiddy
After=network.target

[Service]
Type=simple
ExecStart=/etc/slowdns/sldns-server -udp :5300 -mtu 512 -privkey-file /etc/slowdns/server.key $NAMESERVER 127.0.0.1:22
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

chmod 644 /etc/systemd/system/server-sldns.service

print_status "Setting up SlowDNS service..."
pkill sldns-server 2>/dev/null
systemctl daemon-reload
check_status

print_status "Starting SlowDNS service..."
systemctl stop server-sldns 2>/dev/null
systemctl enable server-sldns
systemctl start server-sldns
systemctl restart server-sldns
check_status

print_status "Removing password complexity module..."
sudo apt-get remove -y libpam-pwquality 2>/dev/null || true

echo ""
echo "========================================"
echo "Setup completed successfully!"
echo "========================================"
echo ""
echo "Checking service status..."
sudo systemctl status server-sldns --no-pager -l
