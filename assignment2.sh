#!/bin/bash

echo "------------------------------"
echo "Starting Assignment 2 Script"
echo "------------------------------"

set -e  # Exit on any error

log() {
    echo -e "\n[INFO] $1"
}

error_exit() {
    echo -e "\n[ERROR] $1" >&2
    exit 1
}

# --------------------------
# Network Configuration
# --------------------------

log "Configuring network with static IP 192.168.16.21/24"

# Get interface that is NOT mgmt
NET_IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo" | grep -v "mgmt" | head -n 1)

if [ -z "$NET_IFACE" ]; then
    error_exit "Could not determine the network interface."
fi

# Try to detect the existing netplan YAML file
NETPLAN_FILE=$(find /etc/netplan -name "*.yaml" | head -n 1)

if [ -z "$NETPLAN_FILE" ]; then
    error_exit "No netplan config file found in /etc/netplan"
fi


# Backup original netplan config if not backed up yet
if [ ! -f "${NETPLAN_FILE}.bak" ]; then
    cp "$NETPLAN_FILE" "${NETPLAN_FILE}.bak"
    log "Backed up netplan config to ${NETPLAN_FILE}.bak"
fi

# Check if the desired static IP is already set
if grep -q "192.168.16.21" "$NETPLAN_FILE"; then
    log "Static IP already configured. Skipping netplan update."
else
    cat > "$NETPLAN_FILE" <<EOF
network:
  version: 2
  ethernets:
    $NET_IFACE:
      addresses:
        - 192.168.16.21/24
      gateway4: 192.168.16.2
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
EOF

    log "Applied new static IP configuration. Applying netplan..."
    netplan apply || log "Warning: netplan apply failed inside container (this may be expected)"
fi

# --------------------------
# Install required packages
# --------------------------
log "Checking and installing apache2 and squid if needed"

REQUIRED_PACKAGES=("apache2" "squid")

for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if dpkg -l | grep -qw "$pkg"; then
        log "$pkg is already installed"
    else
        log "$pkg is not installed. Installing..."
        apt-get update
        apt-get install -y "$pkg" || error_exit "Failed to install $pkg"
    fi
done


# --------------------------
# Create required user accounts
# --------------------------
log "Creating user accounts and configuring SSH keys"

USER_LIST=("dennis" "aubrey" "captain" "snibbles" "brownie" "scooter" "sandy" "perrier" "cindy" "tiger" "yoda")
EXTRA_KEY_DENNIS="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4rT3vTt99Ox5kndS4HmgTrKBT8SKzhK4rhGkEVGlCI student@generic-vm"

for user in "${USER_LIST[@]}"; do
    if id "$user" &>/dev/null; then
        log "User $user already exists"
    else
        log "Creating user $user"
        useradd -m -s /bin/bash "$user"
    fi

    # Setup .ssh and generate keys if needed
    HOME_DIR="/home/$user"
    SSH_DIR="$HOME_DIR/.ssh"

    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    chown "$user":"$user" "$SSH_DIR"

    # Generate keys if not exist
    if [ ! -f "$SSH_DIR/id_rsa.pub" ]; then
        sudo -u "$user" ssh-keygen -t rsa -b 2048 -f "$SSH_DIR/id_rsa" -N ""
    fi
    if [ ! -f "$SSH_DIR/id_ed25519.pub" ]; then
        sudo -u "$user" ssh-keygen -t ed25519 -f "$SSH_DIR/id_ed25519" -N ""
    fi

    # Create authorized_keys
    AUTH_KEYS="$SSH_DIR/authorized_keys"
    touch "$AUTH_KEYS"
    chmod 600 "$AUTH_KEYS"
    chown "$user":"$user" "$AUTH_KEYS"

    # Add their own keys
    cat "$SSH_DIR/id_rsa.pub" >> "$AUTH_KEYS"
    cat "$SSH_DIR/id_ed25519.pub" >> "$AUTH_KEYS"

    # For dennis, add the extra public key
    if [ "$user" == "dennis" ]; then
        echo "$EXTRA_KEY_DENNIS" >> "$AUTH_KEYS"
        usermod -aG sudo dennis
        log "Added sudo access and extra key for dennis"
    fi
done
