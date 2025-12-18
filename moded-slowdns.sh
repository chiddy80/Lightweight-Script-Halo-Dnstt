#!/bin/bash

# =========================================
#  SLOWDNS MODED INSTALLER & PANEL - REMASTERED
#  Author: esim FREEGB
#  Telegram: https://t.me/esimfreegb
# =========================================

# -------------------------
# Configuration
# -------------------------
set -e  # Exit on error
SCRIPT_NAME="slowdns-installer"
SCRIPT_VERSION="1.3.0"

# -------------------------
# Colors
# -------------------------
GREEN='\033[1;32m'
RED='\033[1;31m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
WHITE='\033[1;37m'
NC='\033[0m'

# -------------------------
# Paths
# -------------------------
INFO_FILE="/etc/slowdns-info.conf"
DNSTT_DIR="/root/dnstt"
LOG_FILE="/var/log/slowdns-installer.log"
BACKUP_DIR="/root/slowdns-backup"

# -------------------------
# Dependencies
# -------------------------
REQUIRED_PACKAGES="wget curl screen iptables-persistent net-tools dnsutils openssh-server"
DNSTT_SERVER_URL="https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/dnstt-server"
SERVER_KEY_URL="https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/server.key"
SERVER_PUB_URL="https://raw.githubusercontent.com/chiddy80/Lightweight-Script-Halo-Dnstt/main/server.pub"
BADVPN_URL="https://github.com/ambrop72/badvpn/releases/download/1.999.130/badvpn-udpgw"

# -------------------------
# Logging
# -------------------------
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $*"
}

log_error() {
    log "${RED}[ERROR]${NC} $*"
}

log_info() {
    log "${CYAN}[INFO]${NC} $*"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $*"
}

# -------------------------
# Helper Functions
# -------------------------
print_header() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════╗"
    echo "║    SLOWDNS MODED PANEL - REMASTERED      ║"
    echo "║    Author: esim FREEGB                   ║"
    echo "║    Version: $SCRIPT_VERSION                    ║"
    echo "╚══════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_footer() {
    echo -e "${BLUE}"
    echo "════════════════════════════════════════════"
    echo "Telegram: https://t.me/esimfreegb"
    echo "════════════════════════════════════════════"
    echo -e "${NC}"
}

print_separator() {
    echo -e "${MAGENTA}════════════════════════════════════════════${NC}"
}

# -------------------------
# Validation Functions
# -------------------------
is_root() {
    [[ $EUID -eq 0 ]] || {
        log_error "This script must be run as root"
        echo -e "${RED}Please run as: sudo bash $0${NC}"
        exit 1
    }
}

is_number() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

