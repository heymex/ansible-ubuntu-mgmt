# Host Bootstrap Quick Reference

Quick reference guide for bootstrapping new hosts using raw SSH commands (no Ansible required).

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

The script will prompt for the password when needed.

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

### Scenario 4: Multiple Hosts

```bash
# Bootstrap one at a time (recommended)
./scripts/bootstrap-host.sh server1.example.com
./scripts/bootstrap-host.sh server2.example.com
```

## After Bootstrap

1. **Add to main inventory** (`inventory/hosts`):
   ```ini
   [ubuntu_servers]
   server1.example.com ansible_host=192.168.1.100 ansible_user=ansible
   ```
   
   **Important**: If your SSH private key is not in the default location (`~/.ssh/id_ed25519`), or if you used a custom key during bootstrap, specify it:
   ```ini
   [ubuntu_servers]
   server1.example.com ansible_host=192.168.1.100 ansible_user=ansible ansible_ssh_private_key_file=~/.ssh/id_ed25519
   ```
   
   The bootstrap script will automatically add the host and test the connection if you answer 'Y' to the prompt.

2. **Test connection**:
   ```bash
   ansible server1.example.com -m ping
   ```
   
   If authentication fails:
   - Verify the private key matches the public key installed during bootstrap
   - Test SSH manually: `ssh -i ~/.ssh/id_ed25519 ansible@server1.example.com`
   - Check that the key is loaded in your SSH agent: `ssh-add -l`

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
- **Most common issue**: The private key doesn't match the public key that was installed
  - Check which public key was installed during bootstrap (shown in output)
  - Ensure you're using the corresponding private key
  - Specify the key explicitly: `ansible_ssh_private_key_file=~/.ssh/id_ed25519` in inventory
- Test SSH manually: `ssh -i ~/.ssh/id_ed25519 ansible@hostname`
- Check SSH agent has the key: `ssh-add -l` (if using SSH agent)
- Verify the key file exists and has correct permissions: `ls -la ~/.ssh/id_ed25519`

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
