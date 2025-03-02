
# Tailscale Installation via GitHub Actions

This repository provides an automated solution to install Tailscale on a remote server using GitHub Actions. It includes a GitHub Actions workflow that securely copies and executes an installation script on your server. Follow the steps below to fork the repository, configure your Git environment, set up the necessary secrets, and use the provided scripts.

## Table of Contents
- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [FORKING & SETUP](#forking--setup)
- [Configuring GitHub Secrets and Variables](#configuring-github-secrets-and-variables)
- [GitHub Actions Workflow Explained](#github-actions-workflow-explained)
- [Shell Script Explanation](#shell-script-explanation)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## Overview
This project automates the process of installing (or reinstalling) Tailscale on your remote server. The GitHub Actions workflow does the following:
1. Checks out the repository.
2. Copies the Tailscale installation script to your remote server via SCP.
3. Executes the installation script over SSH, ensuring Tailscale is configured using your custom parameters.

## Prerequisites
Before you begin, ensure you have:
- A GitHub account.
- A remote server (preferably Ubuntu-based) with SSH access.
- SSH credentials (private key, username, host, and port).
- A valid Tailscale Auth Key (reusable, non epheral) (obtainable from [Tailscale](https://tailscale.com)).

## FORKING & SETUP
1. **Fork the Repository:**  
   Click the **Fork** button at the top-right corner of the repository page to create your own copy.

2. **Clone Your Fork Locally:**  
   Open your terminal and run:
   ```bash
   git clone https://github.com/your-username/your-forked-repo.git
   cd your-forked-repo
   ```

## Configuring GitHub Secrets and Variables
In your forked repository, navigate to **Settings > Secrets and variables > Actions** and set up the following:

### Secrets
- **SSH_PRIVATE_KEY:**  
  Your private SSH key for connecting to the remote server.

- **TAILSCALE_AUTH_KEY:**  
  Your Tailscale authentication key.

### Variables
- **EXTERNAL_IP_OR_DOMAIN:**  
  The IP address or domain name of your remote server.

- **USERNAME:**  
  The username used for SSH access on your remote server.

- **SSH_PORT:**  
  The SSH port number (default is usually 22).

- **TAILSCALE_HOSTNAME:**  
  The hostname to be assigned to your Tailscale instance on the remote server.

- **TAILSCALE_EXIT_NODE:**  
  Set this to `"true"` if you want your server to function as an exit node, or `"false"` otherwise.

## GitHub Actions Workflow Explained
The workflow file (e.g., `.github/workflows/install-tailscale.yml`) contains the following key steps:

1. **Checkout Repository:**  
   Uses `actions/checkout@v3` to pull the code from your repository.

2. **Copy Installation Script:**  
   Uses `appleboy/scp-action@master` to securely copy `install-tailscale-vpn/script.sh` to your remote server's home directory.

3. **Execute Installation Script:**  
   Uses `appleboy/ssh-action@v1.2.1` to SSH into your remote server. It sets the necessary environment variables (such as `TAILSCALE_HOSTNAME`, `TAILSCALE_EXIT_NODE`, and `TAILSCALE_AUTH_KEY`), grants execute permissions to the script, and runs it.

## Shell Script Explanation
The `install-tailscale-vpn/script.sh` script performs the following actions:

1. **Parameter Verification:**  
   It checks that `TAILSCALE_HOSTNAME` and `TAILSCALE_AUTH_KEY` are set. If not, it exits with an error message.

2. **Default Settings:**  
   If `TAILSCALE_EXIT_NODE` isn’t provided, it defaults to `"false"`.

3. **Uninstall Existing Tailscale:**  
   If Tailscale is already installed, the script will bring it down and uninstall it to ensure a clean installation.

4. **Install Tailscale:**  
   The script downloads and runs the official Tailscale install script using `curl`.

5. **Configuration:**  
   Finally, it brings up Tailscale with the provided authentication key and hostname. If configured as an exit node, it advertises this during setup.

## Usage

- **Manual Trigger:**  
  You can also run the workflow manually using the **Workflow Dispatch** option in the GitHub Actions tab.

- **Monitor:**  
  Check the GitHub Actions logs to verify that the script is copied and executed correctly on your remote server.

## Troubleshooting
- **Missing Environment Variables:**  
  Ensure all required GitHub Secrets and Variables are configured correctly.

- **SSH Connection Issues:**  
  Verify that your remote server is reachable via SSH and that your credentials are correct.

- **Script Errors:**  
  Review the GitHub Actions log output for any errors during the execution of the script, which can help diagnose issues.

## License
This project is licensed under the [MIT License](LICENSE).

---

Feel free to open issues or submit pull requests if you encounter any problems or have suggestions for improvement.
