#!/bin/bash

# Parameter to control token overwrite; defaults to false.
OVERWRITE_TOKEN=${OVERWRITE_TOKEN:-false}

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

# Update package list and install sudo and jq if needed.
$SUDO apt-get update && $SUDO apt-get install sudo jq -y

#######################################
# Check for existing user using JSON output.
#######################################
if $SUDO pveum user list --noheader 1 --noborder 1 --output-format json-pretty | \
      jq -e '.[] | select(.userid=="'"$userid"'")' > /dev/null; then
    echo "User '$userid' exists. Using existing user."
else
    echo "Creating user '$userid'."
    $SUDO pveum user add $userid
fi

#######################################
# Check for existing role and ensure privileges.
#######################################
if $SUDO pveum role list --noheader 1 --noborder 1 --output-format json-pretty | \
      jq -e '.[] | select(.roleid=="'"$roleid"'")' > /dev/null; then
    echo "Role '$roleid' exists. Checking privileges."
    # Extract the current privileges for the role.
    current_privs=$($SUDO pveum role list --noheader 1 --noborder 1 --output-format json-pretty | \
        jq -r '.[] | select(.roleid=="'"$roleid"'") | .privs')
    
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

#######################################
# Assign the role to the user via ACL.
#######################################
$SUDO pveum aclmod / -user $userid -role $roleid

#######################################
# Check for existing token using JSON output.
#######################################
if $SUDO pveum user token list $userid --noheader 1 --noborder 1 --output-format json-pretty | \
      jq -e '.[] | select(.tokenid=="'"$tokenid"'")' > /dev/null; then
    if [ "$OVERWRITE_TOKEN" = "true" ]; then
        echo "Overwrite enabled: Deleting existing token '$tokenid' for user '$userid'."
        $SUDO pveum user token delete $userid $tokenid
        echo "Creating new token '$tokenid' for user '$userid'."
        $SUDO pveum user token add $userid $tokenid -privsep false
    else
        echo "Token '$tokenid' for user '$userid' exists."
    fi
else
    echo "Creating token '$tokenid' for user '$userid'."
    $SUDO pveum user token add $userid $tokenid -privsep false
fi

#######################################
# Save token details (using JSON output) into a file and display them.
#######################################
$SUDO pveum user token list $userid --noheader 1 --noborder 1 --output-format json-pretty | \
    jq -c '.[] | select(.tokenid=="'"$tokenid"'")' > token

echo "Token details:"
cat token
