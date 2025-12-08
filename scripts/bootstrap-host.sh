#!/bin/bash
#
# Bootstrap Host Script
#
# This script simplifies the process of bootstrapping a new host for Ansible management.
# It handles different authentication scenarios and guides you through the process.
#
# Usage:
#   ./scripts/bootstrap-host.sh <hostname> [options]
#
# Examples:
#   # Bootstrap with password authentication (will prompt)
#   ./scripts/bootstrap-host.sh server1.example.com
#
#   # Bootstrap with specific user
#   ./scripts/bootstrap-host.sh server1.example.com --user admin
#
#   # Bootstrap with IP address
#   ./scripts/bootstrap-host.sh 192.168.1.100 --ip
#
#   # Bootstrap with custom SSH key
#   ./scripts/bootstrap-host.sh server1.example.com --ssh-key ~/.ssh/custom_key

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
HOSTNAME=""
IP_ADDRESS=""
ANSIBLE_USER="${ANSIBLE_USER:-ubuntu}"
SSH_KEY="${SSH_KEY:-}"
MANAGEMENT_USER="${MANAGEMENT_USER:-ansible}"
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY:-$HOME/.ssh/id_ed25519.pub}"
BOOTSTRAP_INVENTORY="inventory/bootstrap-hosts.ini"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Function to print usage
usage() {
    cat << EOF
Usage: $0 <hostname> [options]

Bootstrap a new host for Ansible management.

Arguments:
  hostname              Hostname or IP address of the host to bootstrap

Options:
  -u, --user USER       SSH user for initial connection (default: ubuntu)
  -i, --ip              Treat hostname as IP address (use hostname as ansible_host)
  -k, --ssh-key PATH    Path to SSH private key for initial connection
  -m, --mgmt-user USER  User to create for Ansible management (default: ansible)
  -p, --pub-key PATH    Path to SSH public key to install (default: ~/.ssh/id_ed25519.pub)
  -h, --help            Show this help message

Examples:
  $0 server1.example.com
  $0 server1.example.com --user admin
  $0 192.168.1.100 --ip
  $0 server1.example.com --ssh-key ~/.ssh/custom_key

EOF
    exit 1
}

# Parse arguments
if [ $# -eq 0 ]; then
    usage
fi

HOSTNAME="$1"
shift

while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--user)
            ANSIBLE_USER="$2"
            shift 2
            ;;
        -i|--ip)
            IP_ADDRESS="$HOSTNAME"
            shift
            ;;
        -k|--ssh-key)
            SSH_KEY="$2"
            shift 2
            ;;
        -m|--mgmt-user)
            MANAGEMENT_USER="$2"
            shift 2
            ;;
        -p|--pub-key)
            SSH_PUBLIC_KEY="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}" >&2
            usage
            ;;
    esac
done

# Validate inputs
if [ -z "$HOSTNAME" ]; then
    echo -e "${RED}Error: Hostname is required${NC}" >&2
    usage
fi

if [ ! -f "$SSH_PUBLIC_KEY" ]; then
    echo -e "${YELLOW}Warning: SSH public key not found at $SSH_PUBLIC_KEY${NC}" >&2
    echo "Please specify the correct path with --pub-key or ensure ~/.ssh/id_ed25519.pub exists"
    exit 1
fi

# Change to project directory
cd "$PROJECT_DIR"

# Create bootstrap inventory if it doesn't exist
if [ ! -f "$BOOTSTRAP_INVENTORY" ]; then
    echo -e "${YELLOW}Creating bootstrap inventory file: $BOOTSTRAP_INVENTORY${NC}"
    cp inventory/bootstrap-hosts.ini.example "$BOOTSTRAP_INVENTORY"
fi

