#!/bin/bash
if [ "$EUID" -ne 0 ]; 
then
  echo "Please run as root (sudo)."
  exit 1
fi
# Initialize variables
INSTALL_CRIBL=false
INSTALL_KEEPALIVED=false
STATE=""
IFACE=""
SELF_IP=""
PEER_IP=""
VIP=""

# Function to display usage
usage() {
    echo "Usage:"
    echo "  Install Cribl only: ./setup.sh -c or ./setup.sh --cribl"
    echo "  Install Keepalived only: ./setup.sh -k --state MASTER --iface ens33 --self 192.168.81.140 --peer 192.168.81.141 --vip 192.168.81.142"
    echo "  Install Both (Cribl & Keepalived): ./setup.sh --cribl --keepalived --state MASTER --iface ens33 --self 192.168.81.140 --peer 192.168.81.141 --vip 192.168.81.142"
    echo
    echo "Options:"
    echo "  -c, --cribl         Install Cribl only"
    echo "  -k, --keepalived    Install Keepalived only (requires additional options)"
    echo "  --all               Install both Cribl & Keepalived"
    echo "  -s, --state STATE   Keepalived state (MASTER or BACKUP)"
    echo "  -i, --iface IFACE   Network interface (e.g., ens33)"
    echo "  -n, --self IP       Self IP address"
    echo "  -p, --peer IP       Peer IP address"
    echo "  -v, --vip IP        Virtual IP address"
    exit 1
}

# if no option was provided, print menu and exit
[ "$#" -eq 0 ] && usage && exit 1

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -c|--cribl) INSTALL_CRIBL=true ;;
        -k|--keepalived) INSTALL_KEEPALIVED=true ;;
        --all) INSTALL_CRIBL=true; INSTALL_KEEPALIVED=true ;;
        -s|--state) STATE="$2"; shift ;;
        -i|--iface) IFACE="$2"; shift ;;
        -n|--self) SELF_IP="$2"; shift ;;
        -p|--peer) PEER_IP="$2"; shift ;;
        -v|--vip) VIP="$2"; shift ;;
        *) echo "[ERROR] Invalid option: $1"; usage ;;
    esac
    shift
done

# Part 1: Cribl Setup
if [[ "$INSTALL_CRIBL" == true ]]; then
    echo -e "========== Cribl Setup ==========\n"
    echo "[+] Downloading up Cribl Binary (Zipped)..."
    wget $(curl https://cdn.cribl.io/dl/latest-x64) -O cribl.tar.gz
    [ -f cribl.tar.gz ] && echo "[+] Cribl binary was downloaded successfully, proceeding..." || (echo "[!] Cribl binary download failed. Exiting" && exit 1)
    
    echo "[+] Setting up Cribl worker..."
    chmod +x install-worker.sh
    ./install-worker.sh 1> /dev/null

    if ! systemctl is-active --quiet cribl; then
        echo "[!] Cribl service is not running. Starting it now..."
        sudo systemctl start cribl
    else
        echo "[+] Cribl service is running ✔"
    fi

    if ! systemctl is-enabled --quiet cribl; then
        echo "[!] Enabling Cribl service..."
        sudo systemctl enable cribl
    else
        echo "[+] Cribl service is enabled ✔"
    fi
    echo "========== Cribl Setup Complete =========="
    echo
fi

# Part 2: Keepalived Setup
if [[ "$INSTALL_KEEPALIVED" == true ]]; then
    echo "========== Keepalived Setup =========="
    echo "[*] Installing Keepalived..."
    sudo apt install -y keepalived 1> /dev/null

    if keepalived --version > /dev/null 2>&1; then
        echo "[+] Keepalived installed successfully."
    else
        echo "[-] Keepalived installation failed. Exiting."
        exit 1
    fi

    # Update Keepalived configuration
    echo "[*] Updating Keepalived configuration..."
    mv http_check.sh /usr/local/bin/
    chmod +x /usr/local/bin/http_check.sh
    mv keepalived.conf /etc/keepalived/keepalived.conf

    sed -i "s/\bSTATE\b/$STATE/g" /etc/keepalived/keepalived.conf
    sed -i "s/\bIFACE\b/$IFACE/g" /etc/keepalived/keepalived.conf
    sed -i "s/\bSELF_IP\b/$SELF_IP/g" /etc/keepalived/keepalived.conf
    sed -i "s/\bPEER_IP\b/$PEER_IP/g" /etc/keepalived/keepalived.conf
    sed -i "s/\bVIP\b/$VIP/g" /etc/keepalived/keepalived.conf

    echo "[+] Keepalived configuration updated ✔"
    sudo systemctl restart keepalived
    echo "[+] Keepalived service is restarted ✔"
    sudo systemctl enable keepalived
    echo "[+] Keepalived service is enabled ✔"
    echo
    echo "========== Keepalived Setup Complete =========="
    echo
fi
