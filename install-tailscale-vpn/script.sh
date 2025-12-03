#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
umask 077

: "${TAILSCALE_HOSTNAME:?TAILSCALE_HOSTNAME is required}"
: "${TAILSCALE_AUTH_KEY:?TAILSCALE_AUTH_KEY is required}"
TAILSCALE_EXIT_NODE="${TAILSCALE_EXIT_NODE:-false}"

echo "Tailscale installation starting…"
echo " - Sensitive configuration values hidden for security."

# Detect Debian codename
source /etc/os-release
codename="${VERSION_CODENAME}"

# Required for trixie/bookworm repository verification
sudo apt-get update -y
sudo apt-get install -y sq gpg

# Prepare keyring
sudo install -d -m 0755 /usr/share/keyrings

curl -fsSL "https://pkgs.tailscale.com/stable/debian/${codename}.pubkey.gpg" \
  | sudo gpg --dearmor --yes \
      -o /usr/share/keyrings/tailscale-archive-keyring.gpg

sudo chmod 644 /usr/share/keyrings/tailscale-archive-keyring.gpg

# Add repository
echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/debian ${codename} main" \
  | sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null

sudo apt-get update -y
sudo apt-get install -y tailscale

# Exit node flag
EXIT_FLAG=""
if [[ "$TAILSCALE_EXIT_NODE" == "true" ]]; then
  EXIT_FLAG="--advertise-exit-node"
fi

sudo tailscale up \
  --authkey="$TAILSCALE_AUTH_KEY" \
  --hostname="$TAILSCALE_HOSTNAME" \
  $EXIT_FLAG

echo "Tailscale installed and running."
