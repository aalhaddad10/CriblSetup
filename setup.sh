#!/bin/bash

# Input arguments
STATE=$1
IFACE=$2
SELF_IP=$3
PEER_IP=$4

if [ "$#" -ne 4 ]; then
    echo "Example: ./setup.sh STATE IFACE SELF_IP PEER_IP"
    echo "Example with actual values: ./setup.sh MASTER ens33 192.168.81.140 192.168.81.141"
    exit 1
fi

# Part 1: Cribl Setup
echo "========== Cribl Setup =========="
echo "[+] Cloning CriblSetup repository..."
git clone https://github.com/aalhaddad10/CriblSetup.git 1> /dev/null
cd CriblSetup

echo "[*] Setting up Cribl worker..."
chmod +x install-worker.sh 1> /dev/null
./install-worker.sh

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

# Part 2: Keepalived Setup
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




if ! systemctl is-active --quiet keepalived; then
    echo "[!] Keepalived is not running. Starting it now..."
    sudo systemctl start keepalived
else
    echo "[+] Keepalived service is running ✔"
fi

if ! systemctl is-enabled --quiet keepalived; then
    echo "[!] Keepalived is not enabled. Enabling it now..."
    sudo systemctl enable keepalived
else
    echo "[+] Keepalived service is enabled ✔"
fi

sed -i "s/\bSTATE\b/$STATE/g" /etc/keepalived/keepalived.conf
sed -i "s/\bIFACE\b/$IFACE/g" /etc/keepalived/keepalived.conf
sed -i "s/\bSELF_IP\b/$SELF_IP/g" /etc/keepalived/keepalived.conf
sed -i "s/\bPEER_IP\b/$PEER_IP/g" /etc/keepalived/keepalived.conf
echo "[+] Keepalived configuration updated ✔"

sudo systemctl restart keepalived
 echo "[+] Keepalived service is restarted ✔"

echo "========== Keepalived Setup Complete =========="