# Auto-detect if hostname is an IP address
if [ -z "$IP_ADDRESS" ]; then
    # Check if HOSTNAME looks like an IP address
    if [[ "$HOSTNAME" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IP_ADDRESS="$HOSTNAME"
    fi
fi

# Build inventory entry
if [ -n "$IP_ADDRESS" ]; then
    INVENTORY_ENTRY="$HOSTNAME ansible_host=$IP_ADDRESS ansible_user=$ANSIBLE_USER"
else
    INVENTORY_ENTRY="$HOSTNAME ansible_user=$ANSIBLE_USER"
fi

if [ -n "$SSH_KEY" ]; then
    INVENTORY_ENTRY="$INVENTORY_ENTRY ansible_ssh_private_key_file=$SSH_KEY"
fi

# Add host to bootstrap inventory
echo -e "${GREEN}Adding host to bootstrap inventory...${NC}"

# Ensure bootstrap_hosts group exists
if ! grep -q "^\[bootstrap_hosts\]" "$BOOTSTRAP_INVENTORY" 2>/dev/null; then
    # Add the group if it doesn't exist
    {
        echo ""
        echo "[bootstrap_hosts]"
    } >> "$BOOTSTRAP_INVENTORY"
fi

# Remove existing entry if present (anywhere in file, including comments)
sed -i.bak "/^[[:space:]]*$HOSTNAME[[:space:]]/d" "$BOOTSTRAP_INVENTORY" 2>/dev/null || true

# Create a temporary file for the updated inventory
TMP_INVENTORY=$(mktemp)
IN_GROUP=false
HOST_ADDED=false

# Process the inventory file
while IFS= read -r line || [ -n "$line" ]; do
    # Check if we're entering the bootstrap_hosts group
    if [[ "$line" =~ ^\[bootstrap_hosts\] ]]; then
        echo "$line" >> "$TMP_INVENTORY"
        IN_GROUP=true
        # Add the host entry right after the group header
        echo "$INVENTORY_ENTRY" >> "$TMP_INVENTORY"
        HOST_ADDED=true
    # Check if we're leaving the group (entering another group)
    elif [[ "$line" =~ ^\[ ]] && [ "$IN_GROUP" = true ]; then
        IN_GROUP=false
        echo "$line" >> "$TMP_INVENTORY"
    else
        echo "$line" >> "$TMP_INVENTORY"
    fi
done < "$BOOTSTRAP_INVENTORY"

# If host wasn't added (group didn't exist or was empty), add it
if [ "$HOST_ADDED" = false ]; then
    # Find bootstrap_hosts group and add after it
    if grep -q "^\[bootstrap_hosts\]" "$TMP_INVENTORY"; then
        # Use awk to insert after the group header
        awk -v entry="$INVENTORY_ENTRY" '
            /^\[bootstrap_hosts\]/ {print; print entry; next}
            {print}
        ' "$TMP_INVENTORY" > "${TMP_INVENTORY}.tmp" && mv "${TMP_INVENTORY}.tmp" "$TMP_INVENTORY"
    else
        # Add group and host
        {
            echo ""
            echo "[bootstrap_hosts]"
            echo "$INVENTORY_ENTRY"
        } >> "$TMP_INVENTORY"
    fi
fi

# Replace the original file
mv "$TMP_INVENTORY" "$BOOTSTRAP_INVENTORY"

# Verify the host was added correctly
if grep -A 10 "^\[bootstrap_hosts\]" "$BOOTSTRAP_INVENTORY" | grep -q "^$HOSTNAME "; then
    echo -e "${GREEN}Host added to [bootstrap_hosts] group${NC}"
else
    echo -e "${YELLOW}Warning: Host may not have been added correctly to bootstrap_hosts group${NC}"
    echo "Please check $BOOTSTRAP_INVENTORY manually"
fi

# Validate SSH public key format
if ! grep -qE "^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp|ssh-dss) " "$SSH_PUBLIC_KEY" 2>/dev/null; then
    echo -e "${YELLOW}Warning: SSH public key format may be invalid${NC}" >&2
    echo "Expected format: ssh-ed25519 AAAAC3... or ssh-rsa AAAAB3..."
fi

# Verify inventory before running playbook
echo -e "${GREEN}Verifying inventory...${NC}"
if ! ansible-inventory -i "$BOOTSTRAP_INVENTORY" --list > /dev/null 2>&1; then
    echo -e "${YELLOW}Warning: Inventory validation failed, but continuing...${NC}"
fi

# Show what hosts are in bootstrap_hosts group
BOOTSTRAP_HOSTS=$(ansible-inventory -i "$BOOTSTRAP_INVENTORY" --list 2>/dev/null | grep -A 20 '"bootstrap_hosts"' | grep -o '"[^"]*"' | tr -d '"' | grep -v "^bootstrap_hosts$" || echo "")
if [ -n "$BOOTSTRAP_HOSTS" ]; then
    echo "Hosts in bootstrap_hosts group: $BOOTSTRAP_HOSTS"
fi

# Build ansible-playbook command
# Read the public key and escape it properly for the command line
SSH_KEY_CONTENT="$(cat "$SSH_PUBLIC_KEY" | tr -d '\n')"
PLAYBOOK_CMD="ansible-playbook playbooks/bootstrap-host.yml -i $BOOTSTRAP_INVENTORY --limit $HOSTNAME"
PLAYBOOK_CMD="$PLAYBOOK_CMD -e bootstrap_ansible_user=$MANAGEMENT_USER"
PLAYBOOK_CMD="$PLAYBOOK_CMD -e bootstrap_ssh_public_key='$SSH_KEY_CONTENT'"

# Determine authentication method
if [ -n "$SSH_KEY" ]; then
    echo -e "${GREEN}Using SSH key authentication: $SSH_KEY${NC}"
    AUTH_METHOD="key"
elif ssh -o BatchMode=yes -o ConnectTimeout=5 "$ANSIBLE_USER@${IP_ADDRESS:-$HOSTNAME}" exit 2>/dev/null; then
    echo -e "${GREEN}SSH key authentication available${NC}"
    AUTH_METHOD="key"
else
    echo -e "${YELLOW}SSH key authentication not available. Will prompt for password.${NC}"
    AUTH_METHOD="password"
    PLAYBOOK_CMD="$PLAYBOOK_CMD --ask-pass --ask-become-pass"
fi

echo ""
echo -e "${GREEN}Bootstrapping host: $HOSTNAME${NC}"
echo -e "  User: $ANSIBLE_USER"
echo -e "  Management user: $MANAGEMENT_USER"
echo -e "  SSH public key: $SSH_PUBLIC_KEY"
echo ""

# Run the playbook
if eval "$PLAYBOOK_CMD"; then
    echo ""
    echo -e "${GREEN}✓ Bootstrap completed successfully!${NC}"
    echo ""
    
    # Determine the private key file that corresponds to the public key
    PRIVATE_KEY_FILE="${SSH_PUBLIC_KEY%.pub}"
    
    # If using a non-standard path, try to find the corresponding private key
    if [[ ! -f "$PRIVATE_KEY_FILE" ]]; then
        # Try common locations
        if [[ "$SSH_PUBLIC_KEY" == *"id_ed25519.pub" ]]; then
            PRIVATE_KEY_FILE="$HOME/.ssh/id_ed25519"
        elif [[ "$SSH_PUBLIC_KEY" == *"id_rsa.pub" ]]; then
            PRIVATE_KEY_FILE="$HOME/.ssh/id_rsa"
        fi
    fi
    
    # Check if private key exists
    if [ ! -f "$PRIVATE_KEY_FILE" ]; then
        echo -e "${YELLOW}Warning: Private key not found at $PRIVATE_KEY_FILE${NC}"
        echo "You may need to specify ansible_ssh_private_key_file in inventory"
        PRIVATE_KEY_FILE=""
    fi
    
    # Build inventory entry
    INVENTORY_ENTRY="$HOSTNAME ansible_host=${IP_ADDRESS:-$HOSTNAME} ansible_user=$MANAGEMENT_USER"
    # Only specify private key file if it's not in the default location
    # (SSH will automatically find ~/.ssh/id_ed25519, ~/.ssh/id_rsa, etc.)
    if [ -n "$PRIVATE_KEY_FILE" ] && [[ "$PRIVATE_KEY_FILE" != "$HOME/.ssh/id_ed25519" ]] && [[ "$PRIVATE_KEY_FILE" != "$HOME/.ssh/id_rsa" ]]; then
        INVENTORY_ENTRY="$INVENTORY_ENTRY ansible_ssh_private_key_file=$PRIVATE_KEY_FILE"
    fi
    
    echo "Next steps:"
    echo "1. Add this host to inventory/hosts:"
    echo "   $INVENTORY_ENTRY"
    echo ""
    
    # Test if we can automatically add and test
    read -p "Add to main inventory and test connection now? (Y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        # Add to main inventory
        MAIN_INVENTORY="inventory/hosts"
        if [ -f "$MAIN_INVENTORY" ]; then
            # Remove existing entry if present
            sed -i.bak "/^$HOSTNAME /d" "$MAIN_INVENTORY" 2>/dev/null || true
            # Add new entry
            echo "$INVENTORY_ENTRY" >> "$MAIN_INVENTORY"
            echo -e "${GREEN}Added to $MAIN_INVENTORY${NC}"
            
            # Test connection
            echo ""
            echo "Testing connection..."
            TEST_OUTPUT=$(ansible "$HOSTNAME" -m ping 2>&1)
            TEST_RC=$?
            if [ $TEST_RC -eq 0 ]; then
                echo -e "${GREEN}✓ Connection test successful!${NC}"
                echo ""
                echo "You can now manage this host with Ansible."
            else
                echo -e "${YELLOW}⚠ Connection test failed.${NC}"
                echo ""
                echo "Error output:"
                echo "$TEST_OUTPUT" | tail -5
                echo ""
                echo "Troubleshooting:"
                if [ -n "$PRIVATE_KEY_FILE" ]; then
                    echo "1. Test SSH manually: ssh -i $PRIVATE_KEY_FILE $MANAGEMENT_USER@${IP_ADDRESS:-$HOSTNAME}"
                else
                    echo "1. Test SSH manually: ssh $MANAGEMENT_USER@${IP_ADDRESS:-$HOSTNAME}"
                fi
                echo "2. Check inventory entry matches above"
                echo "3. Verify the private key matches the public key that was installed"
                echo "4. Check that the management user exists and has the SSH key in ~/.ssh/authorized_keys"
                echo ""
                if [ -n "$PRIVATE_KEY_FILE" ] && [[ "$PRIVATE_KEY_FILE" != "$HOME/.ssh/id_ed25519" ]] && [[ "$PRIVATE_KEY_FILE" != "$HOME/.ssh/id_rsa" ]]; then
                    echo "You may need to manually specify the SSH key in inventory:"
                    echo "  $HOSTNAME ansible_host=${IP_ADDRESS:-$HOSTNAME} ansible_user=$MANAGEMENT_USER ansible_ssh_private_key_file=$PRIVATE_KEY_FILE"
                fi
            fi
        else
            echo -e "${YELLOW}Main inventory file not found. Please add manually:${NC}"
            echo "   $INVENTORY_ENTRY"
        fi
    else
        echo ""
        echo "2. Test connection manually:"
        echo "   ansible $HOSTNAME -m ping"
        echo ""
        echo "3. Apply system tweaks:"
        echo "   ansible-playbook playbooks/apply-system-tweaks.yml --limit $HOSTNAME"
    fi
    
    echo ""
    # Optionally remove from bootstrap inventory
    read -p "Remove from bootstrap inventory? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sed -i.bak "/^$HOSTNAME /d" "$BOOTSTRAP_INVENTORY"
        echo -e "${GREEN}Removed from bootstrap inventory${NC}"
    fi
else
    echo ""
    echo -e "${RED}✗ Bootstrap failed. Please check the errors above.${NC}"
    exit 1
fi
