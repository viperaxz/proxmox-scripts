
# Create VM Template

This repository contains a GitHub Actions workflow and a Bash script to automate the creation of a Proxmox VM template based on an Ubuntu cloud image. The workflow uses manual dispatch so you can trigger it on demand, passing in various parameters such as the Ubuntu version, Proxmox Template ID, Template Name, and the index for the storage where the image should be placed.

## Table of Contents

- [Overview](#overview)
- [Workflow Details](#workflow-details)
- [Script Overview](#script-overview)
- [Prerequisites](#prerequisites)
- [Configuration](#configuration)
  - [Environment Variables](#environment-variables)
  - [Repository Secrets](#repository-secrets)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## Overview

The **Create VM Template** workflow automates the following tasks on a remote Proxmox server:
- Downloads (or copies) the Ubuntu cloud image if not already present in the Proxmox ISO storage.
- Configures the image by enabling CPU hotplug, installing the QEMU guest agent, resetting the machine ID, and setting custom DNS settings.
- Creates a VM template using Proxmox commands (`qm`).

The workflow is triggered manually via the GitHub Actions **workflow_dispatch** event. It passes the necessary parameters to the remote script using environment variables.

## Workflow Details

The workflow file (located at `.github/workflows/create-vm-template.yml`) is configured as follows:

```yaml
name: Create VM Template

on:
  workflow_dispatch:
    inputs:
      UBUNTU_VERSION:
        description: "Ubuntu version (default: 24.04)"
        required: false
        default: "24.04"
      VM_TMPL_ID:
        description: "Proxmox Template ID (default: 9000)"
        required: false
        default: "9000"
      VM_TMPL_NAME:
        description: "Proxmox Template Name (default: ubuntu-2404)"
        required: false
        default: "ubuntu-2404"
      STORAGE_INDEX:
        description: "Storage index to use (default: 3)"
        required: false
        default: "3"

jobs:
  create-vm-template:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v3

      - name: Copy VM Template script to remote server
        uses: appleboy/scp-action@master
        with:
          host: ${{ vars.EXTERNAL_IP_OR_DOMAIN }}
          username: ${{ vars.USERNAME }}
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          port: ${{ vars.SSH_PORT }}
          source: "create-vm-template/script.sh"
          target: "~/create-vm-template/"

      - name: Execute VM Template script on remote server via SSH
        uses: appleboy/ssh-action@v1.2.1
        with:
          host: ${{ vars.EXTERNAL_IP_OR_DOMAIN }}
          username: ${{ vars.USERNAME }}
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          port: ${{ vars.SSH_PORT }}
          script: |
            export UBUNTU_VERSION="${{ github.event.inputs.UBUNTU_VERSION }}"
            export VM_TMPL_ID="${{ github.event.inputs.VM_TMPL_ID }}"
            export VM_TMPL_NAME="${{ github.event.inputs.VM_TMPL_NAME }}"
            export STORAGE_INDEX="${{ github.event.inputs.STORAGE_INDEX }}"
            chmod +x ~/create-vm-template/script.sh
            ~/create-vm-template/script.sh
```

### Key Points:
- **Manual Trigger:** The workflow is manually triggered with the ability to override default values.
- **SCP & SSH Steps:** The workflow securely copies the script to the remote server and executes it over SSH.
- **Dynamic Environment Variables:** Input parameters are passed to the script as environment variables.

## Script Overview

The Bash script (located at `create-vm-template/script.sh`) performs the following steps:

1. **Error Handling and Logging:**
   - Uses `set -euo pipefail` to abort on errors.
   - Implements an `error_handler` to output errors and perform cleanup.

2. **Command Execution:**
   - Defines a `run_cmd` function to execute commands, capturing any error output and printing error messages in red.

3. **Non-Interactive Configuration:**
   - Replaces interactive prompts with environment variables (`UBUNTU_VERSION`, `VM_TMPL_ID`, `VM_TMPL_NAME`, and `STORAGE_INDEX`). If these variables are not set, default values are used.
   - Double quotes are added around variable expansions to ensure proper handling of spaces or special characters.

4. **Image Processing:**
   - Checks whether the desired Ubuntu image exists in the Proxmox ISO storage.
   - Downloads the image if it does not exist or if the checksum does not match.
   - Copies the image to the proper location if required.

5. **Customization:**
   - Enables CPU hotplug.
   - Installs the QEMU guest agent.
   - Resets the machine ID.
   - Sets custom DNS resolvers.

6. **VM Template Creation:**
   - Uses Proxmox commands (`qm`) to create and configure the VM template.
   - Destroys any existing VM template with the same ID before creation.

7. **Cleanup:**
   - Removes temporary files and directories created during the process.

Below is the complete script for reference:

```bash
#!/bin/bash

set -euo pipefail

# Function to handle errors
error_handler() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo -e "\e[31mThe script exited with status ${exit_code}.\e[0m" 1>&2
        cleanup
        exit ${exit_code}
    fi
}

trap error_handler EXIT

# Function to run commands and capture stderr
run_cmd() {
    local cmd="$1"
    local stderr_file
    stderr_file=$(mktemp)

    if ! eval "$cmd" > /dev/null 2>"$stderr_file"; then
        echo -e "\e[31mError\n Command '$cmd' failed with output:\e[0m" 1>&2
        awk '{print " \033[31m" $0 "\033[0m"}' "$stderr_file" 1>&2
        rm -f "$stderr_file"
        exit 1
    fi

    rm -f "$stderr_file"
}

# Function to print OK message
print_ok () {
    echo -e "\e[32mOK\e[0m"
}

# Default values
df_ubuntu_ver="24.04"
df_vm_tmpl_id="9000"
df_vm_tmpl_name="ubuntu-2404"

# Use environment variables or fall back to defaults.
ubuntu_ver="${UBUNTU_VERSION:-$df_ubuntu_ver}"
vm_tmpl_id="${VM_TMPL_ID:-$df_vm_tmpl_id}"
vm_tmpl_name="${VM_TMPL_NAME:-$df_vm_tmpl_name}"

# Get list of storages
storages=($(pvesm status | awk 'NR>1 {print $1}'))
echo " Available storages:"
for i in "${!storages[@]}"; do
    echo "  $i: ${storages[$i]}"
done

# Use environment variable for storage index (default 0)
storage_index="${STORAGE_INDEX:-0}"
vm_disk_storage="${storages[$storage_index]}"

# Construct the Ubuntu image URL based on the version input
ubuntu_img_url="https://cloud-images.ubuntu.com/releases/${ubuntu_ver}/release/ubuntu-${ubuntu_ver}-server-cloudimg-amd64.img"
ubuntu_img_filename=$(basename "$ubuntu_img_url")
ubuntu_img_base_url=$(dirname "$ubuntu_img_url")
df_iso_path="/var/lib/vz/template/iso"
script_tmp_path=/tmp/proxmox-scripts

install_lib () {
    local name="$1"
    echo -n "Installing $name..."
    run_cmd "apt-get install -y $name"
    print_ok
}

init () {
    cleanup
    install_lib "libguestfs-tools"
    mkdir -p "$script_tmp_path"
    cd "$script_tmp_path" || exit
}

get_image () {
    local existing_img="$df_iso_path/$ubuntu_img_filename"
    local img_sha256sum
    img_sha256sum=$(curl -s "$ubuntu_img_base_url/SHA256SUMS" | grep "$ubuntu_img_filename" | awk '{print $1}')

    if [ -f "$existing_img" ] && [[ $(sha256sum "$existing_img" | awk '{print $1}') == $img_sha256sum ]]; then
        echo -n "The image file exists in Proxmox ISO storage. Copying..."
        run_cmd "cp $existing_img $ubuntu_img_filename"
        print_ok
    else
        echo -n "The image file does not exist in Proxmox ISO storage. Downloading..."
        run_cmd "wget $ubuntu_img_url -O $ubuntu_img_filename"
        print_ok

        echo -n "Copying the image to Proxmox ISO storage..."
        run_cmd "cp $ubuntu_img_filename $existing_img"
        print_ok
    fi
}

enable_cpu_hotplug () {
    echo -n "Enabling CPU hotplug..."
    run_cmd "virt-customize -a $ubuntu_img_filename --run-command 'echo \"SUBSYSTEM==\\\"cpu\\\", ACTION==\\\"add\\\", TEST==\\\"online\\\", ATTR{online}==\\\"0\\\", ATTR{online}=\\\"1\\\"\" > /lib/udev/rules.d/80-hotplug-cpu.rules'"
    print_ok
}

install_qemu_agent () {
    echo -n "Installing QEMU guest agent..."
    run_cmd "virt-customize -a $ubuntu_img_filename --run-command 'apt update -y && apt install qemu-guest-agent -y && systemctl start qemu-guest-agent'"
    print_ok
}

reset_machine_id () {
    echo -n "Resetting the machine ID..."
    run_cmd "virt-customize -x -a $ubuntu_img_filename --run-command 'echo -n >/etc/machine-id'"
    print_ok
}

set_custom_dns () {
    echo -n "Setting custom DNS resolvers..."

    run_cmd "virt-customize -a $ubuntu_img_filename --run-command \
        'echo \"[Resolve]\" > /etc/systemd/resolved.conf && \
         echo \"DNS=1.1.1.1 1.0.0.1\" >> /etc/systemd/resolved.conf && \
         echo \"FallbackDNS=8.8.8.8 8.8.4.4\" >> /etc/systemd/resolved.conf && \
         echo \"Domains=~.\" >> /etc/systemd/resolved.conf && \
         echo \"DNSStubListener=no\" >> /etc/systemd/resolved.conf'"

    run_cmd "virt-customize -a $ubuntu_img_filename --run-command 'ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf'"
    print_ok
}

create_vm_tmpl () {
    echo -n "Creating VM template..."
    run_cmd "qm destroy $vm_tmpl_id --purge || true"
    run_cmd "qm create $vm_tmpl_id --name $vm_tmpl_name --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0"
    run_cmd "qm set $vm_tmpl_id --scsihw virtio-scsi-single"
    run_cmd "qm set $vm_tmpl_id --virtio0 $vm_disk_storage:0,import-from=$script_tmp_path/$ubuntu_img_filename"
    run_cmd "qm set $vm_tmpl_id --boot c --bootdisk virtio0"
    run_cmd "qm set $vm_tmpl_id --ide2 $vm_disk_storage:cloudinit"
    run_cmd "qm set $vm_tmpl_id --serial0 socket --vga serial0"
    run_cmd "qm set $vm_tmpl_id --agent enabled=1,fstrim_cloned_disks=1"
    run_cmd "qm template $vm_tmpl_id"
    print_ok
}

cleanup () {
    echo -n "Performing cleanup..."
    rm -rf "$script_tmp_path"
    print_ok
}

# Main script execution
init
get_image
enable_cpu_hotplug
install_qemu_agent
reset_machine_id
set_custom_dns
create_vm_tmpl
```

## Prerequisites

Before running this workflow, ensure that your remote Proxmox server:

- Has SSH access enabled.
- Is configured with Proxmox and the necessary command-line tools (e.g., `pvesm`, `qm`, `virt-customize`).
- Can install additional packages (like `libguestfs-tools`) via `apt-get`.

## Configuration

### Environment Variables

Set the following environment variables in your GitHub repository (preferably via [GitHub Environments](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)):

- **EXTERNAL_IP_OR_DOMAIN:** The IP address or domain name of your Proxmox server.
- **USERNAME:** The username for SSH access.
- **SSH_PORT:** The SSH port number.

### Repository Secrets

Store your SSH private key as a secret:

- **SSH_PRIVATE_KEY:** The private key used for SSH authentication with your remote server.

## Usage

To run the workflow manually:

1. Navigate to the **Actions** tab in your GitHub repository.
2. Select the **Create VM Template** workflow.
3. Click **Run workflow**.
4. Optionally, modify the inputs (`UBUNTU_VERSION`, `VM_TMPL_ID`, `VM_TMPL_NAME`, and `STORAGE_INDEX`) as needed.
5. Click **Run workflow**.

The workflow will check out the repository, copy the script to your remote Proxmox server, and execute it with the specified inputs.

## Troubleshooting

- **SSH Connection Issues:**  
  Verify that the SSH key, username, and host details are correctly set. Ensure that your Proxmox server is reachable.

- **Command Failures:**  
  The script uses robust error handling. If a command fails, an error message in red will indicate the problematic command. Check the output logs for details.

- **Environment Variable Issues:**  
  Ensure all required environment variables are provided. The script uses defaults if variables are missing, but these may need to be adjusted for your specific environment.

## License

This project is licensed under your chosen license. (Include your license information here.)
