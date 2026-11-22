#!/bin/bash


# The full Installer USB copies these values to the installed system.
if [ ! -r /root/deployment.env ]; then
    echo "Missing /root/deployment.env" >&2
    exit 1
fi
. /root/deployment.env

if [ -z "${TENABLE_LINK_KEY:-}" ] || [ -z "${TAILSCALE_AUTH_KEY:-}" ]; then
    echo "Deployment credentials are incomplete" >&2
    exit 1
fi

# Set Timezone
timedatectl set-timezone America/New_York
timedatectl set-ntp on

# fix keys
#mkdir -p /usr/share/keyrings
#wget https://archive.kali.org/archive-keyring.gpg -O /usr/share/keyrings/kali-archive-keyring.gpg
#apt update

# The full Installer USB provides this script. Legacy netboot installs fetch it.
if [ ! -s /etc/profile.d/logon-script.sh ]; then
    wget https://raw.githubusercontent.com/tallmega/KaliUnattended/refs/heads/main/logon-script.sh -O /etc/profile.d/logon-script.sh
fi

# Configure sudoers
echo "kali    ALL=(ALL:ALL) NOPASSWD:ALL" | tee -a /etc/sudoers

# Install necessary packages
apt-get update
apt-get install -y airgeddon unattended-upgrades mitm6 jq tesseract-ocr antiword fzf curl python3

# Configure Airgeddon
sed -i 's/AIRGEDDON_WINDOWS_HANDLING=xterm/AIRGEDDON_WINDOWS_HANDLING=tmux/' /usr/share/airgeddon/.airgeddonrc

# Enable and start SSH service
systemctl enable ssh.service
systemctl start ssh.service

# Enable unattended-upgrades
systemctl enable unattended-upgrades

# Configure unattended upgrades

# Uncomment "origin=Debian,codename=${distro_codename}-updates";
sed -i 's|// *"origin=Debian,codename=${distro_codename}-updates";|"origin=Debian,codename=${distro_codename}-updates";|' /etc/apt/apt.conf.d/50unattended-upgrades

# Append configurations for unattended upgrades
tee -a /etc/apt/apt.conf.d/50unattended-upgrades <<EOL
// Custom configurations
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::InstallOnShutdown "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-WithUsers "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
Unattended-Upgrade::OnlyOnACPower "false";
EOL

# Append contents of auto-upgrades settings file
tee -a /etc/apt/apt.conf.d/20auto-upgrades <<EOL
// How often (in days) to apt update
APT::Periodic::Update-Package-Lists "1";
// How often (in days) to download new packages
APT::Periodic::Download-Upgradeable-Packages "7";
// How often (in days) to clean the apt cache
APT::Periodic::AutocleanInterval "7";
// How often (in days) to run unattended-upgrades
APT::Periodic::Unattended-Upgrade "7";
EOL

# Ensure root filesystem is remounted read-write during boot
systemctl add-wants local-fs.target systemd-remount-fs.service
systemctl daemon-reload

# Install and configure Tailscale before contacting Sensor Proxy.
tailscale_setup_ok=false
if ! command -v tailscale >/dev/null 2>&1; then
    if curl -fsSL https://tailscale.com/install.sh -o /root/tsinstall.sh &&
       sh /root/tsinstall.sh; then
        rm -f /root/tsinstall.sh
    else
        echo 'Tailscale installation failed; first-boot setup will retry.' >&2
    fi
fi
if command -v tailscale >/dev/null 2>&1; then
    if tailscale status --json 2>/dev/null | jq -e '.BackendState == "Running"' >/dev/null; then
        tailscale_setup_ok=true
    elif tailscale up --auth-key="$TAILSCALE_AUTH_KEY" --ssh=true --advertise-tags tag:dropbox; then
        tailscale_setup_ok=true
    fi
fi

nessus_setup_ok=false
if [ "$tailscale_setup_ok" = true ] &&
   TENABLE_LINK_KEY="$TENABLE_LINK_KEY" /root/install-nessus.sh; then
    nessus_setup_ok=true
else
    echo 'Nessus setup is incomplete; the first-boot job will retry.' >&2
fi
unset TENABLE_LINK_KEY TAILSCALE_AUTH_KEY

# Upgrade packages. Keep the boot job until the managed scanner is verified.
upgrade_ok=false
if sudo apt-get upgrade -y; then
    upgrade_ok=true
fi

if [ "$upgrade_ok" = true ] && [ "$tailscale_setup_ok" = true ] &&
   [ "$nessus_setup_ok" = true ]; then
    # Remove the line containing the script entry from the crontab
    if sed -i '\|root/preseed_post.sh|d' /etc/crontab; then
        rm -f /root/deployment.env
    else
        echo 'Could not remove the first-boot job; leaving deployment credentials for retry.' >&2
        exit 1
    fi
else
    echo "First-boot setup is incomplete; leaving the boot job in place." >&2
    exit 1
fi
