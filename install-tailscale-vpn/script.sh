#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
umask 077

: "${TAILSCALE_HOSTNAME:?TAILSCALE_HOSTNAME is required}"
: "${TAILSCALE_AUTH_KEY:?TAILSCALE_AUTH_KEY is required}"
TAILSCALE_EXIT_NODE="${TAILSCALE_EXIT_NODE:-false}"

echo "Tailscale installation starting…"
echo " - Configuration values hidden for security."

source /etc/os-release
codename="${VERSION_CODENAME}"

if [[ -z "$codename" ]]; then
  echo "Could not determine Debian codename. Aborting."
  exit 1
fi

sudo mkdir -p /usr/share/keyrings

curl -fsSL "https://pkgs.tailscale.com/stable/debian/${codename}.noarmor.gpg" \
  | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null

curl -fsSL "https://pkgs.tailscale.com/stable/debian/${codename}.tailscale-keyring.list" \
  | sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null

sudo apt-get update -y
sudo apt-get install -y tailscale

EXIT_FLAG=""
if [[ "$TAILSCALE_EXIT_NODE" == "true" ]]; then
  EXIT_FLAG="--advertise-exit-node"
fi

sudo tailscale up \
  --authkey="$TAILSCALE_AUTH_KEY" \
  --hostname="$TAILSCALE_HOSTNAME" \
  $EXIT_FLAG

echo "Tailscale installed successfully."
