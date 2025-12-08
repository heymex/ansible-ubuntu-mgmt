# Ubuntu Linux Management with Ansible

This framework provides a structured approach to managing Ubuntu Linux systems using Ansible. It's designed to be simple, extensible, and suitable for both manual execution and automated scheduling.

## Features

- **Simple Host Management**: Add new hosts to the inventory and they're automatically managed
- **Schedulable Updates**: System update playbooks designed for cron scheduling
- **Extensible System Tweaks**: Easy-to-add configuration tweaks (passwordless sudo, SSH keys, etc.)
- **Organized Structure**: Clear separation of playbooks, roles, and configuration

## Directory Structure

```
.
├── ansible.cfg              # Ansible configuration
├── inventory/
│   ├── hosts               # Main host inventory file
│   └── bootstrap-hosts.ini.example  # Template for bootstrap inventory
├── playbooks/
│   ├── system-updates.yml  # System update playbook (schedulable)
│   ├── apply-system-tweaks.yml  # Apply system configuration tweaks
│   └── bootstrap-host.yml  # One-time host onboarding playbook
├── roles/
│   └── system_tweaks/      # Role for system configuration tweaks
│       ├── tasks/
│       │   ├── main.yml
│       │   ├── passwordless_sudo.yml
│       │   ├── ssh_keys.yml
│       │   └── additional_tweaks.yml
│       ├── defaults/
│       │   └── main.yml
│       └── README.md
├── group_vars/
│   ├── all.yml            # Variables for all hosts
│   └── production.yml     # Variables for production group
├── host_vars/             # Per-host variable overrides
└── scripts/
    ├── schedule-updates.sh  # Cron scheduling script
    └── bootstrap-host.sh   # Host bootstrap helper script
```

## Prerequisites

### Install Ansible Collections

This framework requires the `ansible.posix` collection for SSH key management. Install it:

```bash
ansible-galaxy collection install -r requirements.yml
```

Or install manually:
```bash
ansible-galaxy collection install ansible.posix
```

## Quick Start

### 1. Install Required Collections

```bash
ansible-galaxy collection install -r requirements.yml
```

### 2. Configure Inventory

Edit `inventory/hosts` and add your Ubuntu servers:

```ini
[ubuntu_servers]
server1.example.com ansible_host=192.168.1.100 ansible_user=ubuntu
server2.example.com ansible_host=192.168.1.101 ansible_user=ubuntu

[production]
server1.example.com
```

### 3. Configure SSH Access

Ensure you can SSH to your hosts without password prompts. You can either:

- Use SSH keys (recommended)
- Configure `ansible_ssh_pass` in inventory (less secure)

### 4. Test Connection

```bash
ansible all -m ping
```

### 5. Apply System Tweaks

```bash
ansible-playbook playbooks/apply-system-tweaks.yml
```

### 6. Run System Updates

```bash
ansible-playbook playbooks/system-updates.yml
```

## Bootstrapping New Hosts

When adding a new host that hasn't been configured for Ansible yet, you need to bootstrap it first. This is especially important when hosts have mixed authentication methods (SSH keys vs. password authentication).

### What Bootstrap Does

The bootstrap process uses raw SSH commands (no Ansible required) to:
1. Create a dedicated Ansible management user (default: `ansible`)
2. Install your SSH public key for key-based authentication
3. Configure passwordless sudo for the management user
4. Test the connection to ensure it works

Once bootstrap completes and the connection test succeeds, the host is ready to be added to the inventory and managed with Ansible.

> **Quick Reference**: See [BOOTSTRAP.md](BOOTSTRAP.md) for a quick reference guide with common scenarios and troubleshooting.

### Method 1: Using the Bootstrap Script (Recommended)

The easiest way to bootstrap a new host:

