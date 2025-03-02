#!/bin/bash
set -e

# Check for required environment variables.
if [ -z "$TAILSCALE_DOMAIN" ]; then
  echo "Error: TAILSCALE_DOMAIN environment variable is not set."
  exit 1
fi

if [ -z "$TAILSCALE_HOSTNAME" ]; then
  echo "Error: TAILSCALE_HOSTNAME environment variable is not set."
  exit 1
fi

if [ -z "$TAILSCALE_AUTH_KEY" ]; then
  echo "Error: TAILSCALE_AUTH_KEY environment variable is not set."
  exit 1
fi

# Default TAILSCALE_EXIT_NODE to "false" if not provided.
if [ -z "$TAILSCALE_EXIT_NODE" ]; then
  TAILSCALE_EXIT_NODE="false"
fi

echo "Using the following parameters:"
echo "  Domain:      $TAILSCALE_DOMAIN"
echo "  Hostname:    $TAILSCALE_HOSTNAME"
echo "  Exit Node:   $TAILSCALE_EXIT_NODE"

# Uninstall Tailscale if it exists.
if command -v tailscale >/dev/null 2>&1; then
  echo "Tailscale is already installed. Uninstalling..."
  sudo tailscale down
  sudo apt-get purge -y tailscale || true
  sudo apt-get autoremove -y || true
else
  echo "Tailscale is not installed. Proceeding with installation..."
fi

# Install Tailscale using the official install script.
echo "Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

# Prepare the exit node flag if needed.
if [ "$TAILSCALE_EXIT_NODE" = "true" ]; then
  EXIT_FLAG="--advertise-exit-node"
else
  EXIT_FLAG=""
fi

# Construct the fully qualified hostname.
FULL_HOSTNAME="${TAILSCALE_HOSTNAME}.${TAILSCALE_DOMAIN}"
echo "Starting Tailscale with hostname: $FULL_HOSTNAME"

# Bring up Tailscale with the provided auth key and hostname.
sudo tailscale up --authkey="$TAILSCALE_AUTH_KEY" --hostname="$FULL_HOSTNAME" $EXIT_FLAG

# (Optional) Show Tailscale status.
sudo tailscale status
