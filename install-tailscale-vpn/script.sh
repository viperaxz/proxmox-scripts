#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
umask 077

: "${TAILSCALE_HOSTNAME:?TAILSCALE_HOSTNAME is required}"
: "${TAILSCALE_AUTH_KEY:?TAILSCALE_AUTH_KEY is required}"
TAILSCALE_EXIT_NODE="${TAILSCALE_EXIT_NODE:-false}"

echo "Tailscale installation starting…"
echo " - Sensitive configuration values hidden for security."

# Debian 12/13 + Proxmox 8/9 compatible Tailscale repo setup
source /etc/os-release
codename="${VERSION_CODENAME}"

sudo apt-get update -y
sudo apt-get install -y gpg sq

# MUST fix directory permissions (due to umask 077)
sudo install -d -m 0755 /usr/share/keyrings

curl -fsSL "https://pkgs.tailscale.com/stable/debian/${codename}.noarmor.gpg" \
  | sudo gpg --dearmor --yes -o /usr/share/keyrings/tailscale-archive-keyring.gpg

sudo chmod 0644 /usr/share/keyrings/tailscale-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] \
https://pkgs.tailscale.com/stable/debian ${codename} main" \
  | sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null

sudo apt-get update -y
sudo apt-get install -y tailscale

