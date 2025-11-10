#!/bin/bash

# Script to find the SSH private key for VKS VMs
# Usage: ./find-vks-ssh-key.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo ""
print_info "Searching for SSH private keys that match VKS VMs..."
echo ""

# The public key we're looking for
TARGET_KEY_START="AAAAB3NzaC1yc2EAAAADAQABAAACAQDS5zd"

print_info "Step 1: Searching for private keys in common locations..."
PRIVATE_KEYS=$(find ~ -name "id_rsa" -o -name "id_ed25519" -o -name "*.pem" -o -name "*key" -o -name "id_*" 2>/dev/null | grep -v ".pub")

if [ -n "$PRIVATE_KEYS" ]; then
    print_success "Found some private keys. Checking for matches..."
    echo ""
    
    for key in $PRIVATE_KEYS; do
        if [ -f "$key" ]; then
            # Try to generate public key from private key and compare
            pub_key=$(ssh-keygen -y -f "$key" 2>/dev/null || echo "")
            if echo "$pub_key" | grep -q "$TARGET_KEY_START"; then
                print_success "MATCH FOUND: $key"
                echo ""
                echo "To connect to VKS VMs, use:"
                echo "  ssh -i $key root@192.173.237.67"
                echo ""
                exit 0
            fi
        fi
    done
    
    print_warning "Checked all private keys, but none matched the VKS VM public key"
else
    print_warning "No private keys found in common locations"
fi

echo ""
print_info "Step 2: Checking if key might be in VCF/VKS configuration..."

# Check VCF config directory
if [ -d ~/.config/vcf ]; then
    print_info "Checking VCF config directory..."
    find ~/.config/vcf -type f 2>/dev/null | while read file; do
        if grep -q "BEGIN.*PRIVATE KEY" "$file" 2>/dev/null; then
            print_info "Found potential key in: $file"
        fi
    done
fi

# Check for Tanzu/VKS directories
if [ -d ~/.tanzu ]; then
    print_info "Checking Tanzu config directory..."
    find ~/.tanzu -name "*key*" -o -name "*.pem" 2>/dev/null
fi

echo ""
print_info "Step 3: Checking running SSH agent..."
if [ -n "$SSH_AUTH_SOCK" ]; then
    print_success "SSH agent is running"
    print_info "Loaded keys:"
    ssh-add -L 2>/dev/null || print_warning "No keys in agent"
    
    # Check if our target key is loaded
    if ssh-add -L 2>/dev/null | grep -q "$TARGET_KEY_START"; then
        print_success "The VKS SSH key IS loaded in your SSH agent!"
        echo ""
        echo "You can connect without specifying a key file:"
        echo "  ssh root@192.173.237.67"
        echo ""
        exit 0
    fi
else
    print_warning "SSH agent not running"
fi

echo ""
print_error "SSH private key not found on this system"
echo ""
print_info "Alternative Solutions:"
echo ""
echo "1. Use vSphere Console (RECOMMENDED):"
echo "   - Log into vCenter Web UI"
echo "   - Search for VM: vks-02-wbf8d-2xh2w"
echo "   - Right-click → Launch Web Console"
echo "   - Login as 'root' (usually no password)"
echo ""
echo "2. Check if the key is on another machine:"
echo "   - The key might be on the workstation used to create the cluster"
echo "   - Look for the key there and copy it to this VM"
echo ""
echo "3. Add a new SSH key to the VM:"
echo "   - Access VM via vSphere console"
echo "   - Generate a new key pair: ssh-keygen -t rsa"
echo "   - Add your public key to /root/.ssh/authorized_keys"
echo ""
echo "4. Check VKS documentation:"
echo "   - Your VKS setup might have a default key location"
echo "   - Contact your VKS administrator"
echo ""