```bash
# Bootstrap with password authentication (will prompt)
./scripts/bootstrap-host.sh server1.example.com

# Bootstrap with specific user
./scripts/bootstrap-host.sh server1.example.com --user admin

# Bootstrap using IP address (auto-detected, or use --ip)
./scripts/bootstrap-host.sh 192.168.1.100

# Bootstrap with custom SSH key for initial connection
./scripts/bootstrap-host.sh server1.example.com --ssh-key ~/.ssh/custom_key

# Bootstrap with custom management user
./scripts/bootstrap-host.sh server1.example.com --mgmt-user deploy
```

The script will:
- Test initial SSH connection
- Use raw SSH commands to create the management user
- Install your SSH public key
- Configure passwordless sudo
- Test the connection as the management user
- Offer to add the host to the inventory automatically

### Method 2: Manual Bootstrap

If you prefer to bootstrap manually using SSH:

1. **SSH to the host** with an existing user that has sudo access:
   ```bash
   ssh user@new-server.example.com
   ```

2. **Create the ansible user**:
   ```bash
   sudo useradd -m -s /bin/bash ansible
   sudo usermod -aG sudo ansible
   ```

3. **Install your SSH public key**:
   ```bash
   sudo mkdir -p /home/ansible/.ssh
   sudo chmod 700 /home/ansible/.ssh
   echo "YOUR_PUBLIC_KEY_HERE" | sudo tee /home/ansible/.ssh/authorized_keys
   sudo chmod 600 /home/ansible/.ssh/authorized_keys
   sudo chown -R ansible:ansible /home/ansible/.ssh
   ```

4. **Configure passwordless sudo**:
   ```bash
   echo "ansible ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/ansible
   sudo chmod 440 /etc/sudoers.d/ansible
   sudo visudo -cf /etc/sudoers.d/ansible
   ```

5. **Test the connection**:
   ```bash
   ssh ansible@new-server.example.com
   ```

6. **Add to inventory** (`inventory/hosts`):
   ```ini
   [ubuntu_servers]
   new-server.example.com ansible_host=192.168.1.100 ansible_user=ansible
   ```

7. **Test with Ansible**:
   ```bash
   ansible new-server.example.com -m ping
   ```

### Bootstrap Options

The bootstrap script supports various options:

```bash
# Use a different management user
./scripts/bootstrap-host.sh server1.example.com --mgmt-user deploy

# Use a specific SSH public key
./scripts/bootstrap-host.sh server1.example.com --pub-key ~/.ssh/custom_key.pub

# Use a custom SSH key for initial connection
./scripts/bootstrap-host.sh server1.example.com --ssh-key ~/.ssh/initial_key
```

### Handling Mixed Authentication

The bootstrap script handles different initial authentication scenarios:

- **Password-only hosts**: Will prompt for password when needed
- **SSH key hosts**: Works automatically if your SSH key is already configured
- **Custom SSH keys**: Specify with `--ssh-key` flag for initial connection
- **Different users**: Specify with `--user` flag

After bootstrap, all hosts will use consistent key-based authentication with the management user.

## Adding Already-Configured Hosts

If a host is already configured for Ansible (has Python 3, SSH keys, and sudo access), you can add it directly to `inventory/hosts`:

```ini
[ubuntu_servers]
existing-server.example.com ansible_host=192.168.1.100 ansible_user=ubuntu
new-server.example.com ansible_host=192.168.1.101 ansible_user=ubuntu
```

The new host will automatically:
- Be managed by all playbooks
- Receive system tweaks when you run `apply-system-tweaks.yml`
- Be included in system updates when you run `system-updates.yml`

## System Updates

The `system-updates.yml` playbook handles:
- Updating apt cache
- Upgrading all packages
- Automatic cleanup (autoremove, autoclean)
- Optional automatic reboots

### Manual Execution

```bash
# Update all servers
ansible-playbook playbooks/system-updates.yml

# Update only production servers
ansible-playbook playbooks/system-updates.yml --limit production

# Check for updates without installing
ansible-playbook playbooks/system-updates.yml -e check_only=true

# Enable automatic reboots
ansible-playbook playbooks/system-updates.yml -e auto_reboot=true
```

### Scheduling with Cron

See `scripts/schedule-updates.sh` for an example cron setup, or add directly to crontab:

