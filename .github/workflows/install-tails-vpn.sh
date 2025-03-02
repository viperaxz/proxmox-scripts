name: Install Tailscale on Proxmox

on:
  workflow_dispatch:
    inputs:
      tailscale_domain:
        description: 'Define your Tailscale domain'
        required: true
        default: 'yourdomain.com'
      tailscale_hostname:
        description: 'Define your Tailscale hostname'
        required: true
        default: 'pve'
      tailscale_exit_node:
        description: 'Set to "true" to advertise as an exit node'
        required: false
        default: 'false'
  push:
    branches:
      - main

jobs:
  install-tailscale:
    runs-on: ubuntu-latest
    env:
      TAILSCALE_DOMAIN: ${{ github.event.inputs.tailscale_domain }}
      TAILSCALE_HOSTNAME: ${{ github.event.inputs.tailscale_hostname }}
      TAILSCALE_EXIT_NODE: ${{ github.event.inputs.tailscale_exit_node }}
    steps:
      - name: Checkout repository
        uses: actions/checkout@v3

      - name: Uninstall and Install Tailscale on Proxmox via SSH
        uses: appleboy/ssh-action@v0.1.7
        with:
          host: ${{ secrets.PROXMOX_HOST }}
          username: ${{ secrets.PROXMOX_USER }}
          port: 22
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          # If you prefer password authentication, comment out the key line above and uncomment below:
          # password: ${{ secrets.SSH_PASSWORD }}
          script: |
            #!/bin/bash
            set -e

            # Uninstall Tailscale if it exists.
            if command -v tailscale >/dev/null 2>&1; then
              echo "Tailscale is already installed. Uninstalling..."
              sudo tailscale down
              sudo apt-get purge -y tailscale || true
              sudo apt-get autoremove -y || true
            else
              echo "Tailscale is not installed. Proceeding with installation."
            fi

            # Install Tailscale using the official install script.
            curl -fsSL https://tailscale.com/install.sh | sh

            # Set exit node flag if requested.
            if [ "$TAILSCALE_EXIT_NODE" = "true" ]; then
              EXIT_FLAG="--advertise-exit-node"
            else
              EXIT_FLAG=""
            fi

            # Bring up Tailscale using your auth key and assign a fully qualified hostname.
            sudo tailscale up --authkey=${{ secrets.TAILSCALE_AUTH_KEY }} --hostname="${TAILSCALE_HOSTNAME}.${TAILSCALE_DOMAIN}" $EXIT_FLAG

            # (Optional) Display Tailscale status for verification.
            sudo tailscale status
