#!/bin/bash
set -euo pipefail

declare -A OS_OPTIONS=(
    ["1"]="Ubuntu 22.04|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
    ["2"]="Ubuntu 24.04|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
    ["3"]="Debian 11|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2"
    ["4"]="Debian 12|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
    ["5"]="Fedora 40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2"
    ["6"]="CentOS Stream 9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2"
    ["7"]="AlmaLinux 9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2"
    ["8"]="Rocky Linux 9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2"
    ["9"]="Arch Linux|https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2"
)

VM_DIR="${VM_DIR:-$HOME/vms}"
mkdir -p "$VM_DIR"

check_dependencies() {
    local deps=("qemu-system-x86_64" "qemu-img" "wget" "cloud-localds")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        echo "Missing dependencies: ${missing[*]}"
        echo "Installing..."
        sudo apt install -y qemu-system cloud-image-utils wget
    else
        echo "All dependencies found!"
    fi
}

display_header() {
    clear
    echo -e "\033[1;93m"
    cat << "EOF"
  ______              _ _          __      ____  __  _____ 
 |  ____|            (_) |         \ \    / /  \/  |/ ____|
 | |__ _____  ____  ___| |_ _   _   \ \  / /| \  / | (___  
 |  __/ _ \ \/ /\ \/ / | __| | | |   \ \/ / | |\/| |\___ \ 
 | | | (_) >  <  >  <| | |_| |_| |    \  /  | |  | |____) |
 |_|  \___/_/\_\/_/\_\_|\__|\__, |     \/   |_|  |_|_____/ 
                             __/ |                         
                            |___/                          
--------------------------------------------------------------------
EOF
    echo -e "\033[0m"
}

setup_vm_image() {
    local IMG_FILE="$VM_DIR/$VM_NAME.img"

    echo "Downloading $OS_NAME image..."
    wget --progress=bar:force "$IMG_URL" -O "$IMG_FILE.tmp"
    mv "$IMG_FILE.tmp" "$IMG_FILE"

    echo "Resizing disk to $DISK_SIZE..."
    qemu-img resize "$IMG_FILE" "$DISK_SIZE"

    echo "Creating cloud-init config..."

    cat > /tmp/user-data <<EOF
#cloud-config
hostname: $VM_NAME
ssh_pwauth: true
disable_root: false
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    password: $(openssl passwd -6 "$PASSWORD")
chpasswd:
  list: |
    root:$PASSWORD
    $USERNAME:$PASSWORD
  expire: false
EOF

    cat > /tmp/meta-data <<EOF
instance-id: iid-$VM_NAME
local-hostname: $VM_NAME
EOF

    local SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    cloud-localds "$SEED_FILE" /tmp/user-data /tmp/meta-data
    echo "SEED_FILE=\"$SEED_FILE\"" >> "$VM_DIR/$VM_NAME.conf"
    echo "IMG_FILE=\"$IMG_FILE\"" >> "$VM_DIR/$VM_NAME.conf"

    echo "Image ready!"
}

create_vm() {
    echo -e "\033[0;93m"
    echo "  === Create New VM ==="
    echo -e "\033[0m"

    # VM Name - required
    while true; do
        read -p "Enter VM name: " VM_NAME
        if [ -z "$VM_NAME" ]; then
            echo "VM name is required, please enter a name!"
        else
            break
        fi
    done

    # Username - default root
    read -p "Enter username (default: root): " USERNAME
    USERNAME="${USERNAME:-root}"

    # Password - default empty
    read -s -p "Enter password (leave empty for no password): " PASSWORD
    echo

    # Memory - default 1024MB
    read -p "RAM in MB (default: 1024): " MEMORY
    MEMORY="${MEMORY:-1024}"

    # CPUs - default 1
    read -p "CPU cores (default: 1): " CPUS
    CPUS="${CPUS:-1}"

    # Disk size - default 100M
    read -p "Disk size (default: 100M): " DISK_SIZE
    DISK_SIZE="${DISK_SIZE:-100M}"

    # SSH port - default 2222
    read -p "SSH port (default: 2222): " SSH_PORT
    SSH_PORT="${SSH_PORT:-2222}"

    # OS - required
    while true; do
        echo "Select OS:"
        for key in $(echo "${!OS_OPTIONS[@]}" | tr ' ' '\n' | sort -n); do
            echo "  $key) $(echo "${OS_OPTIONS[$key]}" | cut -d'|' -f1)"
        done
        read -p "Enter OS choice: " os_choice
        if [ -z "$os_choice" ] || [ -z "${OS_OPTIONS[$os_choice]+x}" ]; then
            echo "OS selection is required, please choose a valid option!"
        else
            IMG_URL=$(echo "${OS_OPTIONS[$os_choice]}" | cut -d'|' -f2)
            OS_NAME=$(echo "${OS_OPTIONS[$os_choice]}" | cut -d'|' -f1)
            break
        fi
    done

    local config_file="$VM_DIR/$VM_NAME.conf"

    cat > "$config_file" <<EOF
VM_NAME="$VM_NAME"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
MEMORY="$MEMORY"
CPUS="$CPUS"
DISK_SIZE="$DISK_SIZE"
SSH_PORT="$SSH_PORT"
OS_NAME="$OS_NAME"
IMG_URL="$IMG_URL"
EOF

    echo "VM '$VM_NAME' config saved!"
    setup_vm_image
}

start_vm() {
    # List available VMs
    local vms=($(ls "$VM_DIR"/*.conf 2>/dev/null | xargs -I{} basename {} .conf))
    
    if [ ${#vms[@]} -eq 0 ]; then
        echo "No VMs found!"
        return
    fi

    echo "Select a VM to start:"
    for i in "${!vms[@]}"; do
        echo "  $((i+1))) ${vms[$i]}"
    done

    read -p "Enter choice: " vm_choice
    local vm_name="${vms[$((vm_choice-1))]}"

    # Load the VM config
    source "$VM_DIR/$vm_name.conf"

    echo "Starting $VM_NAME..."

    qemu-system-x86_64 \
        -enable-kvm \
        -m "$MEMORY" \
        -smp "$CPUS" \
        -cpu host \
        -drive "file=$IMG_FILE,format=qcow2,if=virtio" \
        -drive "file=$SEED_FILE,format=raw,if=virtio" \
        -device virtio-net-pci,netdev=n0 \
        -netdev "user,id=n0,hostfwd=tcp::$SSH_PORT-:22" \
        -nographic \
        -serial mon:stdio
}

main_menu() {
    while true; do
        display_header
        echo -e "\033[0;93m"
        echo "  1) Create VM"
        echo "  2) Start VM"
        echo "  3) Stop VM"
        echo "  4) Delete VM"
        echo "  5) VM Settings"
        echo "  6) Show Info"
        echo "  0) Exit"
        echo -e "\033[0m"

        read -p "Enter choice: " choice

        case $choice in
            1) create_vm ;;
            2) start_vm ;;
            3) stop_vm ;;
            4) delete_vm ;;
            5) vm_settings ;;
            6) show_info ;;
            0) exit 0 ;;
            *) echo "Invalid option" ;;
        esac
    done
}

check_dependencies
main_menu
