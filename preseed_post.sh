#!/bin/bash

# Validate input arguments
if [ $# -ne 4 ]; then
    echo "Usage: $0 <activation_code1> <activation_code2> <activation_code3> <tsauthkey>"
    exit 1
fi

# Assign input arguments to variables
activation_code1=$1
activation_code2=$2
activation_code3=$3
tsauthkey=$4

# Configure sudoers
echo "kali    ALL=(ALL:ALL) NOPASSWD:ALL" | tee -a /etc/sudoers

# Install necessary packages
apt-get update
apt-get install -y airgeddon unattended-upgrades mitm6 jq

# Configure Airgeddon
sed -i 's/AIRGEDDON_WINDOWS_HANDLING=xterm/AIRGEDDON_WINDOWS_HANDLING=tmux/' /usr/share/airgeddon/.airgeddonrc

# Enable and start SSH service
systemctl enable ssh.service

# Enable unattended-upgrades
systemctl enable unattended-upgrades

# Fetch the latest Nessus release JSON data
json=$(wget -qO- https://www.tenable.com/downloads/api/v2/pages/nessus)

# Extract the download URL for the latest Debian package
download_url=$(echo "$json" | jq -r '.releases.latest | to_entries[] | .value[] | select(.file | contains("debian")) | .file_url')

# Check if a valid URL was found
if [ -n "$download_url" ] && [ "$download_url" != "null" ]; then
    echo "Downloading the latest Nessus Debian package from: $download_url"
    wget -O Nessus.deb "$download_url"

    # Install the downloaded package
    sudo dpkg -i Nessus.deb

    # Fetch the hostname and extract the numeric part
    hostname=$(hostname)
    numeric_part=$(echo "$hostname" | grep -oE '[0-9]+')

    # Determine the activation code based on the numeric part
    if [ -n "$numeric_part" ]; then
        if [ "$numeric_part" -lt 10 ]; then
            /opt/nessus/sbin/nessuscli fetch --register $activation_code1
        elif [ "$numeric_part" -ge 11 ] && [ "$numeric_part" -le 20 ]; then
            /opt/nessus/sbin/nessuscli fetch --register $activation_code2
        elif [ "$numeric_part" -ge 21 ] && [ "$numeric_part" -le 30 ]; then
            /opt/nessus/sbin/nessuscli fetch --register $activation_code3
        else
            echo "Hostname numeric part out of expected range. Exiting."
            exit 1
        fi
    else
        echo "Unable to determine numeric part of hostname. Exiting."
    fi

    # Add a user with username 'Nessus' and password 'Nessus'
    echo -e "Nessus\nNessus\ny\n\ny\n\n" | /opt/nessus/sbin/nessuscli adduser Nessus

    # Start and enable the Nessus service
    sudo systemctl start nessusd
    sudo systemctl enable nessusd

    # Clean up
    rm Nessus.deb
else
    echo "Failed to find the download URL for the latest Nessus Debian package."
    exit 1
fi

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

# Install and configure Tailscale
curl -fsSL https://tailscale.com/install.sh -o install.sh
sh install.sh
tailscale up --auth-key=$tsauthkey --ssh=true

# upgrade packages
sudo apt-get upgrade -y
