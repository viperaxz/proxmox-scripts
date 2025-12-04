#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

: "${TAILSCALE_HOSTNAME:?TAILSCALE_HOSTNAME is required}"
: "${TAILSCALE_AUTH_KEY:?TAILSCALE_AUTH_KEY is required}"
TAILSCALE_EXIT_NODE="${TAILSCALE_EXIT_NODE:-false}"
TAILSCALE_RESET="${TAILSCALE_RESET:-false}"    # set true to force re-auth

echo "Tailscale installation starting…"

# --- Enable forwarding (needed for subnet routes / exit node; harmless otherwise)
sudo tee /etc/sysctl.d/99-tailscale.conf >/dev/null <<'EOF'
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF
sudo sysctl --system >/dev/null

# --- If already configured and no reset requested, just bring it up and exit
if sudo tailscale status >/dev/null 2>&1 && [[ "$TAILSCALE_RESET" != "true" ]]; then
  echo "Tailscale already configured; bringing it up…"
  args=(--hostname="$TAILSCALE_HOSTNAME")
  if [[ "$TAILSCALE_EXIT_NODE" == "true" ]]; then
    args+=(--advertise-exit-node)
  fi
  sudo tailscale up "${args[@]}" || true
  sudo tailscale status
  exit 0
fi

# --- Detect OS codename (Proxmox 9 is Debian trixie)
source /etc/os-release
codename="${VERSION_CODENAME}"

# --- Install repo key + repo list (Tailscale documented method for Debian trixie/bookworm/etc.)
sudo install -d -m 0755 /usr/share/keyrings
sudo chmod 0755 /usr/share/keyrings
sudo rm -f /usr/share/keyrings/tailscale-archive-keyring.gpg

curl -fsSL "https://pkgs.tailscale.com/stable/debian/${codename}.noarmor.gpg" \
  | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
sudo chmod 0644 /usr/share/keyrings/tailscale-archive-keyring.gpg

curl -fsSL "https://pkgs.tailscale.com/stable/debian/${codename}.tailscale-keyring.list" \
  | sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null

# --- Install tailscale
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y tailscale

# --- Re-auth / refresh credentials if requested or not configured
echo "Authenticating Tailscale…"
args=(--authkey="$TAILSCALE_AUTH_KEY" --hostname="$TAILSCALE_HOSTNAME" --reset)
if [[ "$TAILSCALE_EXIT_NODE" == "true" ]]; then
  args+=(--advertise-exit-node)
fi

sudo tailscale up "${args[@]}"
sudo tailscale status
echo "Done."
