# System Tweaks Role

This role applies various system configuration tweaks to Ubuntu systems.

## Current Tweaks

### Passwordless Sudo
Configures passwordless sudo for specified users.

**Variables:**
- `system_tweaks_passwordless_sudo_enabled`: Enable/disable (default: `true`)
- `system_tweaks_passwordless_sudo_users`: List of usernames (default: `['ubuntu']`)

### SSH Keys
Imports SSH public keys for specified users.

**Variables:**
- `system_tweaks_ssh_keys_enabled`: Enable/disable (default: `true`)
- `system_tweaks_ssh_keys`: List of key configurations (ED25519 recommended):
  ```yaml
  system_tweaks_ssh_keys:
    - user: ubuntu
      key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI..."
      comment: "Admin SSH Key"
    - user: deploy
      key: "{{ lookup('file', '~/.ssh/id_ed25519.pub') }}"
      comment: "Deploy Key"
  ```

## Adding New Tweaks

To add a new system tweak:

1. **Create a new task file** in `tasks/` (e.g., `tasks/my_new_tweak.yml`)

2. **Add the task file** to `tasks/main.yml`:
   ```yaml
   - name: Include my new tweak
     ansible.builtin.include_tasks: my_new_tweak.yml
     tags:
       - my_new_tweak
       - system_tweaks
   ```

3. **Add default variables** to `defaults/main.yml` if needed

4. **Document the tweak** in this README

## Example: Adding a New Tweak

Let's say you want to add a tweak to configure automatic security updates:

1. Create `tasks/auto_security_updates.yml`:
   ```yaml
   - name: Install unattended-upgrades
     ansible.builtin.apt:
       name: unattended-upgrades
       state: present
   
   - name: Configure automatic security updates
     ansible.builtin.copy:
       dest: /etc/apt/apt.conf.d/50unattended-upgrades
       content: |
         Unattended-Upgrade::Allowed-Origins {
             "${distro_id}:${distro_codename}-security";
         };
       when: system_tweaks_auto_security_updates_enabled | default(false) | bool
   ```

2. Add to `tasks/main.yml`:
   ```yaml
   - name: Include auto security updates
     ansible.builtin.include_tasks: auto_security_updates.yml
     tags:
       - auto_security_updates
       - system_tweaks
   ```

3. Add to `defaults/main.yml`:
   ```yaml
   system_tweaks_auto_security_updates_enabled: false
   ```

4. Use in `group_vars/all.yml` or `host_vars/`:
   ```yaml
   system_tweaks_auto_security_updates_enabled: true
   ```
