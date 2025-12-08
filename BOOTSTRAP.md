# Host Bootstrap Quick Reference

Quick reference guide for bootstrapping new hosts.

## Quick Start

```bash
# Simplest method - will prompt for password if needed
./scripts/bootstrap-host.sh server1.example.com

# With specific user
./scripts/bootstrap-host.sh server1.example.com --user admin

# Using IP address
./scripts/bootstrap-host.sh 192.168.1.100 --ip
```

## Common Scenarios

### Scenario 1: Host with Password Authentication Only

```bash
# The script will automatically detect and prompt for password
./scripts/bootstrap-host.sh server1.example.com --user ubuntu
```

Or manually:
```bash
ansible-playbook playbooks/bootstrap-host.yml \
  -i inventory/bootstrap-hosts.ini \
  --ask-pass \
  --ask-become-pass
```

### Scenario 2: Host with SSH Key Already Configured

```bash
# Works automatically if your default SSH key is authorized
./scripts/bootstrap-host.sh server1.example.com
```

### Scenario 3: Host with Custom SSH Key

```bash
./scripts/bootstrap-host.sh server1.example.com \
  --ssh-key ~/.ssh/custom_key \
  --user admin
```

Or in inventory:
```ini
[bootstrap_hosts]
server1.example.com ansible_user=admin ansible_ssh_private_key_file=~/.ssh/custom_key
```

### Scenario 4: Multiple Hosts

```bash
# Bootstrap one at a time (recommended for first-time setup)
./scripts/bootstrap-host.sh server1.example.com
./scripts/bootstrap-host.sh server2.example.com

# Or bootstrap multiple at once (if they share same credentials)
ansible-playbook playbooks/bootstrap-host.yml \
  -i inventory/bootstrap-hosts.ini \
  --ask-pass \
  --ask-become-pass
```

## After Bootstrap

1. **Add to main inventory** (`inventory/hosts`):
   ```ini
   [ubuntu_servers]
   server1.example.com ansible_host=192.168.1.100 ansible_user=ansible
   ```

2. **Test connection**:
   ```bash
   ansible server1.example.com -m ping
   ```

3. **Apply system tweaks**:
   ```bash
   ansible-playbook playbooks/apply-system-tweaks.yml --limit server1.example.com
   ```

## Troubleshooting

### "Python not found" error
The bootstrap playbook automatically installs Python 3. If it fails, ensure:
- You have sudo/root access
- The host has internet connectivity for package installation

### "Permission denied" error
- Ensure the initial user has sudo access
- Use `--ask-become-pass` to provide sudo password
- Check that the user is in the `sudo` group

### SSH connection issues
- Verify SSH service is running: `systemctl status ssh`
- Check firewall rules allow SSH (port 22)
- Verify hostname/IP is correct
- Test manual SSH connection first: `ssh user@hostname`

### Bootstrap succeeds but can't connect after
- Verify the host was added to main inventory with correct `ansible_user`
- Check that the management user's SSH key is correct
- Test SSH manually: `ssh ansible@hostname`

## Advanced Options

### Custom Management User

```bash
./scripts/bootstrap-host.sh server1.example.com \
  --mgmt-user deploy
```

### Custom SSH Public Key

```bash
./scripts/bootstrap-host.sh server1.example.com \
  --pub-key ~/.ssh/custom_key.pub
```

### Disable Password Authentication (Security)

```bash
ansible-playbook playbooks/bootstrap-host.yml \
  -i inventory/bootstrap-hosts.ini \
  -e bootstrap_disable_password_auth=true \
  --ask-pass \
  --ask-become-pass
```

This will disable password authentication in SSH config after bootstrap completes, requiring key-based auth only.