is_valid_domain() {
    [[ "$1" =~ ^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]
}

check_internet() {
    if ! ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
        log_error "No internet connection"
        return 1
    fi
    return 0
}

# -------------------------
# System Functions
# -------------------------
check_dnstt_status() {
    if systemctl is-active --quiet dnstt.service 2>/dev/null; then
        echo -e "${GREEN}[RUNNING]${NC}"
    elif systemctl is-enabled --quiet dnstt.service 2>/dev/null; then
        echo -e "${YELLOW}[ENABLED BUT NOT RUNNING]${NC}"
    else
        echo -e "${RED}[NOT INSTALLED]${NC}"
    fi
}

check_badvpn_status() {
    if systemctl is-active --quiet badvpn.service 2>/dev/null; then
        echo -e "${GREEN}[RUNNING]${NC}"
    else
        echo -e "${RED}[NOT RUNNING]${NC}"
    fi
}

check_ssh_status() {
    if systemctl is-active --quiet ssh 2>/dev/null; then
        echo -e "${GREEN}[RUNNING]${NC}"
    else
        echo -e "${RED}[NOT RUNNING]${NC}"
    fi
}

backup_config() {
    log_info "Creating backup..."
    mkdir -p "$BACKUP_DIR"
    cp -f "$INFO_FILE" "$BACKUP_DIR/" 2>/dev/null || true
    cp -f /etc/systemd/system/dnstt.service "$BACKUP_DIR/" 2>/dev/null || true
    cp -f /etc/systemd/system/badvpn.service "$BACKUP_DIR/" 2>/dev/null || true
    iptables-save > "$BACKUP_DIR/iptables.backup" 2>/dev/null || true
}

# -------------------------
# SSH Configuration
# -------------------------
configure_ssh() {
    log_info "Configuring SSH..."
    
    # Install SSH if not installed
    if ! dpkg -l | grep -q openssh-server; then
        log_info "Installing OpenSSH server..."
        apt-get install -y openssh-server >/dev/null 2>&1
    fi
    
    # Backup original SSH config
    if [[ -f /etc/ssh/sshd_config ]]; then
        cp -f /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)
    fi
    
    # Directly modify the sshd_config file
    cat > /etc/ssh/sshd_config << 'EOF'
# SlowDNS SSH Configuration
Port 22
Protocol 2
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
UsePAM yes
X11Forwarding no
AllowTcpForwarding yes
GatewayPorts no
AllowAgentForwarding no
PermitTunnel no
ClientAliveInterval 60
ClientAliveCountMax 3
MaxAuthTries 3
MaxSessions 3
LoginGraceTime 30
StrictModes yes
IgnoreRhosts yes
HostbasedAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
KerberosAuthentication no
GSSAPIAuthentication no
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes
UseDNS no
Compression delayed
Subsystem sftp /usr/lib/openssh/sftp-server
EOF
    
    # Restart SSH service
    systemctl restart ssh
    
    # Verify SSH is running
    if systemctl is-active --quiet ssh; then
        log_success "SSH configured and restarted successfully"
    else
        log_error "Failed to restart SSH"
        return 1
    fi
}

# -------------------------
# Network Optimization
# -------------------------
optimize_network() {
    log_info "Optimizing network settings..."
    
    cat > /etc/sysctl.d/99-slowdns-optimization.conf << EOF
# SlowDNS Network Optimization
net.core.rmem_max = 4194304
net.core.wmem_max = 4194304
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.optmem_max = 4194304
net.core.netdev_max_backlog = 5000
net.core.somaxconn = 1024

net.ipv4.tcp_rmem = 4096 87380 4194304
net.ipv4.tcp_wmem = 4096 65536 4194304
net.ipv4.udp_mem = 8388608 12582912 16777216
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384

net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_max_syn_backlog = 1024
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30

net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15
EOF
    
    # Apply sysctl settings
    sysctl -p /etc/sysctl.d/99-slowdns-optimization.conf >/dev/null 2>&1 || true
    sysctl --system >/dev/null 2>&1
    
    log_success "Network optimization applied"
}

# -------------------------
# BadVPN Installation - FIXED
# -------------------------
install_badvpn() {
    log_info "Installing BadVPN UDPGW..."
    
    # Try multiple download methods
    if ! command -v badvpn-udpgw &>/dev/null; then
        # Method 1: Direct download from GitHub
        if wget -q --timeout=20 --tries=2 -O /usr/bin/badvpn-udpgw "$BADVPN_URL"; then
            log_success "Downloaded BadVPN from GitHub"
        else
            # Method 2: Alternative source
            log_warning "GitHub download failed, trying alternative..."
            if wget -q --timeout=20 --tries=2 -O /usr/bin/badvpn-udpgw "https://raw.githubusercontent.com/ambrop72/badvpn/master/tun2socks/badvpn-udpgw"; then
                log_success "Downloaded BadVPN from alternative source"
            else
                # Method 3: Build from source
                log_warning "Download failed, attempting to build from source..."
                cd /tmp
                apt-get install -y cmake build-essential >/dev/null 2>&1
                git clone https://github.com/ambrop72/badvpn.git 2>/dev/null
                cd badvpn
                mkdir build && cd build
                cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 >/dev/null 2>&1
                make >/dev/null 2>&1
                cp udpgw/badvpn-udpgw /usr/bin/
                cd /root
                log_success "Built BadVPN from source"
            fi
        fi
        
        chmod +x /usr/bin/badvpn-udpgw
    else
        log_success "BadVPN already installed"
    fi
    
    # Create systemd service
    cat > /etc/systemd/system/badvpn.service << EOF
[Unit]
Description=BadVPN UDP Gateway
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/usr/bin/badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 500 --max-connections-for-client 3
Restart=always
RestartSec=3
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable and start service
    systemctl daemon-reload
    systemctl enable badvpn.service
    systemctl start badvpn.service
    
    # Verify installation
    if systemctl is-active --quiet badvpn.service; then
        log_success "BadVPN installed and started successfully"
        return 0
    else
        log_warning "BadVPN service may need manual start"
        return 1
    fi
}

