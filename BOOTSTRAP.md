# Host Bootstrap Quick Reference

Quick reference guide for bootstrapping new hosts using the `bootstrap_linux_baseline.py` script. This script uses raw SSH connections (no Ansible required) to set up baseline users, SSH keys, and sudo access on remote hosts.

## Prerequisites

1. **Install Python dependencies**:
   ```bash
   cd baseline
   pip install -r requirements.txt
   ```

   Or install system-wide:
   ```bash
   pip3 install paramiko PyYAML
   ```

2. **Create a configuration file** (see `baseline.yml` for an example):
   - Define hosts to bootstrap
   - Define baseline users to create/configure
   - Specify SSH authentication method (key or password)

## Quick Start

```bash
cd baseline
./bootstrap_linux_baseline.py baseline.yml
```

The script will process all hosts defined in the configuration file and ensure all baseline users are configured on each host.

## Configuration File Format

The configuration file is a YAML file with two main sections:

### Hosts Section

Each host entry defines how to connect to the host:

```yaml
hosts:
  - name: server1
    hostname: 192.168.1.100
    ssh_user: admin              # User to connect as (must have sudo access)
    auth_method: password        # "key" or "password"
    password: "your-password"    # Required if auth_method: password
    # OR for key-based auth:
    # auth_method: key
    # ssh_key: ~/.ssh/id_rsa     # Optional, defaults to ~/.ssh/id_rsa
    # sudo_password: "different"  # Optional, defaults to SSH password
```

**Host Configuration Options:**
- `name`: Friendly name for the host (used in output)
- `hostname`: IP address or hostname to connect to
- `ssh_user`: Username for SSH connection (must have sudo privileges)
- `auth_method`: Either `"key"` or `"password"`
- `password`: SSH password (required if `auth_method: password`, optional if omitted will prompt)
- `ssh_key`: Path to SSH private key (defaults to `~/.ssh/id_rsa` if `auth_method: key`)
- `sudo_password`: Separate sudo password (optional, defaults to SSH password)

### Baseline Users Section

Each user entry defines a user to ensure exists on all hosts:

```yaml
baseline_users:
  - name: ansible
    uid: 2001                    # Optional: specific UID
    shell: /bin/bash             # Optional: default /bin/bash
    home: /home/ansible          # Optional: default /home/<name>
    groups: ["sudo"]             # Optional: list of groups to add user to
    create_if_missing: true      # Optional: default true
    
    authorized_keys:
      replace: true              # true = overwrite, false = append
      keys:
        - "ssh-ed25519 AAAAC3... your-public-key"
        - "ssh-rsa AAAA... another-key"
    
    sudo:
      nopasswd: true             # If true, creates passwordless sudo entry
```

**User Configuration Options:**
- `name`: Username (required)
- `uid`: Optional specific UID to assign
- `shell`: Login shell (default: `/bin/bash`)
- `home`: Home directory path (default: `/home/<name>`)
- `groups`: List of groups to add user to (e.g., `["sudo", "docker"]`)
- `create_if_missing`: If `false`, skip user creation if missing (default: `true`)
- `authorized_keys`: SSH key configuration
  - `replace`: `true` to overwrite `~/.ssh/authorized_keys`, `false` to append
  - `keys`: List of SSH public key strings
- `sudo`: Sudo configuration
  - `nopasswd`: If `true`, creates `/etc/sudoers.d/90-<name>-bootstrap` with `NOPASSWD:ALL`

## Common Scenarios

### Scenario 1: Bootstrap with Password Authentication

```yaml
hosts:
  - name: new-server
    hostname: 10.0.0.50
    ssh_user: ubuntu
    auth_method: password
    password: "initial-password"

baseline_users:
  - name: ansible
    groups: ["sudo"]
    authorized_keys:
      replace: true
      keys:
        - "ssh-ed25519 AAAAC3... your-key"
    sudo:
      nopasswd: true
```

Run:
```bash
./bootstrap_linux_baseline.py baseline.yml
```

### Scenario 2: Bootstrap with SSH Key Authentication

```yaml
hosts:
  - name: new-server
    hostname: 10.0.0.50
    ssh_user: admin
    auth_method: key
    ssh_key: ~/.ssh/id_ed25519

baseline_users:
  - name: ansible
    groups: ["sudo"]
    authorized_keys:
      replace: true
      keys:
        - "ssh-ed25519 AAAAC3... your-key"
    sudo:
      nopasswd: true
```

### Scenario 3: Multiple Hosts

The script processes all hosts in the configuration file sequentially:

```yaml
hosts:
  - name: server1
    hostname: 10.0.0.10
    ssh_user: admin
    auth_method: password
    password: "pass1"
  - name: server2
    hostname: 10.0.0.11
    ssh_user: admin
    auth_method: key
    ssh_key: ~/.ssh/id_ed25519

baseline_users:
  - name: ansible
    groups: ["sudo"]
    authorized_keys:
      replace: true
      keys:
        - "ssh-ed25519 AAAAC3... your-key"
    sudo:
      nopasswd: true
```

