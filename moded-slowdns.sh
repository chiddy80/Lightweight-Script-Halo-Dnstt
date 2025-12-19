#!/bin/bash

# Clear screen
clear

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Simple status function
status() {
    echo -e "[*] $1"
}

success() {
    echo -e "${GREEN}[✓] $1${NC}"
}

error() {
    echo -e "${RED}[✗] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[!] $1${NC}"
}

# ====================== START INSTALLATION ======================
echo "========================================"
echo "    DNS/SlowDNS Setup Script"
echo "========================================"
echo ""

# ====================== FIX HOSTNAME ======================
status "Fixing hostname resolution..."
hostname=$(hostname)
grep -q "$hostname" /etc/hosts || echo "127.0.0.1 $hostname" >> /etc/hosts
success "Hostname fixed"

# ====================== INSTALL SSLH ======================
status "Installing SSLH..."
apt-get update -y
apt-get install -y sslh

# Stop everything on port 443
status "Clearing port 443..."
systemctl stop nginx 2>/dev/null
systemctl stop apache2 2>/dev/null
pkill sslh 2>/dev/null
fuser -k 443/tcp 2>/dev/null
sleep 2

# Simple SSLH config
status "Configuring SSLH..."
cat > /etc/default/sslh <<'EOF'
RUN=daemon
DAEMON_OPTS="--user sslh --listen 0.0.0.0:443 --ssh 127.0.0.1:22 --ssl 127.0.0.1:4443"
EOF

# Enable and start SSLH
systemctl enable sslh
systemctl start sslh
sleep 2

# Check SSLH
if systemctl is-active --quiet sslh; then
    success "SSLH is running"
else
    warning "SSLH failed. Trying port 444..."
    sed -i 's/--listen 0.0.0.0:443/--listen 0.0.0.0:444/g' /etc/default/sslh
    systemctl restart sslh
    if systemctl is-active --quiet sslh; then
        success "SSLH running on port 444"
    else
        error "SSLH installation failed"
    fi
fi

# ====================== DISABLE SYSTEMD-RESOLVED ======================
status "Disabling systemd-resolved..."
systemctl stop systemd-resolved 2>/dev/null
systemctl disable systemd-resolved 2>/dev/null
[ -L /etc/resolv.conf ] && rm -f /etc/resolv.conf
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 8.8.4.4" >> /etc/resolv.conf
success "DNS configured"

# ====================== CONFIGURE SSH ======================
status "Configuring SSH..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null

# Add SSH ports
ports="22 2222 2223 2224"
sed -i '/^Port/d' /etc/ssh/sshd_config 2>/dev/null
for p in $ports; do
    echo "Port $p" >> /etc/ssh/sshd_config
done

# Enable TCP forwarding
sed -i 's/#AllowTcpForwarding yes/AllowTcpForwarding yes/g' /etc/ssh/sshd_config
grep -q "AllowTcpForwarding yes" /etc/ssh/sshd_config || echo "AllowTcpForwarding yes" >> /etc/ssh/sshd_config

systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
success "SSH configured"

# ====================== SETUP SLOWDNS ======================
status "Setting up SlowDNS..."
rm -rf /etc/slowdns
mkdir -p /etc/slowdns
chmod 777 /etc/slowdns

# Download files
wget -q -O /etc/slowdns/server.key "https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/server.key"
wget -q -O /etc/slowdns/server.pub "https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/server.pub"
wget -q -O /etc/slowdns/sldns-server "https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/dnstt-server"
chmod +x /etc/slowdns/sldns-server
success "SlowDNS files downloaded"

# Get nameserver
echo ""
read -p "Enter nameserver (e.g., dns.example.com): " NAMESERVER
[ -z "$NAMESERVER" ] && NAMESERVER="ns.example.com"

# Get number of tunnels
echo ""
read -p "Number of tunnels (1-5): " NUM_TUNNELS
[ -z "$NUM_TUNNELS" ] && NUM_TUNNELS=1
[[ ! "$NUM_TUNNELS" =~ ^[1-5]$ ]] && NUM_TUNNELS=1

# Create tunnels
status "Creating $NUM_TUNNELS tunnel(s)..."
for i in $(seq 1 $NUM_TUNNELS); do
    udp_port=$((5300 + i - 1))
    ssh_port=$((2221 + i))
    [ $i -eq 1 ] && ssh_port=22
    
    cat > /etc/systemd/system/server-sldns-$i.service <<EOF
[Unit]
Description=SlowDNS Tunnel $i
After=network.target