# -------------------------
# SSH User Management
# -------------------------
create_ssh_user() {
    echo -e "\n${CYAN}━━━━━━━━ CREATE SSH USER ━━━━━━━━${NC}"
    
    # Get username
    while true; do
        read -p "Username (3-32 chars, letters/numbers only): " username
        if [[ "$username" =~ ^[a-zA-Z0-9]{3,32}$ ]]; then
            if id "$username" &>/dev/null; then
                echo -e "${RED}User '$username' already exists${NC}"
                continue
            fi
            break
        else
            echo -e "${RED}Invalid username. Use 3-32 letters/numbers only.${NC}"
        fi
    done
    
    # Get password
    while true; do
        read -sp "Password (min 8 chars): " password
        echo
        if [[ ${#password} -ge 8 ]]; then
            read -sp "Confirm password: " password2
            echo
            if [[ "$password" == "$password2" ]]; then
                break
            else
                echo -e "${RED}Passwords do not match${NC}"
            fi
        else
            echo -e "${RED}Password must be at least 8 characters${NC}"
        fi
    done
    
    # Create user
    if useradd -m -s /bin/bash -G sudo "$username" 2>/dev/null; then
        echo "$username:$password" | chpasswd
        
        # Set up SSH directory
        mkdir -p "/home/$username/.ssh"
        chmod 700 "/home/$username/.ssh"
        chown -R "$username:$username" "/home/$username"
        
        log_success "User '$username' created successfully"
        echo -e "${GREEN}Username: $username${NC}"
        echo -e "${GREEN}Password: [hidden]${NC}"
    else
        log_error "Failed to create user '$username'"
    fi
}

delete_ssh_user() {
    echo -e "\n${CYAN}━━━━━━━━ DELETE SSH USER ━━━━━━━━${NC}"
    
    # Get all non-system users
    users=($(awk -F: '$3 >= 1000 && $1 != "nobody" && $1 != "systemd-*" {print $1}' /etc/passwd))
    
    if [[ ${#users[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No regular users found${NC}"
        return
    fi
    
    # Display users
    echo -e "${WHITE}Available users:${NC}"
    for i in "${!users[@]}"; do
        echo "$((i+1)). ${users[$i]}"
    done
    echo "$(( ${#users[@]} + 1 )). Cancel"
    
    # Get selection
    while true; do
        read -p "Select user to delete (1-${#users[@]}): " selection
        if is_number "$selection"; then
            if [[ $selection -ge 1 && $selection -le ${#users[@]} ]]; then
                user_to_delete="${users[$((selection-1))]}"
                break
            elif [[ $selection -eq $(( ${#users[@]} + 1 )) ]]; then
                echo "Cancelled"
                return
            fi
        fi
        echo -e "${RED}Invalid selection${NC}"
    done
    
    # Confirm deletion
    read -p "Are you sure you want to delete user '$user_to_delete'? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        if userdel -r "$user_to_delete" 2>/dev/null; then
            log_success "User '$user_to_delete' deleted successfully"
        else
            log_error "Failed to delete user '$user_to_delete'"
        fi
    else
        echo "Deletion cancelled"
    fi
}

list_ssh_users() {
    echo -e "\n${CYAN}━━━━━━━━ SSH USERS LIST ━━━━━━━━${NC}"
    echo -e "${WHITE}#  Username        Last Login${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    users=($(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd))
    
    if [[ ${#users[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No regular users found${NC}"
        return
    fi
    
    for i in "${!users[@]}"; do
        user="${users[$i]}"
        last_login=$(lastlog -u "$user" | tail -1 | awk '{print $4,$5,$6,$7,$8,$9}' | sed 's/  / /g')
        if [[ "$last_login" == "**Never logged in**" ]]; then
            last_login="Never logged in"
        fi
        printf "%-3d %-15s %-25s\n" "$((i+1))" "$user" "$last_login"
    done
}

# -------------------------
# SlowDNS/DNSTT Installation with CUSTOM MTU
# -------------------------
install_slowdns() {
    print_header
    echo -e "${YELLOW}━━━━━━━━ SLOWDNS INSTALLATION ━━━━━━━━${NC}\n"
    
    # Check internet
    if ! check_internet; then
        echo -e "${RED}No internet connection. Please check your network.${NC}"
        return 1
    fi
    
    # Backup existing config
    backup_config
    
    # Update system
    log_info "Updating system packages..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >/dev/null 2>&1
    apt-get upgrade -y --with-new-pkgs >/dev/null 2>&1
    
    # Install dependencies
    log_info "Installing dependencies..."
    apt-get install -y $REQUIRED_PACKAGES >/dev/null 2>&1
    
    # Clean up previous installation
    log_info "Cleaning up previous installation..."
    systemctl stop dnstt.service 2>/dev/null || true
    systemctl disable dnstt.service 2>/dev/null || true
    rm -rf "$DNSTT_DIR"
    
    # Create DNSTT directory
    mkdir -p "$DNSTT_DIR"
    cd "$DNSTT_DIR" || exit 1
    
    # Download DNSTT files
    log_info "Downloading DNSTT binaries..."
    
    for url in "$DNSTT_SERVER_URL" "$SERVER_KEY_URL" "$SERVER_PUB_URL"; do
        filename=$(basename "$url")
        if ! wget -q --timeout=30 --tries=3 --show-progress -O "$filename" "$url"; then
            log_error "Failed to download $filename"
            return 1
        fi
    done
    
    chmod +x dnstt-server
    
    # Get configuration
    echo -e "\n${WHITE}━━━━━━━━ CONFIGURATION ━━━━━━━━${NC}"
    
    # NS Domain
    while true; do
        read -p "Enter NS Domain (e.g., ns1.yourdomain.com): " ns_domain
        if is_valid_domain "$ns_domain"; then
            break
        else
            echo -e "${RED}Invalid domain format${NC}"
        fi
    done
    
    # Port selection
    echo -e "\n${WHITE}Select forwarding port:${NC}"
    echo "1) SSH (Port 22)"
    echo "2) V2Ray (Port 8787)"
    echo "3) Custom port"
    
    while true; do
        read -p "Choose option (1-3): " port_choice
        case $port_choice in
            1)
                forward_port=22
                break
                ;;
            2)
                forward_port=8787
                echo -e "\n${YELLOW}Installing 3x-UI panel...${NC}"
                bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) || {
                    log_warning "3x-UI installation failed or was cancelled"
                }
                read -p "Press Enter to continue..."
                break
                ;;
            3)
                while true; do
                    read -p "Enter custom port (1-65535): " forward_port
                    if is_number "$forward_port" && [[ $forward_port -ge 1 && $forward_port -le 65535 ]]; then
                        break
                    else
                        echo -e "${RED}Invalid port number${NC}"
                    fi
                done
                break
                ;;
            *)
                echo -e "${RED}Invalid choice${NC}"
                ;;
        esac
    done
    
    # MTU Selection
    echo -e "\n${WHITE}Select MTU (Maximum Transmission Unit):${NC}"
    echo "1) Default (512)"
    echo "2) Recommended (1280)"
    echo "3) High Performance (1450)"
    echo "4) Custom MTU"
    
    while true; do
        read -p "Choose MTU option (1-4): " mtu_choice
        case $mtu_choice in
            1)
                MTU=512
                break
                ;;
            2)
                MTU=1280
                break
                ;;
            3)
                MTU=1450
                break
                ;;
            4)
                while true; do
                    read -p "Enter custom MTU (68-1500): " MTU
                    if is_number "$MTU" && [[ $MTU -ge 68 && $MTU -le 1500 ]]; then
                        break
                    else
                        echo -e "${RED}Invalid MTU. Must be between 68 and 1500${NC}"
                    fi
                done
                break
                ;;
            *)
                echo -e "${RED}Invalid choice${NC}"
                ;;
        esac
    done
    
    # Create DNSTT service with custom MTU
    log_info "Creating DNSTT systemd service with MTU: $MTU..."
    
    cat > /etc/systemd/system/dnstt.service << EOF
[Unit]
Description=DNSTT Tunnel Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$DNSTT_DIR
Environment="MTU=$MTU"
ExecStart=$DNSTT_DIR/dnstt-server -udp :5300 -mtu \$MTU -privkey-file $DNSTT_DIR/server.key $ns_domain 127.0.0.1:$forward_port
Restart=always
RestartSec=3
LimitNOFILE=1000000
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # Configure firewall
    log_info "Configuring firewall..."
    iptables -I INPUT -p udp --dport 5300 -j ACCEPT 2>/dev/null || true
    iptables -I INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || true
    netfilter-persistent save 2>/dev/null || true
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    
    # Enable and start services
    systemctl daemon-reload
    systemctl enable dnstt.service
    systemctl start dnstt.service
    
    # Apply optimizations
    configure_ssh
    optimize_network
    install_badvpn
    
    # Save configuration
    cat > "$INFO_FILE" << EOF
# SlowDNS Configuration
# Generated on $(date)
NS_DOMAIN=$ns_domain
FORWARD_PORT=$forward_port
TUNNEL=127.0.0.1:$forward_port
MTU=$MTU
PUBKEY=$(cat "$DNSTT_DIR/server.pub")
INSTALL_DATE=$(date +%Y-%m-%d)
INSTALL_TIME=$(date +%H:%M:%S)
EOF
    
    # Verify installation
    echo -e "\n${WHITE}━━━━━━━━ VERIFICATION ━━━━━━━━${NC}"
    sleep 2
    
    if systemctl is-active --quiet dnstt.service; then
        echo -e "✓ DNSTT Service: ${GREEN}RUNNING${NC}"
        echo -e "  MTU Setting: ${CYAN}$MTU${NC}"
    else
        echo -e "✗ DNSTT Service: ${RED}FAILED${NC}"
    fi
    
    if systemctl is-active --quiet badvpn.service; then
        echo -e "✓ BadVPN Service: ${GREEN}RUNNING${NC}"
    else
        echo -e "✗ BadVPN Service: ${RED}FAILED${NC}"
    fi
    
    if systemctl is-active --quiet ssh; then
        echo -e "✓ SSH Service: ${GREEN}RUNNING${NC}"
    else
        echo -e "✗ SSH Service: ${RED}FAILED${NC}"
    fi
    
    print_separator
    echo -e "${GREEN}✓ SlowDNS installation completed successfully!${NC}"
    echo -e "\n${WHITE}Configuration Summary:${NC}"
    echo -e "  NS Domain: ${CYAN}$ns_domain${NC}"
    echo -e "  Forward Port: ${CYAN}$forward_port${NC}"
    echo -e "  DNSTT Port: ${CYAN}5300/udp${NC}"
    echo -e "  BadVPN Port: ${CYAN}7300/tcp${NC}"
    echo -e "  MTU Value: ${CYAN}$MTU${NC}"
    
        echo -e "\n${YELLOW}Important:${NC}"
    echo -e "1. Configure DNS A record for $ns_domain to point to: $(curl -s ifconfig.me)"
    echo -e "2. Use the public key below in your client configuration"
    echo -e "3. Client MTU should be set to: $MTU"
    echo -e "\n${WHITE}Public Key:${NC}"
    cat "$DNSTT_DIR/server.pub"
    
    echo -e "\n${YELLOW}Press Enter to return to menu...${NC}"
    read -r
}

# -------------------------
# DNSTT Information
# -------------------------
show_dnstt_info() {
    print_header
    
    if [[ ! -f "$INFO_FILE" ]]; then
        echo -e "${RED}SlowDNS is not installed${NC}"
        echo -e "\nPlease run the installation first."
        read -p "Press Enter to continue..."
        return
    fi
    
    echo -e "${CYAN}━━━━━━━━ SLOWDNS INFORMATION ━━━━━━━━${NC}\n"
    
    # Load configuration
    source "$INFO_FILE" 2>/dev/null
    
    # Display service status
    echo -e "${WHITE}Service Status:${NC}"
    echo -e "  DNSTT Tunnel: $(check_dnstt_status)"
    echo -e "  BadVPN UDPGW: $(check_badvpn_status)"
    echo -e "  SSH Service: $(check_ssh_status)"
    
    echo -e "\n${WHITE}Configuration Details:${NC}"
    echo -e "  NS Domain: ${GREEN}${NS_DOMAIN:-Not set}${NC}"
    echo -e "  Forward Port: ${GREEN}${FORWARD_PORT:-Not set}${NC}"
    echo -e "  Tunnel: ${GREEN}${TUNNEL:-Not set}${NC}"
    echo -e "  MTU Value: ${GREEN}${MTU:-512}${NC}"
    
    if [[ -f "$DNSTT_DIR/server.pub" ]]; then
        echo -e "\n${WHITE}Public Key:${NC}"
        echo -e "${CYAN}$(cat "$DNSTT_DIR/server.pub")${NC}"
    fi
    
    # Show system information
    echo -e "\n${WHITE}System Information:${NC}"
    echo -e "  Server IP: $(curl -s ifconfig.me 2>/dev/null || echo 'Unknown')"
    echo -e "  Uptime: $(uptime -p | sed 's/up //')"
    
    # Show recent logs
    echo -e "\n${WHITE}Recent DNSTT Logs (last 5 lines):${NC}"
    journalctl -u dnstt.service -n 5 --no-pager 2>/dev/null || echo "No logs available"
    
    echo -e "\n${WHITE}Active Connections:${NC}"
    ss -tulpn | grep -E ':5300|:7300|:22' | awk '{print "  " $0}' || echo "  No active connections found"
    
    print_footer
    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# -------------------------
# Service Management
# -------------------------
manage_services() {
    while true; do
        print_header
        echo -e "${CYAN}━━━━━━━━ SERVICE MANAGEMENT ━━━━━━━━${NC}\n"
        
        echo -e "${WHITE}Current Status:${NC}"
        echo -e "1. DNSTT Tunnel: $(check_dnstt_status)"
        echo -e "2. BadVPN UDPGW: $(check_badvpn_status)"
        echo -e "3. SSH Service: $(check_ssh_status)"
        
        echo -e "\n${WHITE}Actions:${NC}"
        echo "1. Start DNSTT Service"
        echo "2. Stop DNSTT Service"
        echo "3. Restart DNSTT Service"
        echo "4. Start BadVPN Service"
        echo "5. Stop BadVPN Service"
        echo "6. Restart BadVPN Service"
        echo "7. Start SSH Service"
        echo "8. Stop SSH Service"
        echo "9. Restart SSH Service"
        echo "10. View DNSTT Logs"
        echo "11. View BadVPN Logs"
        echo "12. View SSH Logs"
        echo "13. Back to Main Menu"
        
        echo -e "\n${WHITE}Select action:${NC}"
        read -r choice
        
        case $choice in
            1)
                systemctl start dnstt.service
                log_success "DNSTT service started"
                sleep 2
                ;;
            2)
                systemctl stop dnstt.service
                log_success "DNSTT service stopped"
                sleep 2
                ;;
            3)
                systemctl restart dnstt.service
                log_success "DNSTT service restarted"
                sleep 2
                ;;
            4)
                systemctl start badvpn.service
                log_success "BadVPN service started"
                sleep 2
                ;;
            5)
                systemctl stop badvpn.service
                log_success "BadVPN service stopped"
                sleep 2
                ;;
            6)
                systemctl restart badvpn.service
                log_success "BadVPN service restarted"
                sleep 2
                ;;
            7)
                systemctl start ssh
                log_success "SSH service started"
                sleep 2
                ;;
            8)
                systemctl stop ssh
                log_success "SSH service stopped"
                sleep 2
                ;;
            9)
                systemctl restart ssh
                log_success "SSH service restarted"
                sleep 2
                ;;
            10)
                echo -e "\n${CYAN}DNSTT Service Logs:${NC}"
                journalctl -u dnstt.service -n 20 --no-pager
                read -p "Press Enter to continue..."
                ;;
            11)
                echo -e "\n${CYAN}BadVPN Service Logs:${NC}"
                journalctl -u badvpn.service -n 20 --no-pager
                read -p "Press Enter to continue..."
                ;;
            12)
                echo -e "\n${CYAN}SSH Service Logs:${NC}"
                journalctl -u ssh.service -n 20 --no-pager
                read -p "Press Enter to continue..."
                ;;
            13)
                break
                ;;
            *)
                echo -e "${RED}Invalid choice${NC}"
                sleep 1
                ;;
        esac
    done
}

