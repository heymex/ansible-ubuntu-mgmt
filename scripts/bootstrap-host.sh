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

# Read the public key content
SSH_KEY_CONTENT="$(cat "$SSH_PUBLIC_KEY" | tr -d '\n')"

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
    # Use -t flag to allocate pseudo-terminal for password prompts
    SSH_CMD="$SSH_CMD -t"
fi

# Test initial connection (without -t for this test to avoid password prompt)
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

# Bootstrap script to run on remote host
BOOTSTRAP_SCRIPT=$(cat << 'BOOTSTRAP_EOF'
#!/bin/bash
set -euo pipefail

MANAGEMENT_USER="$1"
SSH_KEY_CONTENT="$2"
INITIAL_USER="$3"

# Create management user if it doesn't exist
if ! id "$MANAGEMENT_USER" &>/dev/null; then
    echo "Creating user: $MANAGEMENT_USER"
    useradd -m -s /bin/bash "$MANAGEMENT_USER"
    
    # Add to sudo group
    if command -v usermod > /dev/null 2>&1; then
        usermod -aG sudo "$MANAGEMENT_USER" 2>/dev/null || true
    fi
else
    echo "User $MANAGEMENT_USER already exists"
fi

# Create .ssh directory
mkdir -p "/home/$MANAGEMENT_USER/.ssh"
chmod 700 "/home/$MANAGEMENT_USER/.ssh"
chown "$MANAGEMENT_USER:$MANAGEMENT_USER" "/home/$MANAGEMENT_USER/.ssh"

# Add SSH key to authorized_keys
AUTH_KEYS="/home/$MANAGEMENT_USER/.ssh/authorized_keys"
if ! grep -qF "$SSH_KEY_CONTENT" "$AUTH_KEYS" 2>/dev/null; then
    echo "$SSH_KEY_CONTENT" >> "$AUTH_KEYS"
    echo "Added SSH key to authorized_keys"
else
    echo "SSH key already in authorized_keys"
fi
chmod 600 "$AUTH_KEYS"
chown "$MANAGEMENT_USER:$MANAGEMENT_USER" "$AUTH_KEYS"

# Configure passwordless sudo
SUDOERS_FILE="/etc/sudoers.d/ansible-$MANAGEMENT_USER"
if [ ! -f "$SUDOERS_FILE" ]; then
    echo "$MANAGEMENT_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS_FILE"
    chmod 440 "$SUDOERS_FILE"
    # Validate sudoers file
    if command -v visudo > /dev/null 2>&1; then
        visudo -cf "$SUDOERS_FILE" || {
            echo "Warning: Sudoers file validation failed, removing"
            rm -f "$SUDOERS_FILE"
            exit 1
        }
    fi
    echo "Configured passwordless sudo for $MANAGEMENT_USER"
else
    echo "Passwordless sudo already configured"
fi

# Also ensure initial user has passwordless sudo (if different)
if [ "$INITIAL_USER" != "$MANAGEMENT_USER" ] && [ "$INITIAL_USER" != "root" ]; then
    INITIAL_SUDOERS="/etc/sudoers.d/ansible-$INITIAL_USER"
    if [ ! -f "$INITIAL_SUDOERS" ]; then
        echo "$INITIAL_USER ALL=(ALL) NOPASSWD: ALL" > "$INITIAL_SUDOERS"
        chmod 440 "$INITIAL_SUDOERS"
        if command -v visudo > /dev/null 2>&1; then
            visudo -cf "$INITIAL_SUDOERS" || rm -f "$INITIAL_SUDOERS"
        fi
    fi
fi

echo "Bootstrap complete for $MANAGEMENT_USER"
BOOTSTRAP_EOF
)

# Execute bootstrap script on remote host
echo ""
echo "Running bootstrap on remote host..."
echo "This will:"
echo "  1. Create user: $MANAGEMENT_USER"
echo "  2. Install SSH public key"
echo "  3. Configure passwordless sudo"
if [ "$SSH_NEEDS_PASSWORD" = true ]; then
    echo ""
    echo "You will be prompted for the sudo password for $INITIAL_USER"
fi

# Use -t flag to allocate pseudo-terminal for sudo password prompts
# This allows sudo to prompt for password interactively
if $SSH_CMD "$INITIAL_USER@$TARGET_HOST" "sudo bash -s" <<< "$BOOTSTRAP_SCRIPT" "$MANAGEMENT_USER" "$SSH_KEY_CONTENT" "$INITIAL_USER"; then
    echo ""
    echo -e "${GREEN}✓ Bootstrap completed successfully!${NC}"
else
    echo ""
    echo -e "${RED}✗ Bootstrap failed${NC}"
    echo ""
    echo "Common issues:"
    echo "  - Incorrect sudo password"
    echo "  - User $INITIAL_USER doesn't have sudo access"
    echo "  - Network connectivity issues"
    exit 1
fi

# Test connection as management user
echo ""
echo "Testing connection as $MANAGEMENT_USER..."
PRIVATE_KEY_FILE="${SSH_PUBLIC_KEY%.pub}"
if [ ! -f "$PRIVATE_KEY_FILE" ]; then
    if [[ "$SSH_PUBLIC_KEY" == *"id_ed25519.pub" ]]; then
        PRIVATE_KEY_FILE="$HOME/.ssh/id_ed25519"
    elif [[ "$SSH_PUBLIC_KEY" == *"id_rsa.pub" ]]; then
        PRIVATE_KEY_FILE="$HOME/.ssh/id_rsa"
    fi
fi

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
