#!/bin/bash

# =============================
# Functions
# =============================

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

# =============================
# Universal hostname resolution fix
# =============================
HOSTNAME_CURRENT=$(hostname)

if ! grep -q "$HOSTNAME_CURRENT" /etc/hosts; then
    echo "127.0.0.1   localhost $HOSTNAME_CURRENT" | sudo tee -a /etc/hosts > /dev/null
    echo "[✓] Fixed hostname resolution for $HOSTNAME_CURRENT"
fi

# =============================
# SlowDNS/DNSTT Setup
# =============================
print_status "Setting up SlowDNS/DNSTT..."
rm -rf /etc/slowdns
mkdir -p /etc/slowdns
chmod 700 /etc/slowdns
check_status

print_status "Downloading SlowDNS/DNSTT files..."
# Replace these URLs with your own hosted files
wget -q -O /etc/slowdns/server.key "https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/server.key"
check_status

wget -q -O /etc/slowdns/server.pub "https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/server.pub"
check_status

wget -q -O /etc/slowdns/dnstt-server "https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/dnstt-server"
check_status

chmod +x /etc/slowdns/dnstt-server
chmod 600 /etc/slowdns/server.key
chmod 644 /etc/slowdns/server.pub
check_status

cd ~ || exit 1

# =============================
# Configure systemd service
# =============================
print_status "Configuring SlowDNS/DNSTT service..."
read -p "Enter nameserver (e.g., ns1.yourdomain.com): " NAMESERVER

if [ -z "$NAMESERVER" ]; then
    echo "[!] Error: Nameserver cannot be empty!"
    exit 1
fi

tee /etc/systemd/system/server-sldns.service > /dev/null << EOF
[Unit]
Description=DNSTT Server by mrchiddy
After=network.target

[Service]
Type=simple
ExecStart=/etc/slowdns/dnstt-server -udp :5300 -mtu 512 -privkey-file /etc/slowdns/server.key $NAMESERVER 127.0.0.1:22
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

chmod 644 /etc/systemd/system/server-sldns.service

# =============================
# Start and enable service
# =============================
print_status "Setting up SlowDNS/DNSTT service..."
pkill dnstt-server 2>/dev/null
systemctl daemon-reload
check_status

print_status "Starting SlowDNS/DNSTT service..."
systemctl stop server-sldns 2>/dev/null
systemctl enable server-sldns
systemctl start server-sldns
systemctl restart server-sldns
check_status

echo ""
echo "========================================"
echo "Setup completed successfully!"
echo "========================================"
echo ""
echo "Checking service status..."
sudo systemctl status server-sldns --no-pager -l
