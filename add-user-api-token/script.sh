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

# Check if the user exists by listing users and grepping for an exact match.
if $SUDO pveum user list | grep -q "^$userid\b"; then
    echo "User '$userid' exists. Using existing user."
else
    echo "Creating user '$userid'."
    $SUDO pveum user add $userid
fi

# Check if the role exists by listing roles.
if $SUDO pveum role list | grep -q "^$roleid\b"; then
    echo "Role '$roleid' exists. Checking privileges."
    # Extract current privileges for the role.
    current_privs=$($SUDO pveum role list | grep "^$roleid\b" | sed "s/^$roleid\s*//")
    
    missing_privs=""
    for priv in $required_privs; do
        if ! echo "$current_privs" | grep -qw "$priv"; then
            missing_privs="$missing_privs $priv"
        fi
    done

    if [ -n "$missing_privs" ]; then
        echo "Adding missing privileges:$missing_privs"
        new_privs="$current_privs $missing_privs"
        $SUDO pveum role modify $roleid -privs "$new_privs"
    else
        echo "All required privileges are already set for role '$roleid'."
    fi
else
    echo "Role '$roleid' does not exist. Creating role with required privileges."
    $SUDO pveum role add $roleid -privs "$required_privs"
fi

# Assign the role to the user via ACL.
$SUDO pveum aclmod / -user $userid -role $roleid

# Check if the token exists by listing tokens for the user.
if $SUDO pveum user token list $userid | grep -qw "$tokenid"; then
    echo "Token '$tokenid' for user '$userid' exists."
else
    echo "Creating token '$tokenid' for user '$userid'."
    $SUDO pveum user token add $userid $tokenid -privsep false
fi

# Save token details (filtered from the token list) into a file named "token" and display them.
$SUDO pveum user token list $userid | grep "$tokenid" > token
echo "Token details:"
cat token