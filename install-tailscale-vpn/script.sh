#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

: "${TAILSCALE_HOSTNAME:?TAILSCALE_HOSTNAME is required}"
: "${TAILSCALE_AUTH_KEY:?TAILSCALE_AUTH_KEY is required}"
TAILSCALE_EXIT_NODE="${TAILSCALE_EXIT_NODE:-false}"

echo "Tailscale installation starting…"

source /etc/os-release
codename="${VERSION_CODENAME}"

# 1) Ensure keyrings dir is accessible to _apt (REQUIRED on Debian 13)
sudo install -d -m 0755 /usr/share/keyrings
sudo chmod 0755 /usr/share/keyrings

# 2) Remove any stale/bad keyring that might have wrong perms/format
sudo rm -f /usr/share/keyrings/tailscale-archive-keyring.gpg

# 3) Use Tailscale's documented 'noarmor' key as-is (no gpg --dearmor)
curl -fsSL "https://pkgs.tailscale.com/stable/debian/${codename}.noarmor.gpg" \
  | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null

# 4) Force world-readable keyring (sqv/_apt must read it)
sudo chmod 0644 /usr/share/keyrings/tailscale-archive-keyring.gpg

# 5) Repo list (official)
curl -fsSL "https://pkgs.tailscale.com/stable/debian/${codename}.tailscale-keyring.list" \
  | sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null

sudo ls -ld /usr/share/keyrings
sudo ls -l /usr/share/keyrings/tailscale-archive-keyring.gpg
sudo stat -c '%A %U:%G %n' /usr/share/keyrings /usr/share/keyrings/tailscale-archive-keyring.gpg


# 6) Update & install
sudo apt-get update -y
sudo apt-get install -y tailscale

# 7) Bring it up (avoid logging secrets)
args=(--authkey="$TAILSCALE_AUTH_KEY" --hostname="$TAILSCALE_HOSTNAME")
if [[ "$TAILSCALE_EXIT_NODE" == "true" ]]; then
  args+=(--advertise-exit-node)
fi

sudo tailscale up "${args[@]}"
sudo tailscale status