[Service]
Type=simple
ExecStart=/etc/slowdns/sldns-server -udp :$udp_port -privkey-file /etc/slowdns/server.key $NAMESERVER 127.0.0.1:$ssh_port
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable server-sldns-$i
    systemctl start server-sldns-$i
    echo "  Tunnel $i: UDP:$udp_port → SSH:$ssh_port"
done
success "Tunnels created"

# ====================== SETUP BADVPN (QUICK) ======================
status "Setting up BadVPN..."
if [ ! -f /usr/bin/badvpn-udpgw ]; then
    wget -q -O /usr/bin/badvpn-udpgw "https://raw.githubusercontent.com/daybreakersx/premscript/master/badvpn-udpgw64"
    chmod +x /usr/bin/badvpn-udpgw
fi

# Start BadVPN
pkill badvpn-udpgw 2>/dev/null
screen -dmS badvpn badvpn-udpgw --listen-addr 127.0.0.1:7100 --max-clients 100
screen -dmS badvpn badvpn-udpgw --listen-addr 127.0.0.1:7200 --max-clients 100
screen -dmS badvpn badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 100
success "BadVPN started"

# ====================== SETUP IPTABLES ======================
status "Setting up iptables..."
iptables -I INPUT -p udp --dport 5300 -j ACCEPT
iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300
iptables-save > /etc/iptables/rules.v4 2>/dev/null
success "iptables configured"

# ====================== SETUP RCLOCAL ======================
status "Setting up auto-start..."
cat > /etc/rc.local <<'EOF'
#!/bin/sh -e
# Start SSLH
systemctl start sslh 2>/dev/null

# Start BadVPN
screen -dmS badvpn badvpn-udpgw --listen-addr 127.0.0.1:7100 --max-clients 100
screen -dmS badvpn badvpn-udpgw --listen-addr 127.0.0.1:7200 --max-clients 100
screen -dmS badvpn badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 100

# DNS redirect
iptables -I INPUT -p udp --dport 5300 -j ACCEPT
iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300
exit 0
EOF

chmod +x /etc/rc.local
systemctl enable rc-local 2>/dev/null || true
success "Auto-start configured"

# ====================== CONFIGURE FIREWALL ======================
status "Configuring firewall..."
ufw disable 2>/dev/null
for i in $(seq 1 $NUM_TUNNELS); do
    udp_port=$((5300 + i - 1))
    ufw allow $udp_port/udp 2>/dev/null
done
for p in $ports; do
    ufw allow $p/tcp 2>/dev/null
done
ufw allow 443/tcp 2>/dev/null
ufw allow 444/tcp 2>/dev/null
echo "y" | ufw enable 2>/dev/null
success "Firewall configured"

# ====================== FINAL OUTPUT ======================
clear
echo ""
echo "========================================"
echo "      SETUP COMPLETED SUCCESSFULLY"
echo "========================================"
echo ""

# Show simple service status
echo "Service Status:"
echo "---------------"
if systemctl is-active --quiet server-sldns-1; then
    echo -e "${GREEN}✓ SLOWDNS: ON${NC}"
else
    echo -e "${RED}✗ SLOWDNS: OFF${NC}"
fi

if systemctl is-active --quiet sslh; then
    echo -e "${GREEN}✓ SSLH: ON${NC}"
else
    echo -e "${RED}✗ SSLH: OFF${NC}"
fi

if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
    echo -e "${GREEN}✓ SSH: ON${NC}"
else
    echo -e "${RED}✗ SSH: OFF${NC}"
fi

echo ""
echo "========================================"
echo "      CONNECTION INFORMATION"
echo "========================================"
echo ""
echo "Nameserver: $NAMESERVER"
echo ""
echo "Public Key:"
if [ -f /etc/slowdns/server.pub ]; then
    cat /etc/slowdns/server.pub
else
    echo "ERROR: Public key file not found!"
fi

echo ""
echo "Tunnels:"
for i in $(seq 1 $NUM_TUNNELS); do
    udp_port=$((5300 + i - 1))
    ssh_port=$((2221 + i))
    [ $i -eq 1 ] && ssh_port=22
    echo "  Tunnel $i: UDP:$udp_port → SSH:$ssh_port"
done

echo ""
echo "========================================"
echo "      QUICK COMMANDS"
echo "========================================"
echo ""
echo "Restart all: systemctl restart sslh && systemctl restart server-sldns-1"
echo "Check SSLH: systemctl status sslh"
echo "Check SlowDNS: systemctl status server-sldns-1"
echo "Fix services: systemctl daemon-reload && systemctl restart sslh"
echo ""
echo "========================================"