# -------------------------
# SSH Management Menu
# -------------------------
ssh_management_menu() {
    while true; do
        print_header
        echo -e "${CYAN}━━━━━━━━ SSH USER MANAGEMENT ━━━━━━━━${NC}\n"
        
        echo "1. Create SSH User"
        echo "2. Delete SSH User"
        echo "3. List SSH Users"
        echo "4. Test SSH Connection"
        echo "5. Back to Main Menu"
        
        echo -e "\n${WHITE}Select option:${NC}"
        read -r choice
        
        case $choice in
            1) create_ssh_user ;;
            2) delete_ssh_user ;;
            3) list_ssh_users ;;
            4)
                echo -e "\n${CYAN}Testing SSH connection...${NC}"
                if ssh -o BatchMode=yes -o ConnectTimeout=5 localhost echo "SSH test successful" 2>/dev/null; then
                    echo -e "${GREEN}SSH connection test successful${NC}"
                else
                    echo -e "${RED}SSH connection test failed${NC}"
                fi
                read -p "Press Enter to continue..."
                ;;
            5) break ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
        
        echo -e "\n${YELLOW}Press Enter to continue...${NC}"
        read -r
    done
}

# -------------------------
# Uninstallation
# -------------------------
uninstall_slowdns() {
    print_header
    echo -e "${RED}━━━━━━━━ UNINSTALL SLOWDNS ━━━━━━━━${NC}\n"
    
    echo -e "${YELLOW}WARNING: This will remove all SlowDNS components${NC}\n"
    echo -e "The following will be removed:"
    echo "1. DNSTT Service"
    echo "2. BadVPN Service"
    echo "3. Configuration files"
    echo "4. Iptables rules"
    
    echo -e "\n${RED}This action cannot be undone!${NC}"
    read -p "Are you sure you want to uninstall? (y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Starting uninstallation..."
        
        # Stop services
        systemctl stop dnstt.service 2>/dev/null || true
        systemctl stop badvpn.service 2>/dev/null || true
        
        # Disable services
        systemctl disable dnstt.service 2>/dev/null || true
        systemctl disable badvpn.service 2>/dev/null || true
        
        # Remove services
        rm -f /etc/systemd/system/dnstt.service
        rm -f /etc/systemd/system/badvpn.service
        
        # Remove configuration
        rm -f "$INFO_FILE"
        rm -rf "$DNSTT_DIR"
        
        # Remove iptables rules
        iptables -D INPUT -p udp --dport 5300 -j ACCEPT 2>/dev/null || true
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        
        # Remove sysctl config
        rm -f /etc/sysctl.d/99-slowdns-optimization.conf
        sysctl --system >/dev/null 2>&1
        
        # Restore original SSH config if backup exists
        if ls /etc/ssh/sshd_config.backup.* 2>/dev/null; then
            latest_backup=$(ls -t /etc/ssh/sshd_config.backup.* | head -1)
            cp -f "$latest_backup" /etc/ssh/sshd_config
            systemctl restart ssh
        fi
        
        # Remove binaries
        rm -f /usr/bin/badvpn-udpgw
        
        systemctl daemon-reload
        
        echo -e "\n${GREEN}✓ SlowDNS has been successfully uninstalled${NC}"
        echo -e "${YELLOW}A backup has been saved to: $BACKUP_DIR${NC}"
    else
        echo -e "\n${GREEN}Uninstallation cancelled${NC}"
    fi
    
    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# -------------------------
# Main Menu
# -------------------------
main_menu() {
    while true; do
        print_header
        
        echo -e "${WHITE}Service Status:${NC}"
        echo -e "  SlowDNS/DNSTT: $(check_dnstt_status)"
        echo -e "  BadVPN UDPGW: $(check_badvpn_status)"
        echo -e "  SSH Service: $(check_ssh_status)"
        
        print_separator
        
        echo -e "${WHITE}MAIN MENU${NC}"
        echo "1. Install/Reinstall SlowDNS"
        echo "2. View SlowDNS Information"
        echo "3. Manage Services"
        echo "4. SSH User Management"
        echo "5. Optimize Network"
        echo "6. Uninstall SlowDNS"
        echo "7. Exit"
        
        print_separator
        
        echo -e "${WHITE}Select option (1-7):${NC}"
        read -r choice
        
        case $choice in
            1) install_slowdns ;;
            2) show_dnstt_info ;;
            3) manage_services ;;
            4) ssh_management_menu ;;
            5)
                optimize_network
                echo -e "${GREEN}Network optimization completed${NC}"
                sleep 2
                ;;
            6) uninstall_slowdns ;;
            7)
                echo -e "\n${GREEN}Thank you for using SlowDNS Moded Panel${NC}"
                echo -e "${CYAN}Telegram: https://t.me/esimfreegb${NC}\n"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${NC}"
                sleep 2
                ;;
        esac
    done
}

# -------------------------
# Initialization
# -------------------------
init() {
    # Check root
    is_root
    
    # Create log file
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Clear screen
    clear
    
    # Log script start
    log_info "SlowDNS Moded Panel started"
    
    # Welcome message
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════╗"
    echo "║    SLOWDNS MODED PANEL - REMASTERED      ║"
    echo "║    Author: esim FREEGB                   ║"
    echo "║    Version: $SCRIPT_VERSION                    ║"
    echo "╚══════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${YELLOW}Initializing...${NC}"
    sleep 2
}

# -------------------------
# Trap for clean exit
# -------------------------
trap cleanup EXIT INT TERM

cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${NC}"
    log_info "Script terminated"
    exit 0
}

# -------------------------
# Main Execution
# -------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init
    main_menu
fi
