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
    while true; do
        read -p "SSH port (default: 2222): " SSH_PORT
        SSH_PORT="${SSH_PORT:-2222}"
        if ss -tln 2>/dev/null | grep -q ":$SSH_PORT "; then
            echo "Port $SSH_PORT is already in use, please choose another!"
        else
            break
        fi
    done

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

    source "$VM_DIR/$vm_name.conf"

    # KVM check
    if [ -e /dev/kvm ]; then
        KVM_FLAGS="-enable-kvm -cpu host"
        echo "KVM available, using hardware acceleration!"
    else
        KVM_FLAGS=""
        echo "KVM not available, using software emulation (slower)..."
    fi

    echo "Starting $VM_NAME..."
    echo "SSH into your VM with: ssh -p $SSH_PORT $USERNAME@localhost"

    qemu-system-x86_64 \
        $KVM_FLAGS \
        -m "$MEMORY" \
        -smp "$CPUS" \
        -drive "file=$IMG_FILE,format=qcow2,if=virtio" \
        -drive "file=$SEED_FILE,format=raw,if=virtio" \
        -device virtio-net-pci,netdev=n0 \
        -netdev "user,id=n0,hostfwd=tcp::$SSH_PORT-:22" \
        -nographic \
        -serial mon:stdio
}

stop_vm() {
    local vms=($(ls "$VM_DIR"/*.conf 2>/dev/null | xargs -I{} basename {} .conf))

    if [ ${#vms[@]} -eq 0 ]; then
        echo "No VMs found!"
        return
    fi

    echo "Select a VM to stop:"
    for i in "${!vms[@]}"; do
        echo "  $((i+1))) ${vms[$i]}"
    done

    read -p "Enter choice: " vm_choice
    local vm_name="${vms[$((vm_choice-1))]}"

    source "$VM_DIR/$vm_name.conf"

    if pgrep -f "qemu.*$IMG_FILE" > /dev/null; then
        pkill -f "qemu.*$IMG_FILE"
        echo "$VM_NAME stopped!"
    else
        echo "$VM_NAME is not running!"
    fi
}

delete_vm() {
    local vms=($(ls "$VM_DIR"/*.conf 2>/dev/null | xargs -I{} basename {} .conf))

    if [ ${#vms[@]} -eq 0 ]; then
        echo "No VMs found!"
        return
    fi

    echo "Select a VM to delete:"
    for i in "${!vms[@]}"; do
        echo "  $((i+1))) ${vms[$i]}"
    done

    read -p "Enter choice: " vm_choice
    local vm_name="${vms[$((vm_choice-1))]}"

    source "$VM_DIR/$vm_name.conf"

    read -p "Are you sure you want to delete $VM_NAME? (y/N): " confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -f "$IMG_FILE"
        rm -f "$SEED_FILE"
        rm -f "$VM_DIR/$vm_name.conf"
        echo "$VM_NAME deleted!"
    else
        echo "Deletion cancelled."
    fi
}

show_info() {
    local vms=($(ls "$VM_DIR"/*.conf 2>/dev/null | xargs -I{} basename {} .conf))

    if [ ${#vms[@]} -eq 0 ]; then
        echo "No VMs found!"
        return
    fi

    echo "Select a VM to show info:"
    for i in "${!vms[@]}"; do
        echo "  $((i+1))) ${vms[$i]}"
    done

    read -p "Enter choice: " vm_choice
    local vm_name="${vms[$((vm_choice-1))]}"

    source "$VM_DIR/$vm_name.conf"

    echo -e "\033[0;93m"
    echo "========================================"
    echo "  VM Info: $VM_NAME"
    echo "========================================"
    echo "  OS:       $OS_NAME"
    echo "  Username: $USERNAME"
    echo "  Password: $PASSWORD"
    echo "  RAM:      $MEMORY MB"
    echo "  CPUs:     $CPUS"
    echo "  Disk:     $DISK_SIZE"
    echo "  SSH Port: $SSH_PORT"
    echo "  IMG File: $IMG_FILE"
    echo "========================================"
    echo -e "\033[0m"
}

vm_settings() {
    local vms=($(ls "$VM_DIR"/*.conf 2>/dev/null | xargs -I{} basename {} .conf))

    if [ ${#vms[@]} -eq 0 ]; then
        echo "No VMs found!"
        return
    fi

    echo "Select a VM to configure:"
    for i in "${!vms[@]}"; do
        echo "  $((i+1))) ${vms[$i]}"
    done

    read -p "Enter choice: " vm_choice
    local vm_name="${vms[$((vm_choice-1))]}"

    source "$VM_DIR/$vm_name.conf"

    while true; do
        echo -e "\033[0;93m"
        echo "  === VM Settings: $VM_NAME ==="
        echo "  1) Resize Disk (current: $DISK_SIZE)"
        echo "  2) Resize RAM (current: $MEMORY MB)"
        echo "  3) Resize CPU cores (current: $CPUS)"
        echo "  4) Show Performance"
        echo "  0) Back"
        echo -e "\033[0m"

        read -p "Enter choice: " settings_choice

        case $settings_choice in
            1)
                read -p "New disk size (e.g. 20G): " new_disk
                qemu-img resize "$IMG_FILE" "$new_disk"
                DISK_SIZE="$new_disk"
                sed -i "s/DISK_SIZE=.*/DISK_SIZE=\"$DISK_SIZE\"/" "$VM_DIR/$vm_name.conf"
                echo "Disk resized to $DISK_SIZE!"
                ;;
            2)
                read -p "New RAM in MB (e.g. 2048): " new_ram
                MEMORY="$new_ram"
                sed -i "s/MEMORY=.*/MEMORY=\"$MEMORY\"/" "$VM_DIR/$vm_name.conf"
                echo "RAM updated to $MEMORY MB!"
                ;;
            3)
                read -p "New CPU core count (e.g. 4): " new_cpus
                CPUS="$new_cpus"
                sed -i "s/CPUS=.*/CPUS=\"$CPUS\"/" "$VM_DIR/$vm_name.conf"
                echo "CPUs updated to $CPUS!"
                ;;
            4)
                local qemu_pid=$(pgrep -f "qemu.*$IMG_FILE" || true)
                if [ -n "$qemu_pid" ]; then
                    echo "CPU Usage:"
                    ps -p "$qemu_pid" -o %cpu,%mem --no-headers
                    echo "Memory Usage:"
                    free -h
                else
                    echo "$VM_NAME is not running!"
                fi
                ;;
            0)
                break
                ;;
            *)
                echo "Invalid option!"
                ;;
        esac
    done
}