```bash
# Update all servers daily at 2 AM
0 2 * * * cd /path/to/ansible-ubuntu-mgmt && ansible-playbook playbooks/system-updates.yml >> /var/log/ansible-updates.log 2>&1

# Update production servers weekly on Sunday at 3 AM
0 3 * * 0 cd /path/to/ansible-ubuntu-mgmt && ansible-playbook playbooks/system-updates.yml --limit production >> /var/log/ansible-updates.log 2>&1
```

## System Tweaks

The `system_tweaks` role applies various system configurations. Current tweaks include:

### Passwordless Sudo

Configure passwordless sudo for users:

```yaml
# In group_vars/all.yml or host_vars/server.yml
system_tweaks_passwordless_sudo_users:
  - ubuntu
  - admin
  - deploy
```

### SSH Keys

Import SSH public keys for users:

```yaml
# In group_vars/all.yml
system_tweaks_ssh_keys:
  - user: ubuntu
    key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI..."
    comment: "Admin SSH Key"
  - user: deploy
    key: "{{ lookup('file', '~/.ssh/id_ed25519.pub') }}"
    comment: "Deploy Key"
```

### Adding New Tweaks

To add a new system tweak:

1. Create a new task file in `roles/system_tweaks/tasks/` (e.g., `my_tweak.yml`)
2. Include it in `roles/system_tweaks/tasks/main.yml`
3. Add default variables to `roles/system_tweaks/defaults/main.yml`
4. Document it in `roles/system_tweaks/README.md`

See `roles/system_tweaks/README.md` for detailed examples.

## Configuration

### Ansible Configuration

The `ansible.cfg` file is pre-configured with:
- SSH connection optimizations (ControlPersist, pipelining)
- Sudo privilege escalation
- Performance settings (forks, fact gathering)
- Logging

### Variables

Variables can be set at multiple levels (in order of precedence):
1. `host_vars/<hostname>.yml` - Per-host overrides
2. `group_vars/<group>.yml` - Per-group overrides
3. `group_vars/all.yml` - Global defaults
4. Role defaults in `roles/system_tweaks/defaults/main.yml`

### Example: Production-Specific Configuration

Create `group_vars/production.yml`:

```yaml
system_tweaks_passwordless_sudo_users:
  - ubuntu
  - admin
  - deploy

system_tweaks_ssh_keys:
  - user: ubuntu
    key: "{{ lookup('file', '~/.ssh/production_key.pub') }}"
    comment: "Production Admin Key"
```

## Best Practices

1. **Test First**: Use `--check` mode to see what would change:
   ```bash
   ansible-playbook playbooks/system-updates.yml --check
   ```

2. **Limit Scope**: Use `--limit` to test on a subset of hosts:
   ```bash
   ansible-playbook playbooks/apply-system-tweaks.yml --limit staging
   ```

3. **Use Tags**: Run specific parts of playbooks:
   ```bash
   ansible-playbook playbooks/apply-system-tweaks.yml --tags ssh_keys
   ```

4. **Version Control**: Commit your inventory and variable files to track changes

5. **Backup**: Consider backing up critical configuration files before applying changes

## Troubleshooting

### Connection Issues

```bash
# Test SSH connection
ansible all -m ping

# Test with verbose output
ansible all -m ping -vvv

# Test specific host
ansible server1.example.com -m ping
```

### Permission Issues

Ensure the ansible user has sudo access:
```bash
ansible all -m shell -a "sudo -l" --become
```

### Python Issues

Ubuntu 18.04+ should have Python 3 by default. If needed, specify:
```ini
[ubuntu_servers:vars]
ansible_python_interpreter=/usr/bin/python3
```

## Requirements

- Ansible 2.9 or later
- Python 3 on control node
- SSH access to target hosts
- Sudo access on target hosts (or ability to become root)

## Additional Resources

- [Ansible Documentation](https://docs.ansible.com/)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)
- [Ubuntu Server Guide](https://ubuntu.com/server/docs)
