# Proxmox Scripts (GitHub Actions + SSH)

A small collection of **GitHub Actions workflows** and **Bash scripts** that automate common tasks on a Proxmox node:

- Create/update a Proxmox API user + role + API token
- Build an Ubuntu Cloud-Image VM template
- Install and configure Tailscale

All workflows are **manual** (`workflow_dispatch`) and follow the same pattern:

1. GitHub Actions runner starts
2. Repo is checked out
3. A script is copied to the Proxmox host via SCP
4. The script is executed over SSH

---

## Repository Layout

    proxmox-scripts/
      add-user-api-token/script.sh
      create-vm-template/script.sh
      install-tailscale-vpn/script.sh
      .github/workflows/add-user-api-token.yml
      .github/workflows/create-vm-template.yml
      .github/workflows/install-tails-vpn.yml
      README.md

---

## Requirements

### On the Proxmox Server

- A Proxmox VE node reachable via SSH
- CLI tools:
  - `pveum` (users / roles / tokens)
  - `qm` and `pvesm` (VMs / storage)
- `apt-get` (Debian-based environment)
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
- Proxmox **API token secrets** are typically shown only at creation time. Avoid printing them in CI logs.

If you need stricter secrecy, modify scripts so newly-created secrets are written to root-only files on the server (and not printed).

---

## Step 1 — Generate an SSH Key Pair (for GitHub Actions)

Generate a dedicated key pair on your local machine.

Recommended (Ed25519):

```bash
ssh-keygen -t ed25519 -a 64 -C "github-actions-proxmox" -f ~/.ssh/github_actions_proxmox
```

This creates:
- Private key: `~/.ssh/github_actions_proxmox` (keep secret)
- Public key: `~/.ssh/github_actions_proxmox.pub` (safe to share)

---

## Step 2 — Install the Public Key on the Proxmox Host

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

## Step 3 — Configure GitHub Secrets and Variables

### 3.1 Secrets

GitHub → Settings → Secrets and variables → Actions → Secrets

Add:

- `SSH_PRIVATE_KEY` (contents of the private key file):

```bash
cat ~/.ssh/github_actions_proxmox
```

If using Tailscale workflow:
- `TAILSCALE_AUTH_KEY`

### 3.2 Variables

GitHub → Settings → Secrets and variables → Actions → Variables

Add:

- `EXTERNAL_IP_OR_DOMAIN` = e.g. `proxmox.example.com`
- `USERNAME` = e.g. `root` (or another sudo-enabled Linux user)
- `SSH_PORT` = e.g. `22`
- `TAILSCALE_HOSTNAME` = e.g. `proxmox-node-1`
- `TAILSCALE_EXIT_NODE` = `true` or `false`

---

# Workflows and Scripts

## 1) Add Proxmox User + Role + API Token

Workflow: `.github/workflows/add-user-api-token.yml`  
Script: `add-user-api-token/script.sh`

### What it does

- Ensures a Proxmox user exists (example: `terraform-deploy@pve`)
- Ensures a role exists with required privileges (example role: `TerraformDeploy`)
- Applies an ACL mapping the user to the role at `/`
- Ensures an API token exists (example token: `token1`)
  - if `overwrite_token = "true"` → deletes and recreates the token
  - else → keeps it if it already exists

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

- Detects storages from `pvesm status` and selects one by `STORAGE_INDEX`
- Downloads or reuses an Ubuntu cloud image
- Customizes the image (CPU hotplug, QEMU agent, machine-id reset, DNS)
- Creates a VM and converts it into a template (`qm template`)

### Run it

GitHub → Actions → **Create VM Template** → Run workflow  
Optional inputs:
- `UBUNTU_VERSION` (default `24.04`)
- `VM_TMPL_ID` (default `9000`)
- `VM_TMPL_NAME` (default `ubuntu-2404`)
- `STORAGE_INDEX` (0-based index of storage from `pvesm status`)

Tip: SSH to Proxmox and run `pvesm status` to confirm which index matches the storage you want.

---

## 3) Install Tailscale on Proxmox

Workflow: `.github/workflows/install-tails-vpn.yml`  
Script: `install-tailscale-vpn/script.sh`

### What it does

- Installs Tailscale via the official installer
- Joins your tailnet using `TAILSCALE_AUTH_KEY`
- Sets hostname with `TAILSCALE_HOSTNAME`
- If `TAILSCALE_EXIT_NODE=true`, advertises exit-node

### Run it

GitHub → Actions → **Install Tailscale on Server** → Run workflow

Make sure you set:
- Secret: `TAILSCALE_AUTH_KEY`
- Variables: `TAILSCALE_HOSTNAME`, `TAILSCALE_EXIT_NODE`

---

## Troubleshooting

### SSH connection fails

- Check routing/firewall/NAT to `<PROXMOX_HOST>:<SSH_PORT>`
- Test locally:

```bash
ssh -i ~/.ssh/github_actions_proxmox -p <SSH_PORT> <USERNAME>@<PROXMOX_HOST>
```

- Verify the public key is in `~/.ssh/authorized_keys` for that Linux user

### Sudo / permission issues

If using a non-root user, ensure it can run Proxmox commands and `sudo` works non-interactively (no password prompt).

### VM template errors

- Confirm selected storage supports VM disks
- Ensure dependencies install successfully
- Confirm virtualization support is enabled on the host

---