export_vm() {
    local vms=($(ls "$VM_DIR"/*.conf 2>/dev/null | xargs -I{} basename {} .conf))

    if [ ${#vms[@]} -eq 0 ]; then
        echo "No VMs found!"
        return
    fi

    echo "Select a VM to export:"
    for i in "${!vms[@]}"; do
        echo "  $((i+1))) ${vms[$i]}"
    done

    read -p "Enter choice: " vm_choice
    local vm_name="${vms[$((vm_choice-1))]}"

    source "$VM_DIR/$vm_name.conf"

    read -p "Enter export directory (default: $HOME): " export_dir
    export_dir="${export_dir:-$HOME}"

    local export_path="$export_dir/$vm_name"
    mkdir -p "$export_path"

    echo "Exporting $VM_NAME to $export_path..."
    cp "$IMG_FILE" "$export_path/"
    cp "$SEED_FILE" "$export_path/"

    cat > "$export_path/$vm_name.conf" <<EOF
VM_NAME="$VM_NAME"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
MEMORY="$MEMORY"
CPUS="$CPUS"
DISK_SIZE="$DISK_SIZE"
SSH_PORT="$SSH_PORT"
OS_NAME="$OS_NAME"
IMG_URL="$IMG_URL"
IMG_FILE="$vm_name.img"
SEED_FILE="$vm_name-seed.iso"
EOF

    echo "VM '$VM_NAME' exported to $export_path!"
    echo "Copy that folder to your other PC and use Import VM!"
}

import_vm() {
    read -p "Enter path to exported VM folder: " import_path

    if [ ! -d "$import_path" ]; then
        echo "Directory not found!"
        return
    fi

    local conf_file=$(ls "$import_path"/*.conf 2>/dev/null | head -1)

    if [ -z "$conf_file" ]; then
        echo "No VM config found in that directory!"
        return
    fi

    source "$conf_file"

    if [ -f "$VM_DIR/$VM_NAME.conf" ]; then
        echo "A VM with name '$VM_NAME' already exists!"
        read -p "Enter a new name for the imported VM: " VM_NAME
    fi

    read -p "Enter SSH port for this PC (default: $SSH_PORT): " new_port
    SSH_PORT="${new_port:-$SSH_PORT}"

    cp "$import_path/$IMG_FILE" "$VM_DIR/$VM_NAME.img"
    cp "$import_path/$SEED_FILE" "$VM_DIR/$VM_NAME-seed.iso"

    cat > "$VM_DIR/$VM_NAME.conf" <<EOF
VM_NAME="$VM_NAME"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
MEMORY="$MEMORY"
CPUS="$CPUS"
DISK_SIZE="$DISK_SIZE"
SSH_PORT="$SSH_PORT"
OS_NAME="$OS_NAME"
IMG_URL="$IMG_URL"
IMG_FILE="$VM_DIR/$VM_NAME.img"
SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
EOF

    echo "VM '$VM_NAME' imported successfully!"
    echo "You can now start it from the main menu."
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
        echo "  7) Export VM"
        echo "  8) Import VM"
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
            7) export_vm ;;
            8) import_vm ;;
            0) exit 0 ;;
            *) echo "Invalid option" ;;
        esac
    done
}

check_dependencies
main_menu
