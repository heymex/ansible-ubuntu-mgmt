#!/bin/bash
#
# Bootstrap Host Script
#
# This script bootstraps a new host for Ansible management using raw SSH commands.
# It creates the ansible user, installs SSH keys, and configures sudo access.
# Once complete, the host can be added to the Ansible inventory.
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
#   # Bootstrap with custom SSH key for initial connection
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
INITIAL_USER="${INITIAL_USER:-ubuntu}"
SSH_KEY="${SSH_KEY:-}"
MANAGEMENT_USER="${MANAGEMENT_USER:-ansible}"
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY:-$HOME/.ssh/id_ed25519.pub}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Function to print usage
usage() {
    cat << EOF
Usage: $0 <hostname> [options]

Bootstrap a new host for Ansible management using raw SSH commands.

Arguments:
  hostname              Hostname or IP address of the host to bootstrap

Options:
  -u, --user USER       SSH user for initial connection (default: ubuntu)
  -i, --ip              Treat hostname as IP address (use hostname as target)
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
            INITIAL_USER="$2"
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
    echo -e "${RED}Error: SSH public key not found at $SSH_PUBLIC_KEY${NC}" >&2
    echo "Please specify the correct path with --pub-key or ensure ~/.ssh/id_ed25519.pub exists"
    exit 1
fi

# Auto-detect if hostname is an IP address
if [ -z "$IP_ADDRESS" ]; then
    if [[ "$HOSTNAME" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IP_ADDRESS="$HOSTNAME"
    fi
fi

TARGET_HOST="${IP_ADDRESS:-$HOSTNAME}"

# Validate SSH public key format
if ! grep -qE "^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp|ssh-dss) " "$SSH_PUBLIC_KEY" 2>/dev/null; then
    echo -e "${YELLOW}Warning: SSH public key format may be invalid${NC}" >&2
    echo "Expected format: ssh-ed25519 AAAAC3... or ssh-rsa AAAAB3..."
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}Bootstrapping host: $HOSTNAME${NC}"
echo -e "  Target: $TARGET_HOST"
echo -e "  Initial user: $INITIAL_USER"
echo -e "  Management user: $MANAGEMENT_USER"
echo -e "  SSH public key: $SSH_PUBLIC_KEY"
echo ""

# Build SSH command for initial connection
SSH_CMD="ssh"
SSH_NEEDS_PASSWORD=false
if [ -n "$SSH_KEY" ]; then
    SSH_CMD="$SSH_CMD -i $SSH_KEY"
    echo -e "${GREEN}Using SSH key for initial connection: $SSH_KEY${NC}"
elif ssh -o BatchMode=yes -o ConnectTimeout=5 "$INITIAL_USER@$TARGET_HOST" exit 2>/dev/null; then
    echo -e "${GREEN}SSH key authentication available for initial connection${NC}"
else
    echo -e "${YELLOW}Password authentication will be required for initial connection${NC}"
    echo "You will be prompted for the password for $INITIAL_USER@$TARGET_HOST"
    SSH_NEEDS_PASSWORD=true
fi

# Test initial connection
echo ""
echo "Testing initial connection..."
TEST_SSH_CMD="ssh"
if [ -n "$SSH_KEY" ]; then
    TEST_SSH_CMD="$TEST_SSH_CMD -i $SSH_KEY"
fi
if $TEST_SSH_CMD -o ConnectTimeout=10 "$INITIAL_USER@$TARGET_HOST" exit 2>/dev/null; then
    echo -e "${GREEN}✓ Initial connection successful${NC}"
else
    echo -e "${RED}✗ Initial connection failed${NC}"
    echo "Please ensure you can SSH to $INITIAL_USER@$TARGET_HOST"
    exit 1
fi

# Check if initial user has passwordless sudo
echo ""
echo "Checking sudo access..."
if $SSH_CMD "$INITIAL_USER@$TARGET_HOST" "sudo -n true" 2>/dev/null; then
    echo "  Passwordless sudo is configured for $INITIAL_USER"
    SUDO_NEEDS_PASSWORD=false
else
    echo "  Sudo will require a password for $INITIAL_USER"
    SUDO_NEEDS_PASSWORD=true
    # Use -t flag to allocate pseudo-terminal for sudo password prompts
    SSH_CMD="$SSH_CMD -t"
fi

# Step 1: Create the management user
echo ""
echo "Step 1: Creating user '$MANAGEMENT_USER'..."
if $SSH_CMD "$INITIAL_USER@$TARGET_HOST" "id $MANAGEMENT_USER" &>/dev/null; then
    echo "  User $MANAGEMENT_USER already exists"
else
    echo "  Creating user..."
    if [ "$SUDO_NEEDS_PASSWORD" = true ]; then
        echo "  (You will be prompted for the sudo password)"
    fi
    $SSH_CMD "$INITIAL_USER@$TARGET_HOST" "sudo useradd -m -s /bin/bash $MANAGEMENT_USER && sudo usermod -aG sudo $MANAGEMENT_USER" || {
        echo -e "  ${RED}Failed to create user${NC}"
        exit 1
    }
    echo -e "  ${GREEN}✓ User created${NC}"
fi

# Step 2: Install SSH key using ssh-copy-id
echo ""
echo "Step 2: Installing SSH public key..."
PRIVATE_KEY_FILE="${SSH_PUBLIC_KEY%.pub}"
if [ ! -f "$PRIVATE_KEY_FILE" ]; then
    if [[ "$SSH_PUBLIC_KEY" == *"id_ed25519.pub" ]]; then
        PRIVATE_KEY_FILE="$HOME/.ssh/id_ed25519"
    elif [[ "$SSH_PUBLIC_KEY" == *"id_rsa.pub" ]]; then
        PRIVATE_KEY_FILE="$HOME/.ssh/id_rsa"
    fi
fi

# Build ssh-copy-id command
SSH_COPY_ID_CMD="ssh-copy-id"
if [ -n "$SSH_KEY" ]; then
    SSH_COPY_ID_CMD="$SSH_COPY_ID_CMD -i $SSH_KEY"
elif [ -f "$PRIVATE_KEY_FILE" ]; then
    SSH_COPY_ID_CMD="$SSH_COPY_ID_CMD -i $PRIVATE_KEY_FILE"
fi

# Use ssh-copy-id to install the key
if $SSH_COPY_ID_CMD -f "$MANAGEMENT_USER@$TARGET_HOST" 2>&1 | grep -v "WARNING:"; then
    echo -e "  ${GREEN}✓ SSH key installed${NC}"
else
    # If ssh-copy-id fails, try manual method
    echo "  ssh-copy-id failed, trying manual method..."
    if [ "$SUDO_NEEDS_PASSWORD" = true ]; then
        echo "  (You will be prompted for the sudo password)"
    fi
    $SSH_CMD "$INITIAL_USER@$TARGET_HOST" "sudo mkdir -p /home/$MANAGEMENT_USER/.ssh && sudo chmod 700 /home/$MANAGEMENT_USER/.ssh && echo '$(cat "$SSH_PUBLIC_KEY")' | sudo tee -a /home/$MANAGEMENT_USER/.ssh/authorized_keys > /dev/null && sudo chmod 600 /home/$MANAGEMENT_USER/.ssh/authorized_keys && sudo chown -R $MANAGEMENT_USER:$MANAGEMENT_USER /home/$MANAGEMENT_USER/.ssh" || {
        echo -e "  ${RED}Failed to install SSH key${NC}"
        exit 1
    }
    echo -e "  ${GREEN}✓ SSH key installed${NC}"
fi

# Step 3: Configure passwordless sudo
echo ""
echo "Step 3: Configuring passwordless sudo..."
if [ "$SUDO_NEEDS_PASSWORD" = true ]; then
    echo "  (You will be prompted for the sudo password)"
fi
$SSH_CMD "$INITIAL_USER@$TARGET_HOST" "echo '$MANAGEMENT_USER ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/ansible-$MANAGEMENT_USER > /dev/null && sudo chmod 440 /etc/sudoers.d/ansible-$MANAGEMENT_USER && sudo visudo -cf /etc/sudoers.d/ansible-$MANAGEMENT_USER" || {
    echo -e "  ${RED}Failed to configure sudo${NC}"
    exit 1
}
echo -e "  ${GREEN}✓ Passwordless sudo configured${NC}"

# Test connection as management user
echo ""
echo "Testing connection as $MANAGEMENT_USER..."
if [ -f "$PRIVATE_KEY_FILE" ]; then
    TEST_SSH_CMD="ssh -i $PRIVATE_KEY_FILE"
else
    TEST_SSH_CMD="ssh"
fi

if $TEST_SSH_CMD -o ConnectTimeout=10 -o BatchMode=yes "$MANAGEMENT_USER@$TARGET_HOST" exit 2>/dev/null; then
    echo -e "${GREEN}✓ Connection test successful!${NC}"
    echo ""
    echo "The host is now ready for Ansible management."
    echo ""
    
    # Build inventory entry
    INVENTORY_ENTRY="$HOSTNAME ansible_host=$TARGET_HOST ansible_user=$MANAGEMENT_USER"
    if [ -f "$PRIVATE_KEY_FILE" ] && [[ "$PRIVATE_KEY_FILE" != "$HOME/.ssh/id_ed25519" ]] && [[ "$PRIVATE_KEY_FILE" != "$HOME/.ssh/id_rsa" ]]; then
        INVENTORY_ENTRY="$INVENTORY_ENTRY ansible_ssh_private_key_file=$PRIVATE_KEY_FILE"
    fi
    
    # Offer to add to inventory
    MAIN_INVENTORY="$PROJECT_DIR/inventory/hosts"
    read -p "Add to main inventory ($MAIN_INVENTORY)? (Y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        if [ -f "$MAIN_INVENTORY" ]; then
            # Remove existing entry if present
            sed -i.bak "/^$HOSTNAME /d" "$MAIN_INVENTORY" 2>/dev/null || true
            # Add new entry
            echo "$INVENTORY_ENTRY" >> "$MAIN_INVENTORY"
            echo -e "${GREEN}Added to $MAIN_INVENTORY${NC}"
            echo ""
            echo "Inventory entry:"
            echo "  $INVENTORY_ENTRY"
            echo ""
            echo "You can now test with: ansible $HOSTNAME -m ping"
        else
            echo -e "${YELLOW}Main inventory file not found at $MAIN_INVENTORY${NC}"
            echo "Please add manually:"
            echo "  $INVENTORY_ENTRY"
        fi
    else
        echo ""
        echo "Add this entry to inventory/hosts:"
        echo "  $INVENTORY_ENTRY"
    fi
else
    echo -e "${YELLOW}⚠ Connection test failed${NC}"
    echo ""
    echo "Troubleshooting:"
    if [ -f "$PRIVATE_KEY_FILE" ]; then
        echo "1. Test SSH manually: ssh -i $PRIVATE_KEY_FILE $MANAGEMENT_USER@$TARGET_HOST"
    else
        echo "1. Test SSH manually: ssh $MANAGEMENT_USER@$TARGET_HOST"
        echo "   (Private key not found at expected location: $PRIVATE_KEY_FILE)"
    fi
    echo "2. Verify the SSH key was installed:"
    echo "   $SSH_CMD $INITIAL_USER@$TARGET_HOST 'sudo cat /home/$MANAGEMENT_USER/.ssh/authorized_keys'"
    echo "3. Check that the management user exists:"
    echo "   $SSH_CMD $INITIAL_USER@$TARGET_HOST 'id $MANAGEMENT_USER'"
    exit 1
fi
