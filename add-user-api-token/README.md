
---

# SAVE THE TOKEN IN A SAFE LOCATION, IT'S BEING SHOWN AT THE END OF THE SCRIPT


---

# Add User API Token

This GitHub Actions workflow automates the process of adding an API token for a designated user on a remote server. The workflow checks for the existence of a user, role, and token on the remote server (using Proxmox commands via `pveum`), and creates or updates them as needed.

## Table of Contents

- [Overview](#overview)
- [Workflow Details](#workflow-details)
- [Installation Script Overview](#installation-script-overview)
- [Prerequisites](#prerequisites)
- [Configuration](#configuration)
  - [Environment Variables](#environment-variables)
  - [Repository Secrets](#repository-secrets)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## Overview

This workflow is triggered manually via GitHub's **workflow_dispatch** event. It has an input parameter (`overwrite_token`) to control whether an existing API token should be replaced. When executed, the workflow:

1. **Checks out the repository** to get the required script.
2. **Copies the installation script** to a remote server using SCP.
3. **Executes the installation script** on the remote server over SSH.

The installation script itself:
- Checks if the specified user exists; if not, it creates the user.
- Verifies if the specified role exists and has all the required privileges. Missing privileges are added if necessary.
- Applies the role to the user via ACL modification.
- Checks for an existing token. If the token exists and the `overwrite_token` flag is set to `true`, the token is deleted and re-created; otherwise, it is left unchanged.
- Finally, the token details are saved to a file and displayed.

## Workflow Details

The workflow file (e.g., `.github/workflows/add-user-api-token.yml`) is defined as follows:

```yaml
name: Add user api token

on:
  workflow_dispatch:
    inputs:
      overwrite_token:
        description: 'Set to true to overwrite an existing token'
        required: false
        default: "false"

jobs:
  add-token:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v3

      - name: Copy installation script to remote server
        uses: appleboy/scp-action@master
        with:
          host: ${{ vars.EXTERNAL_IP_OR_DOMAIN }}
          username: ${{ vars.USERNAME }}
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          port: ${{ vars.SSH_PORT }}
          source: "add-user-api-token/script.sh"
          target: "~/"

      - name: Execute installation script on remote server via SSH
        uses: appleboy/ssh-action@v1.2.1
        with:
          host: ${{ vars.EXTERNAL_IP_OR_DOMAIN }}
          username: ${{ vars.USERNAME }}
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          port: ${{ vars.SSH_PORT }}
          script: |
            export OVERWRITE_TOKEN="${{ github.event.inputs.overwrite_token }}"
            chmod +x ~/add-user-api-token/script.sh
            ~/add-user-api-token/script.sh
```

## Installation Script Overview

The installation script (`add-user-api-token/script.sh`) performs the following tasks:

1. **Environment Setup:**  
   Determines whether to use `sudo` based on the current user's privileges and ensures that necessary packages (`sudo` and `jq`) are installed.

2. **User Check/Create:**  
   Checks if the user (`terraform-deploy@pve`) exists. If not, the user is created.

3. **Role Check/Update:**  
   Verifies whether the role (`TerraformDeploy`) exists. If it does, the script checks for required privileges and adds any missing ones. If the role does not exist, it is created with the specified privileges.

4. **Assign Role to User:**  
   Applies the role to the user using ACL modifications.

5. **Token Check/Create:**  
   Checks if the API token exists. If the token exists and the `OVERWRITE_TOKEN` parameter is `true`, the token is deleted and recreated. Otherwise, the token is left unchanged. If no token exists, it is created.

6. **Output:**  
   The script outputs the token details by writing them to a file named `token` and then displaying the contents.

## Prerequisites

Before using this workflow, ensure that you have:

- A remote server with SSH access.
- The Proxmox command-line tool (`pveum`) installed and properly configured on the remote server.
- The remote server accessible using the provided IP/domain, username, and SSH key.

## Configuration

### Environment Variables

This workflow uses several environment variables that you must define in your repository’s environment or via the GitHub Actions UI. The following variables are required:

- **EXTERNAL_IP_OR_DOMAIN**: The IP address or domain name of the remote server.
- **USERNAME**: The username used to log in to the remote server.
- **SSH_PORT**: The SSH port for connecting to the remote server.

To set these up:

1. Navigate to your repository on GitHub.
2. Go to **Settings** > **Environments**.
3. Create (or select) an environment (for example, "production").
4. Add the required environment variables (`EXTERNAL_IP_OR_DOMAIN`, `USERNAME`, `SSH_PORT`).

### Repository Secrets

The workflow also relies on sensitive information stored as secrets. You need to add the following secret:

- **SSH_PRIVATE_KEY**: The private SSH key used for authentication with your remote server.

To configure secrets:

1. Navigate to your repository on GitHub.
2. Go to **Settings** > **Secrets and variables** > **Actions**.
3. Click on **New repository secret**.
4. Enter `SSH_PRIVATE_KEY` as the name and paste your private key as the value.
5. Save the secret.

## Usage

To run the workflow manually:

1. Navigate to the **Actions** tab in your GitHub repository.
2. Select the **Add user api token** workflow.
3. Click on **Run workflow**.
4. Optionally, set the `overwrite_token` input to `"true"` if you want to force the creation of a new token.
5. Click **Run workflow**.

The workflow will then check out the repository, copy the script to the remote server, and execute it via SSH.

## Troubleshooting

- **SSH Connection Issues:**  
  Ensure that the SSH key, username, and host details are correctly configured. Verify that the remote server is accessible from GitHub Actions' runners.

- **Permissions Errors:**  
  The script checks if it is being run as root. If not, it prepends commands with `sudo`. Make sure the provided user has the necessary sudo privileges on the remote server.

- **Missing Packages:**  
  The script installs `sudo` and `jq` if they are not available. However, if you encounter issues, verify that the remote server can update its package list and install these packages.

- **Token Overwrite:**  
  If you set `overwrite_token` to `"true"`, an existing token will be deleted and recreated. Verify that this behavior matches your expectations.

## License

This project is licensed under the terms of your choice. (Include your license information here.)

---

This README should help you configure and understand the GitHub Actions workflow as well as the installation script used to manage user API tokens on your remote server.