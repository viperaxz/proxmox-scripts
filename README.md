# Proxmox Scripts (GitHub Actions + SSH)

A small collection of **GitHub Actions workflows** + **Bash scripts** to automate common tasks on a Proxmox node:

- Create/update a Proxmox **user + role + API token**
- Build an Ubuntu **cloud-image VM template**
- Install and configure **Tailscale** on the host

All workflows are **manual** (`workflow_dispatch`) and follow the same pattern:

1. GitHub Actions runner starts
2. Repo is checked out
3. A script is copied to the Proxmox host via SCP
4. The script is executed over SSH

---

## Repository Layout

```
proxmox-scripts/
  add-user-api-token/script.sh
  create-vm-template/script.sh
  install-tailscale-vpn/script.sh
  .github/workflows/add-user-api-token.yml
  .github/workflows/create-vm-template.yml
  .github/workflows/install-tails-vpn.yml
  README.md
```

---

## Requirements

### On the Proxmox Host

- A Proxmox VE node reachable via SSH
- CLI tools:
  - `pveum` (users / roles / tokens)
  - `qm` and `pvesm` (VMs / storage)
- Debian-based environment with `apt-get`
- A Linux user that can run Proxmox commands (commonly `root`, or a sudo-enabled user)

### In the GitHub Repository

Configure **Actions Secrets** and **Actions Variables**.

**Secrets**
- `SSH_PRIVATE_KEY` – private key used by GitHub Actions to connect to Proxmox
- `TAILSCALE_AUTH_KEY` – Tailscale auth key (only for the Tailscale workflow)

**Variables**
- `EXTERNAL_IP_OR_DOMAIN` – public IP or DNS of the Proxmox host
- `USERNAME` – SSH username (Linux user on the Proxmox host)
- `SSH_PORT` – SSH port (usually 22)
- `TAILSCALE_HOSTNAME` – hostname to register in Tailscale
- `TAILSCALE_EXIT_NODE` – `true` or `false`

Tip: you can store these at repo-level or inside a GitHub **Environment** (useful for dev/prod).

---

## Security Notes (public repo friendly)

- Never commit private keys into the repository.
- Store sensitive values only in **GitHub Secrets**.
- Anything printed by scripts can end up in **Actions logs**; treat logs as sensitive.
- Proxmox **API token secrets** are typically shown only at creation time.

This repo is set up to avoid leaking the API token secret into GitHub Actions logs:
- `add-user-api-token/script.sh` writes the one-time token secret output to a **root-only file** on the host (default under `/root/proxmox-api-tokens/`) rather than printing it.

---

# Step 1 — Generate an SSH Key Pair (for GitHub Actions)

Generate a dedicated key pair on your local machine.

Recommended (Ed25519):

```bash
ssh-keygen -t ed25519 -a 64 -C "github-actions-proxmox" -f ~/.ssh/github_actions_proxmox
```

This creates:
- Private key: `~/.ssh/github_actions_proxmox` (keep secret)
- Public key: `~/.ssh/github_actions_proxmox.pub` (safe to share)

---

# Step 2 — Install the Public Key on the Proxmox Host

Install the public key for the Linux user you will SSH as.

Using `ssh-copy-id`:

```bash
ssh-copy-id -i ~/.ssh/github_actions_proxmox.pub -p 22 <USERNAME>@<PROXMOX_HOST>
```

Manual method:

1) Show the public key locally:

```bash
cat ~/.ssh/github_actions_proxmox.pub
```

2) SSH into the Proxmox host:

```bash
ssh -p 22 <USERNAME>@<PROXMOX_HOST>
```

3) On the server:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
nano ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

Paste the public key as a single line into `authorized_keys`.

Test it:

```bash
ssh -i ~/.ssh/github_actions_proxmox -p 22 <USERNAME>@<PROXMOX_HOST>
```

---

# Step 3 — Configure GitHub Secrets and Variables

### 3.1 Secrets

GitHub → Settings → Secrets and variables → Actions → Secrets

Add:

- `SSH_PRIVATE_KEY` (contents of the private key file):

```bash
cat ~/.ssh/github_actions_proxmox
```

If using the Tailscale workflow:
- `TAILSCALE_AUTH_KEY`

### 3.2 Variables

GitHub → Settings → Secrets and variables → Actions → Variables

Add:

- `EXTERNAL_IP_OR_DOMAIN` = e.g. `proxmox.example.com`
- `USERNAME` = e.g. `root` (or another sudo-enabled Linux user)
- `SSH_PORT` = e.g. `22`
- `TAILSCALE_HOSTNAME` = e.g. `proxmox-node-1`
- `TAILSCALE_EXIT_NODE` = `true` or `false`

