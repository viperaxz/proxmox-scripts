
# Tailscale Installation Workflow for Proxmox

instll-tails-vpn is a GitHub Actions Workflow that automates the installation (or reinstallation) of [Tailscale](https://tailscale.com) on a Proxmox server. The workflow connects to the Proxmox server via SSH, uninstalls any existing Tailscale installation, and then installs and configures Tailscale using your provided authentication key. Additionally, it lets you optionally advertise the node as an exit node.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Configuration](#configuration)
  - [GitHub Secrets](#github-secrets)
  - [Workflow Dispatch Inputs](#workflow-dispatch-inputs)
- [Usage](#usage)
- [Workflow Details](#workflow-details)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## Overview

This workflow does the following:
- **Uninstall Existing Tailscale:** If Tailscale is already installed, the workflow stops its service and uninstalls it.
- **Install Tailscale:** Uses the official Tailscale installation script to install Tailscale.
- **Configure Tailscale:** Sets up Tailscale with your authentication key and assigns the node a fully qualified hostname composed of a user-defined hostname and domain.
- **Optional Exit Node Setup:** You can choose to advertise the node as an exit node by setting an input variable.

## Prerequisites

Before using this workflow, ensure you have:

- **A Proxmox Server**: Accessible via SSH.
- **GitHub Repository:** Where you can store the workflow file.
- **Tailscale Auth Key:** Obtain a valid authentication key from [Tailscale Admin Console](https://login.tailscale.com/admin/settings/authkeys). ( Check -> Reusable and Ephemeral )
- **SSH Access:** Configured either with an SSH private key or a password.
- **GitHub Actions Runner:** The default runner is sufficient.

## Configuration

### GitHub Secrets

Set up the following secrets in your repository (under **Settings → Secrets and variables → Actions**):

- `PROXMOX_HOST`: The external IP address (or domain name) of your Proxmox server.
- `PROXMOX_USER`: The SSH username for your Proxmox server, you may use root
- `SSH_PRIVATE_KEY`: Your private SSH key (or alternatively, use `SSH_PASSWORD` - not recommanded).
- `TAILSCALE_AUTH_KEY`: Your Tailscale authentication key.

### Workflow Dispatch Inputs

When manually triggering the workflow, you can set these non-sensitive configuration values:

- **`tailscale_domain`**: The interal domain for your Tailscale node (default: `yourdomain.com`).
- **`tailscale_hostname`**: The hostname for your Tailscale node (default: `proxmox-node`).
- **`tailscale_exit_node`**: Set to `"true"` to advertise the node as an exit node; defaults to `"false"`.

These inputs are passed as environment variables to the workflow.

## Usage

1. **Add the Workflow File:**

   Create a file at `.github/workflows/install-tailscale.yml` in your repository and paste the workflow code provided.

2. **Trigger the Workflow:**

   - **Manually:**  
     - Go to the **Actions** tab in your repository.
     - Select the **Install Tailscale on Proxmox** workflow.
     - Click **Run workflow** and provide your custom inputs if needed.
     
   - **Automatically:**  
     Any push to the `main` branch will also trigger the workflow.

## Workflow Details

The workflow uses the `appleboy/ssh-action` to connect to your Proxmox server via SSH. Here is an outline of the steps performed:

1. **Repository Checkout:**  
   The workflow checks out the repository to ensure the latest version is used.

2. **SSH Connection & Script Execution:**  
   The script executed on the server:
   - Checks if Tailscale is installed. If so, it runs `tailscale down` and uninstalls it using `apt-get purge` and `apt-get autoremove`.
   - Installs Tailscale using its official installation script.
   - Constructs the fully qualified hostname by combining the provided `tailscale_hostname` and `tailscale_domain`.
   - Checks the value of `tailscale_exit_node` and adds the `--advertise-exit-node` flag if set to `"true"`.
   - Starts Tailscale with the provided authentication key.
   - Optionally displays Tailscale status for verification.

Below is the relevant snippet of the script:

```bash
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
```

## Troubleshooting

- **SSH Connection Issues:**  
  Ensure your Proxmox server is accessible from the GitHub Actions runner and that the SSH credentials in your secrets are correct.

- **Installation Failures:**  
  Make sure your Proxmox server uses `apt-get` as its package manager; if not, adjust the uninstall commands accordingly.

- **Incorrect Hostname/Domain:**  
  Verify that the workflow inputs are correctly set when triggering the workflow to form the proper fully qualified hostname.

## Contributing

Contributions, suggestions, and improvements are welcome! Please open issues or submit pull requests if you have enhancements or fixes.

## License

This project is licensed under the [MIT License](LICENSE).

---

This `README.md` file provides detailed instructions on how to set up and use the workflow, making it easier for others to understand and utilize the script in their own environment.