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

# ====================== ESSENTIAL SETUP ======================
print_status "Disabling UFW..."
ufw disable 2>/dev/null
check_status

print_status "Disabling systemd-resolved..."
systemctl stop systemd-resolved 2>/dev/null
systemctl disable systemd-resolved 2>/dev/null
check_status

if [ -L /etc/resolv.conf ]; then
    print_status "Removing resolv.conf symlink..."
    rm -f /etc/resolv.conf
    check_status
fi

print_status "Creating new resolv.conf with Google DNS..."
echo -e "nameserver 8.8.8.8\nnameserver 8.8.4.4" > /etc/resolv.conf
check_status

# ====================== FIX SSLH SIMPLY ======================
print_status "Fixing SSLH for SlowDNS..."

# Install SSLH if not installed
if ! command -v sslh &> /dev/null; then
    print_status "Installing SSLH..."
    apt-get update -y
    apt-get install -y sslh
    check_status
fi

# Stop anything using port 443
systemctl stop nginx 2>/dev/null
systemctl stop apache2 2>/dev/null
pkill sslh 2>/dev/null
sleep 2

# Simple SSLH config
cat > /etc/default/sslh <<'EOF'
RUN=daemon
DAEMON_OPTS="--user sslh --listen 0.0.0.0:443 --ssh 127.0.0.1:22"
EOF

# Start SSLH
systemctl enable sslh
systemctl restart sslh
sleep 2

if systemctl is-active --quiet sslh; then
    echo -e "[✓] SSLH is running"
else
    # Try alternative port
    sed -i 's/--listen 0.0.0.0:443/--listen 0.0.0.0:444/g' /etc/default/sslh
    systemctl restart sslh
    echo -e "[✓] SSLH running on port 444"
fi

# ====================== CONFIGURE SSH FOR SLOWDNS ======================
print_status "Configuring SSH for SlowDNS..."
echo "Port 22" >> /etc/ssh/sshd_config
sed -i 's/#AllowTcpForwarding yes/AllowTcpForwarding yes/g' /etc/ssh/sshd_config

# Add SSH restart with proper service name
if systemctl list-unit-files | grep -q "ssh.service"; then
    systemctl restart ssh
else
    systemctl restart sshd
fi
check_status

# ====================== SETUP SLOWDNS ======================
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

# ====================== CONFIGURE SLOWDNS SERVICE ======================
print_status "Configuring SlowDNS service..."
read -p "Enter nameserver: " NAMESERVER

if [ -z "$NAMESERVER" ]; then
    echo "[!] Error: Nameserver cannot be empty!"
    exit 1
fi

# Create service file
cat > /etc/systemd/system/server-sldns.service << EOF
[Unit]
Description=SlowDNS Server
After=network.target

[Service]
Type=simple
ExecStart=/etc/slowdns/sldns-server -udp :5300 -privkey-file /etc/slowdns/server.key $NAMESERVER 127.0.0.1:22
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

chmod 644 /etc/systemd/system/server-sldns.service

# Setup rc.local for auto-start
print_status "Setting up auto-start..."
cat > /etc/rc.local <<'EOF'
#!/bin/sh -e
# Auto-start SSLH
systemctl start sslh 2>/dev/null

# Auto-start SlowDNS
systemctl start server-sldns 2>/dev/null

# DNS redirect for SlowDNS
iptables -I INPUT -p udp --dport 5300 -j ACCEPT
iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300
exit 0
EOF

chmod +x /etc/rc.local
systemctl enable rc-local 2>/dev/null || true

# ====================== SETUP IPTABLES FOR SLOWDNS ======================
print_status "Setting up iptables for SlowDNS..."
iptables -I INPUT -p udp --dport 5300 -j ACCEPT
iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300

# Save iptables rules
apt-get install -y iptables-persistent 2>/dev/null
iptables-save > /etc/iptables/rules.v4 2>/dev/null

# ====================== START SLOWDNS SERVICE ======================
print_status "Starting SlowDNS service..."
systemctl daemon-reload
systemctl enable server-sldns
systemctl start server-sldns
systemctl restart server-sldns
sleep 2

# ====================== SIMPLE FIREWALL RULES ======================
print_status "Setting essential firewall rules..."
ufw allow 22/tcp 2>/dev/null
ufw allow 443/tcp 2>/dev/null
ufw allow 444/tcp 2>/dev/null
ufw allow 5300/udp 2>/dev/null
echo "y" | ufw enable 2>/dev/null

# ====================== FINAL OUTPUT ======================
clear
echo ""
echo "========================================"
echo "   SLOWDNS SETUP COMPLETED"
echo "========================================"
echo ""
echo "Service Status:"
echo "---------------"

# Check SlowDNS
if systemctl is-active --quiet server-sldns; then
    echo -e "[✓] SLOWDNS: ON"
else
    echo -e "[✗] SLOWDNS: OFF"
fi

# Check SSLH
if systemctl is-active --quiet sslh; then
    echo -e "[✓] SSLH: ON"
else
    echo -e "[✗] SSLH: OFF"
fi

# Check SSH
if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
    echo -e "[✓] SSH: ON"
else
    echo -e "[✗] SSH: OFF"
fi

echo ""
echo "========================================"
echo "   CONNECTION INFORMATION"
echo "========================================"
echo ""
echo "Nameserver: $NAMESERVER"
echo ""
echo "Public Key:"
if [ -f /etc/slowdns/server.pub ]; then
    cat /etc/slowdns/server.pub
else
    echo "ERROR: Public key not found!"
fi

echo ""
echo "SlowDNS Port: UDP 5300"
echo "SSH Port: 22"
echo "SSLH Port: 443 (or 444 if 443 failed)"
echo ""
echo "========================================"
echo "   QUICK COMMANDS"
echo "========================================"
echo ""
echo "Restart SlowDNS: systemctl restart server-sldns"
echo "Restart SSLH: systemctl restart sslh"
echo "Check status: systemctl status server-sldns"
echo ""
echo "========================================"