Optional hardening (recommended):
- Add a variable like `SSH_HOST_FINGERPRINT` and set it in the workflows (the lines are already present but commented out).

---

# Workflows and Scripts

## 1) Add Proxmox User + Role + API Token

Workflow: `.github/workflows/add-user-api-token.yml`  
Script: `add-user-api-token/script.sh`

### What it does

- Ensures a Proxmox user exists (default: `terraform-deploy@pve`)
- Ensures a role exists with **exact required privileges** (default role: `TerraformDeploy`)
  - The script enforces the same privilege list each run to avoid privilege creep.
- Applies an ACL mapping the user to the role on `ACL_PATH` (default `/`)
- Ensures an API token exists (default token id: `token1`)
  - If `overwrite_token = "true"` → deletes and recreates the token
  - Else → keeps it if it already exists
- When the token is created, the token secret output is saved to a root-only file:
  - Default: `/root/proxmox-api-tokens/<userid>__<tokenid>.secret`

### Useful environment variables

You can override these by exporting them before running the script:

- `ROLE_ID` (default `TerraformDeploy`)
- `USER_ID` (default `terraform-deploy@pve`)
- `TOKEN_ID` (default `token1`)
- `ACL_PATH` (default `/`) — strongly recommended to scope to `/pool/<pool>` or `/vms/<id>`
- `PRIVSEP` (default `1`) — token privilege separation
- `TOKEN_DIR` (default `/root/proxmox-api-tokens`)
- `OVERWRITE_TOKEN` (`true/false`)

### Run it

GitHub → Actions → **Add User API Token** → Run workflow  
Optional input:
- `overwrite_token`: `"true"` or `"false"` (default `"false"`)

Note: If you recreate the token, anything using the old token will stop working until updated.

---

## 2) Create Ubuntu VM Template (Cloud Image)

Workflow: `.github/workflows/create-vm-template.yml`  
Script: `create-vm-template/script.sh`

### What it does

- Downloads (or reuses) an Ubuntu cloud image and verifies it with SHA256SUMS
- Customizes the image:
  - CPU hotplug udev rule
  - Installs `qemu-guest-agent`
  - Resets `/etc/machine-id` (good for clones/templates)
- Creates a VM and converts it into a template (`qm template`)
- Imports the disk into the selected Proxmox storage and adds a Cloud-Init drive

### Important change: storage selection is now by name (required)

The script **requires**:

- `STORAGE_NAME` (example: `local-lvm`, `ceph-vm`, `zfs-ssd`)

It will refuse to run without it (no fallback to `STORAGE_INDEX` anymore).

To list storages that support VM images:

```bash
pvesm status --content images
```

### Inputs

GitHub workflow inputs:

- `UBUNTU_VERSION` (default `24.04`)
- `VM_TMPL_ID` (default `9000`)
- `VM_TMPL_NAME` (default `ubuntu-2404`)
- `STORAGE_NAME` (**required**)

---

## 3) Install Tailscale on Proxmox Host

Workflow: `.github/workflows/install-tails-vpn.yml`  
Script: `install-tailscale-vpn/script.sh`

### What it does

- Enables forwarding (needed for subnet routes / exit node; harmless otherwise)
- Installs Tailscale using the official Debian repository for the host codename
  - Note: Proxmox 9 is based on Debian **trixie**, and the script uses `/etc/os-release` to detect the codename.
- Joins your tailnet using `TAILSCALE_AUTH_KEY`
- Sets hostname with `TAILSCALE_HOSTNAME`
- If `TAILSCALE_EXIT_NODE=true`, advertises as an exit node
- If the workflow input `reset=true`, forces re-auth (`--reset`)

### Run it

GitHub → Actions → **Install Tailscale on Server** → Run workflow  
Optional input:
- `reset`: `"true"` or `"false"` (default `"false"`)

---

# Troubleshooting

## SSH connection fails

- Check routing/firewall/NAT to `<PROXMOX_HOST>:<SSH_PORT>`
- Test locally:

```bash
ssh -i ~/.ssh/github_actions_proxmox -p <SSH_PORT> <USERNAME>@<PROXMOX_HOST>
```

- Verify the public key exists in `~/.ssh/authorized_keys` for that Linux user
- Consider adding host key pinning (`fingerprint:`) to the Actions steps

## Sudo / permission issues

If using a non-root user, ensure it can run Proxmox commands and that `sudo` works non-interactively (no password prompt).

## VM template errors

- Confirm the selected `STORAGE_NAME` supports VM images:
  - `pvesm status --content images`
- Ensure dependencies install successfully (the script installs `libguestfs-tools` if needed)
- Confirm virtualization support is enabled on the host