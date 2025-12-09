#!/usr/bin/env python3
import sys
import os
import yaml
import paramiko
import getpass

def load_config(path):
    with open(path, "r") as f:
        return yaml.safe_load(f)

def get_ssh_client(host_cfg):
    hostname = host_cfg["hostname"]
    username = host_cfg["ssh_user"]
    auth_method = host_cfg.get("auth_method", "key")

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    password = None

    if auth_method == "key":
        key_path = os.path.expanduser(host_cfg.get("ssh_key", "~/.ssh/id_rsa"))
        pkey = paramiko.RSAKey.from_private_key_file(key_path)
        client.connect(hostname, username=username, pkey=pkey, timeout=15)
    elif auth_method == "password":
        password = host_cfg.get("password")
        if password is None:
            password = getpass.getpass(f"SSH password for {username}@{hostname}: ")
        client.connect(hostname, username=username, password=password, timeout=15)
    else:
        raise ValueError(f"Unknown auth_method {auth_method} for host {hostname}")

    # Determine sudo password:
    #   - if sudo_password provided, use that
    #   - else reuse SSH password
    sudo_password = host_cfg.get("sudo_password", password)

    return client, sudo_password

def run(client, cmd, sudo=False, sudo_password=None):
    """
    Run a command. If sudo=True:
      - if sudo_password is provided: use 'sudo -S -p ""' and feed password
      - otherwise, assume passwordless sudo or root and just prefix sudo
    """
    if sudo:
        if sudo_password:
            cmd = f"sudo -S -p '' {cmd}"
        else:
            if not cmd.startswith("sudo "):
                cmd = "sudo " + cmd

    stdin, stdout, stderr = client.exec_command(cmd)

    if sudo and sudo_password:
        # Feed sudo the password on stdin
        stdin.write(sudo_password + "\n")
        stdin.flush()

    exit_status = stdout.channel.recv_exit_status()
    out = stdout.read().decode()
    err = stderr.read().decode()
    return exit_status, out, err

def ensure_user(client, sudo_password, user):
    name = user["name"]
    shell = user.get("shell", "/bin/bash")
    home = user.get("home", f"/home/{name}")
    uid = user.get("uid")
    groups = user.get("groups", [])
    create_if_missing = user.get("create_if_missing", True)

    status, _, _ = run(client, f"id -u {name}", sudo=True, sudo_password=sudo_password)
    if status != 0:
        if not create_if_missing:
            print(f"  - User {name} missing, but create_if_missing is false. Skipping create.")
            return
        print(f"  - Creating user {name}")
        cmd = f"useradd -m -d {home} -s {shell}"
        if uid is not None:
            cmd += f" -u {uid}"
        if groups:
            cmd += f" -G {','.join(groups)}"
        cmd += f" {name}"
        status, out, err = run(client, cmd, sudo=True, sudo_password=sudo_password)
        if status != 0:
            print(f"    ! Failed to create user {name}: {err.strip()}")
        else:
            print(f"    + User {name} created")
    else:
        print(f"  - User {name} already exists")
        # Best-effort normalize shell/home/groups
        run(client, f"usermod -d {home} -s {shell} {name}",
            sudo=True, sudo_password=sudo_password)
        if groups:
            run(client, f"usermod -a -G {','.join(groups)} {name}",
                sudo=True, sudo_password=sudo_password)

def ensure_authorized_keys(client, sudo_password, user):
    name = user["name"]
    ak = user.get("authorized_keys")
    if not ak:
        return

    keys = ak.get("keys", [])
    if not keys:
        return

    replace = ak.get("replace", True)
    home = user.get("home", f"/home/{name}")
    ssh_dir = f"{home}/.ssh"
    auth_file = f"{ssh_dir}/authorized_keys"

    print(f"  - Ensuring authorized_keys for {name}")

    run(client, f"mkdir -p {ssh_dir}", sudo=True, sudo_password=sudo_password)
    run(client, f"chown {name}:{name} {ssh_dir}", sudo=True, sudo_password=sudo_password)
    run(client, f"chmod 700 {ssh_dir}", sudo=True, sudo_password=sudo_password)

    key_block = "\n".join(keys) + "\n"

    if replace:
        cmd = f"bash -c 'cat > {auth_file}'"
        stdin, stdout, stderr = client.exec_command(f"sudo -S -p '' {cmd}")
        if sudo_password:
            stdin.write(sudo_password + "\n")
            stdin.flush()
        stdin.write(key_block)
        stdin.channel.shutdown_write()
        stdout.channel.recv_exit_status()
    else:
        for k in keys:
            escaped_k = k.replace("'", "'\"'\"'")
            check_cmd = f"grep -qx '{escaped_k}' {auth_file} || echo '{escaped_k}' >> {auth_file}"
            run(client, f"bash -c \"{check_cmd}\"", sudo=True, sudo_password=sudo_password)

    run(client, f"chown {name}:{name} {auth_file}", sudo=True, sudo_password=sudo_password)
    run(client, f"chmod 600 {auth_file}", sudo=True, sudo_password=sudo_password)
    print(f"    + authorized_keys updated")

def ensure_sudo(client, sudo_password, user):
    name = user["name"]
    sudo_cfg = user.get("sudo")
    if not sudo_cfg:
        return

    nopasswd = sudo_cfg.get("nopasswd", False)
    if not nopasswd:
        return

    print(f"  - Ensuring passwordless sudo for {name}")
    sudo_file = f"/etc/sudoers.d/90-{name}-bootstrap"
    line = f"{name} ALL=(ALL) NOPASSWD:ALL\n"

    cmd = f"bash -c 'echo \"{line.rstrip()}\" > {sudo_file}'"
    status, out, err = run(client, cmd, sudo=True, sudo_password=sudo_password)
    if status != 0:
        print(f"    ! Failed to write sudoers file: {err.strip()}")
        return

    run(client, f"chmod 440 {sudo_file}", sudo=True, sudo_password=sudo_password)

    status, out, err = run(client, f"visudo -cf {sudo_file}", sudo=True, sudo_password=sudo_password)
    if status != 0:
        print(f"    ! visudo validation failed, removing {sudo_file}: {err.strip()}")
        run(client, f"rm -f {sudo_file}", sudo=True, sudo_password=sudo_password)
    else:
        print(f"    + Sudoers entry valid and in place")

def process_host(host_cfg, baseline_users):
    print(f"=== {host_cfg['name']} ({host_cfg['hostname']}) ===")
    try:
        client, sudo_password = get_ssh_client(host_cfg)
    except Exception as e:
        print(f"!! Failed to connect: {e}")
        return

    try:
        for user in baseline_users:
            print(f"- Handling user {user['name']}")
            ensure_user(client, sudo_password, user)
            ensure_authorized_keys(client, sudo_password, user)
            ensure_sudo(client, sudo_password, user)
    except Exception as e:
        print(f"!! Error processing users: {e}")
    finally:
        client.close()

def main():
    if len(sys.argv) < 2:
        print("Usage: bootstrap_linux_baseline.py <config.yml>")
        sys.exit(1)

    config_path = sys.argv[1]
    config = load_config(config_path)

    hosts = config.get("hosts", [])
    baseline_users = config.get("baseline_users", [])

    if not hosts:
        print("No hosts configured")
        sys.exit(1)

    if not baseline_users:
        print("No baseline_users configured")
        sys.exit(1)

    for host_cfg in hosts:
        process_host(host_cfg, baseline_users)

if __name__ == "__main__":
    main()
