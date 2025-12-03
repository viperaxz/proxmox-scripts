#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
umask 077

df_ubuntu_ver="24.04"
df_vm_tmpl_id="9000"
df_vm_tmpl_name="ubuntu-2404"

ubuntu_ver="${UBUNTU_VERSION:-$df_ubuntu_ver}"
vm_tmpl_id="${VM_TMPL_ID:-$df_vm_tmpl_id}"
vm_tmpl_name="${VM_TMPL_NAME:-$df_vm_tmpl_name}"

storage_index="${STORAGE_INDEX:-0}"

die() { echo "Error: $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1; }

# ---- Input validation (prevents command injection & footguns)
[[ "$ubuntu_ver" =~ ^[0-9]{2}\.[0-9]{2}$ ]] || die "UBUNTU_VERSION must look like 24.04"
[[ "$vm_tmpl_id" =~ ^[0-9]+$ ]] || die "VM_TMPL_ID must be numeric"
[[ "$storage_index" =~ ^[0-9]+$ ]] || die "STORAGE_INDEX must be numeric"
[[ "$vm_tmpl_name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$ ]] || die "VM_TMPL_NAME has unsafe characters"

# ---- deps
need_cmd pvesm || die "pvesm not found (run on Proxmox host)"
need_cmd qm    || die "qm not found (run on Proxmox host)"
need_cmd curl  || die "curl not found"

if ! need_cmd virt-customize; then
  apt-get update
  apt-get install -y libguestfs-tools
fi

df_iso_path="/var/lib/vz/template/iso"
tmp_dir="$(mktemp -d -t proxmox-scripts.XXXXXX)"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT

# ---- storage selection
mapfile -t storages < <(pvesm status | awk 'NR>1 {print $1}')
((${#storages[@]} > 0)) || die "No storages returned by pvesm status"
((storage_index < ${#storages[@]})) || die "STORAGE_INDEX out of range"

vm_disk_storage="${storages[$storage_index]}"

ubuntu_img_url="https://cloud-images.ubuntu.com/releases/${ubuntu_ver}/release/ubuntu-${ubuntu_ver}-server-cloudimg-amd64.img"
ubuntu_img_filename="$(basename "$ubuntu_img_url")"
ubuntu_img_base_url="$(dirname "$ubuntu_img_url")"

cd "$tmp_dir"

echo "Using:"
echo " - Ubuntu:   $ubuntu_ver"
echo " - Template: $vm_tmpl_id ($vm_tmpl_name)"
echo " - Storage:  $vm_disk_storage"

get_image() {
  local existing_img="${df_iso_path}/${ubuntu_img_filename}"

  echo "Fetching SHA256SUMS..."
  local sums
  sums="$(curl -fsSL "${ubuntu_img_base_url}/SHA256SUMS")"
  local img_sha
  img_sha="$(awk -v f="$ubuntu_img_filename" '$2==f {print $1}' <<<"$sums")"
  [[ -n "$img_sha" ]] || die "Could not find sha256 for $ubuntu_img_filename"

  if [[ -f "$existing_img" ]] && [[ "$(sha256sum "$existing_img" | awk '{print $1}')" == "$img_sha" ]]; then
    echo "Image exists & checksum OK; copying from ISO storage..."
    cp -- "$existing_img" "./$ubuntu_img_filename"
  else
    echo "Downloading image..."
    curl -fL --retry 3 --retry-delay 1 -o "./$ubuntu_img_filename" "$ubuntu_img_url"
    echo "Verifying checksum..."
    [[ "$(sha256sum "./$ubuntu_img_filename" | awk '{print $1}')" == "$img_sha" ]] || die "Checksum mismatch"

    echo "Copying to ISO storage..."
    install -m 0644 "./$ubuntu_img_filename" "$existing_img"
  fi
}

enable_cpu_hotplug() {
  virt-customize -a "./$ubuntu_img_filename" --run-command \
    "printf '%s\n' 'SUBSYSTEM==\"cpu\", ACTION==\"add\", TEST==\"online\", ATTR{online}==\"0\", ATTR{online}=\"1\"' > /lib/udev/rules.d/80-hotplug-cpu.rules"
}

install_qemu_agent() {
  virt-customize -a "./$ubuntu_img_filename" --run-command \
    "apt-get update -y && apt-get install -y qemu-guest-agent && systemctl enable --now qemu-guest-agent"
}

reset_machine_id() {
  virt-customize -a "./$ubuntu_img_filename" --run-command \
    "truncate -s 0 /etc/machine-id"
}

create_vm_tmpl() {
  qm destroy "$vm_tmpl_id" --purge || true

  qm create "$vm_tmpl_id" \
    --name "$vm_tmpl_name" \
    --memory 2048 \
    --cores 2 \
    --net0 virtio,bridge=vmbr0

  qm set "$vm_tmpl_id" --scsihw virtio-scsi-single
  qm set "$vm_tmpl_id" --virtio0 "${vm_disk_storage}:0,import-from=${tmp_dir}/${ubuntu_img_filename}"
  qm set "$vm_tmpl_id" --boot c --bootdisk virtio0
  qm set "$vm_tmpl_id" --ide2 "${vm_disk_storage}:cloudinit"
  qm set "$vm_tmpl_id" --serial0 socket --vga serial0
  qm set "$vm_tmpl_id" --agent enabled=1,fstrim_cloned_disks=1

  qm template "$vm_tmpl_id"
}

get_image
enable_cpu_hotplug
install_qemu_agent
reset_machine_id
create_vm_tmpl

echo "OK: template created: $vm_tmpl_id ($vm_tmpl_name)"