### Scenario 4: Append SSH Keys (Don't Replace)

To add keys without overwriting existing ones:

```yaml
baseline_users:
  - name: ansible
    authorized_keys:
      replace: false    # Append instead of replace
      keys:
        - "ssh-ed25519 AAAAC3... new-key"
```

### Scenario 5: Multiple Users

Configure multiple baseline users:

```yaml
baseline_users:
  - name: ansible
    groups: ["sudo"]
    authorized_keys:
      replace: true
      keys:
        - "ssh-ed25519 AAAAC3... key1"
    sudo:
      nopasswd: true
  
  - name: deploy
    groups: ["sudo", "docker"]
    authorized_keys:
      replace: true
      keys:
        - "ssh-ed25519 AAAAC3... key2"
    sudo:
      nopasswd: true
```

## What the Script Does

For each host in the configuration:

1. **Connects via SSH** using the specified authentication method
2. **For each baseline user**:
   - Checks if user exists, creates if missing (unless `create_if_missing: false`)
   - Updates user's shell, home directory, and groups if needed
   - Creates/updates `~/.ssh/authorized_keys`:
     - If `replace: true`: Overwrites the file with specified keys
     - If `replace: false`: Appends keys that don't already exist
   - Sets proper permissions on `.ssh` directory (700) and `authorized_keys` (600)
   - If `sudo.nopasswd: true`: Creates a sudoers drop-in file for passwordless sudo
     - Validates with `visudo -cf` before finalizing
     - Removes the file if validation fails

## After Bootstrap

1. **Add to main inventory** (`inventory/hosts`):
   ```ini
   [ubuntu_servers]
   server1.example.com ansible_host=192.168.1.100 ansible_user=ansible
   ```
   
   If your SSH private key is not in the default location, specify it:
   ```ini
   [ubuntu_servers]
   server1.example.com ansible_host=192.168.1.100 ansible_user=ansible ansible_ssh_private_key_file=~/.ssh/id_ed25519
   ```

2. **Test connection**:
   ```bash
   ansible server1.example.com -m ping
   ```
   
   Or test SSH manually:
   ```bash
   ssh ansible@server1.example.com
   ```

3. **Apply system tweaks** (if using Ansible):
   ```bash
   ansible-playbook playbooks/apply-system-tweaks.yml --limit server1.example.com
   ```

## Troubleshooting

### "ImportError: No module named 'paramiko'" or similar

Install the required dependencies:
```bash
cd baseline
pip install -r requirements.txt
```

Or install system-wide:
```bash
pip3 install paramiko PyYAML
```

### "Failed to connect" error

- Verify SSH service is running on the target host: `systemctl status ssh`
- Check firewall rules allow SSH (port 22)
- Verify hostname/IP is correct
- Test manual SSH connection first: `ssh user@hostname`
- For password auth: Ensure password is correct in config or be ready to enter it when prompted
- For key auth: Verify the SSH key path is correct and the key has proper permissions (600)

### "Permission denied" or sudo errors

- Ensure the `ssh_user` has sudo access on the target host
- If sudo requires a password, ensure `sudo_password` is set correctly (or matches SSH password)
- Check that the user is in the `sudo` group: `groups $USER`

### "visudo validation failed"

The script validates sudoers entries with `visudo -cf`. If validation fails:
- Check the error message for syntax issues
- The script will automatically remove the invalid sudoers file
- Verify the username doesn't conflict with existing sudoers rules

### Bootstrap succeeds but can't connect after

- Verify the host was added to main inventory with correct `ansible_user`
- **Most common issue**: The private key doesn't match the public key that was installed
  - Check which public key was installed during bootstrap (shown in output)
  - Ensure you're using the corresponding private key
  - Specify the key explicitly: `ansible_ssh_private_key_file=~/.ssh/id_ed25519` in inventory
- Test SSH manually: `ssh -i ~/.ssh/id_ed25519 ansible@hostname`
- Verify the key file exists and has correct permissions: `ls -la ~/.ssh/id_ed25519`

### User creation fails

- Check that the UID (if specified) is not already in use
- Verify groups exist on the target system (e.g., `sudo` group on Ubuntu/Debian)
- Check error messages in script output for specific issues

## Security Notes

- **Never commit passwords or private keys** to version control
- Consider using environment variables or a secrets manager for passwords
- The script uses `paramiko.AutoAddPolicy()` which automatically accepts host keys (convenient but less secure for production)
- Passwordless sudo (`nopasswd: true`) provides full root access - use with caution
- SSH keys are written with proper permissions (600 for `authorized_keys`, 700 for `.ssh` directory)

## Example Configuration File

See `baseline/baseline.yml` for a complete example with multiple hosts and users.
