#!/bin/bash

roleid="TerraformDeploy"
userid="terraform-deploy@pve"
tokenid="token1"
required_privs="VM.Allocate VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Monitor VM.Audit VM.PowerMgmt Datastore.AllocateSpace Datastore.Audit"

# Check if running as root; if so, do not use sudo.
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

# Update package list and install sudo if needed.
$SUDO apt-get update && $SUDO apt-get install sudo -y

# Check if the user exists; if not, create it.
if $SUDO pveum user show $userid &> /dev/null; then
    echo "User '$userid' exists. Using existing user."
else
    echo "Creating user '$userid'."
    $SUDO pveum user add $userid
fi

# Check if the role exists.
if $SUDO pveum role show $roleid &> /dev/null; then
    echo "Role '$roleid' exists. Checking privileges."
    # Retrieve current privileges (assumes output includes a line like "Privs: <privileges>")
    current_privs=$($SUDO pveum role show $roleid | grep -oP 'Privs:\s+\K.*')
    
    missing_privs=""
    for priv in $required_privs; do
        if ! echo "$current_privs" | grep -qw "$priv"; then
            missing_privs="$missing_privs $priv"
        fi
    done

    if [ -n "$missing_privs" ]; then
        echo "Adding missing privileges: $missing_privs"
        # Combine the existing privileges with the missing ones.
        new_privs="$current_privs $missing_privs"
        $SUDO pveum role update $roleid -privs "$new_privs"
    else
        echo "All required privileges are already set for role '$roleid'."
    fi
else
    echo "Role '$roleid' does not exist. Creating role with required privileges."
    $SUDO pveum role add $roleid -privs "$required_privs"
fi

# Assign the role to the user via ACL.
$SUDO pveum aclmod / -user $userid -role $roleid

# Check if the token exists; if not, create it with privilege separation disabled.
if $SUDO pveum user token show $userid $tokenid &> /dev/null; then
    echo "Token '$tokenid' for user '$userid' exists."
else
    echo "Creating token '$tokenid' for user '$userid'."
    $SUDO pveum user token add $userid $tokenid -privsep false
fi

# Save token details into a file named "token" and display them.
$SUDO pveum user token show $userid $tokenid > token
echo "Token details:"
cat token
