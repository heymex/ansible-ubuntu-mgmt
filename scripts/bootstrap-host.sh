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
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY:-$HOME/.ssh/id_rsa.pub}"
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
  -p, --pub-key PATH    Path to SSH public key to install (default: ~/.ssh/id_rsa.pub)
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
    echo "Please specify the correct path with --pub-key or ensure ~/.ssh/id_rsa.pub exists"
    exit 1
fi

# Change to project directory
cd "$PROJECT_DIR"

# Create bootstrap inventory if it doesn't exist
if [ ! -f "$BOOTSTRAP_INVENTORY" ]; then
    echo -e "${YELLOW}Creating bootstrap inventory file: $BOOTSTRAP_INVENTORY${NC}"
    cp inventory/bootstrap-hosts.ini.example "$BOOTSTRAP_INVENTORY"
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
# Remove existing entry if present
sed -i.bak "/^$HOSTNAME /d" "$BOOTSTRAP_INVENTORY" 2>/dev/null || true
# Add new entry
echo "$INVENTORY_ENTRY" >> "$BOOTSTRAP_INVENTORY"

# Build ansible-playbook command
PLAYBOOK_CMD="ansible-playbook playbooks/bootstrap-host.yml -i $BOOTSTRAP_INVENTORY --limit $HOSTNAME"
PLAYBOOK_CMD="$PLAYBOOK_CMD -e bootstrap_ansible_user=$MANAGEMENT_USER"
PLAYBOOK_CMD="$PLAYBOOK_CMD -e bootstrap_ssh_public_key=\"$(cat "$SSH_PUBLIC_KEY")\""

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
    echo "Next steps:"
    echo "1. Add this host to inventory/hosts:"
    echo "   $HOSTNAME ansible_host=${IP_ADDRESS:-$HOSTNAME} ansible_user=$MANAGEMENT_USER"
    echo ""
    echo "2. Test connection:"
    echo "   ansible $HOSTNAME -m ping"
    echo ""
    echo "3. Apply system tweaks:"
    echo "   ansible-playbook playbooks/apply-system-tweaks.yml --limit $HOSTNAME"
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
