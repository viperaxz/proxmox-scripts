#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
umask 077

OVERWRITE_TOKEN="${OVERWRITE_TOKEN:-false}"

roleid="${ROLE_ID:-TerraformDeploy}"
userid="${USER_ID:-terraform-deploy@pve}"
tokenid="${TOKEN_ID:-token1}"

# Strongly recommended: scope this to /pool/<pool> or /vms/<id> etc.
acl_path="${ACL_PATH:-/}"

# Token privilege separation: recommended true (1)
privsep="${PRIVSEP:-1}"

# Where to store the *one-time* token secret output (root-only)
token_dir="${TOKEN_DIR:-/root/proxmox-api-tokens}"
token_file="${token_dir}/${userid//@/_}__${tokenid}.secret"

required_privs="VM.Allocate VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Monitor VM.Audit VM.PowerMgmt Datastore.AllocateSpace Datastore.Audit"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Please run as root (recommended) or ensure passwordless sudo is configured." >&2
  exit 1
fi
SUDO=""

need_cmd() { command -v "$1" >/dev/null 2>&1; }

if ! need_cmd jq; then
  apt-get update
  apt-get install -y jq
fi

mkdir -p "$token_dir"
chmod 700 "$token_dir"

user_exists() {
  pveum user list --output-format json \
    | jq -e --arg u "$userid" '.[] | select(.userid==$u)' >/dev/null
}

role_exists() {
  pveum role list --output-format json \
    | jq -e --arg r "$roleid" '.[] | select(.roleid==$r)' >/dev/null
}

token_exists() {
  pveum user token list "$userid" --output-format json \
    | jq -e --arg t "$tokenid" '.[] | select(.tokenid==$t)' >/dev/null
}

echo "Ensuring user: $userid"
if user_exists; then
  echo " - user exists"
else
  pveum user add "$userid"
  echo " - user created"
fi

echo "Ensuring role: $roleid (exact privileges enforced)"
if role_exists; then
  # Enforce exact privileges to avoid privilege creep
  pveum role modify "$roleid" -privs "$required_privs"
  echo " - role updated"
else
  pveum role add "$roleid" -privs "$required_privs"
  echo " - role created"
fi

echo "Ensuring ACL on path: $acl_path"
# You can (and should) also assign ACL specifically to the token when privsep=1.
pveum aclmod "$acl_path" -user "$userid" -role "$roleid"

echo "Ensuring API token: ${userid}!${tokenid} (privsep=$privsep)"
if token_exists; then
  if [[ "$OVERWRITE_TOKEN" == "true" ]]; then
    pveum user token delete "$userid" "$tokenid"
    echo " - existing token deleted"
  else
    echo " - token exists (not overwriting)"
    exit 0
  fi
fi

# IMPORTANT: do NOT let token secret hit stdout (GitHub logs).
# pveum prints the secret only at creation time.
pveum user token add "$userid" "$tokenid" -privsep "$privsep" >"$token_file"
chmod 600 "$token_file"
echo " - token created; secret saved on host to: $token_file"

# If using privsep=1, assign role directly to the token too (recommended).
# Token permissions are always a subset of its user’s permissions. :contentReference[oaicite:2]{index=2}
if [[ "$privsep" == "1" ]]; then
  pveum aclmod "$acl_path" -token "${userid}!${tokenid}" -role "$roleid"
  echo " - ACL applied to token on $acl_path"
fi

echo "Done."
