#!/bin/bash


# The full Installer USB copies these values to the installed system. Keep
# argument support for systems installed with the older netboot preseed.
if [ $# -eq 0 ]; then
    if [ ! -r /root/deployment.env ]; then
        echo "Missing /root/deployment.env" >&2
        exit 1
    fi
    . /root/deployment.env
    activation_code1=$ACTIVATION_CODE_1
    activation_code2=$ACTIVATION_CODE_2
    activation_code3=$ACTIVATION_CODE_3
    tsauthkey=$TAILSCALE_AUTH_KEY
elif [ $# -eq 4 ]; then
    activation_code1=$1
    activation_code2=$2
    activation_code3=$3
    tsauthkey=$4
else
    echo "Usage: $0 [<activation_code1> <activation_code2> <activation_code3> <tsauthkey>]" >&2
    exit 1
fi

if [ -z "$activation_code1" ] || [ -z "$activation_code2" ] || [ -z "$activation_code3" ] || [ -z "$tsauthkey" ]; then
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

nessus_cli=/opt/nessus/sbin/nessuscli
nessus_registered=/root/.nessus-activation-complete

# Select the activation code from the hostname suffix. Do not register again
# if first-boot setup has to retry after a successful registration.
ensure_nessus_registered() {
    local numeric_part activation_code

    [ -f "$nessus_registered" ] && return 0
    numeric_part=$(hostname -s | grep -oE '[0-9]+$') || {
        echo 'Hostname must end in a number to select a Nessus activation code.' >&2
        return 1
    }
    if [ "$numeric_part" -ge 1 ] && [ "$numeric_part" -le 10 ]; then
        activation_code=$activation_code1
    elif [ "$numeric_part" -ge 11 ] && [ "$numeric_part" -le 20 ]; then
        activation_code=$activation_code2
    elif [ "$numeric_part" -ge 21 ]; then
        activation_code=$activation_code3
    else
        echo 'Hostname numeric suffix must be at least 1.' >&2
        return 1
    fi

    "$nessus_cli" fetch --register "$activation_code" || return 1
    touch "$nessus_registered"
}

# The local API reports ready only after the initial plugin load finishes.
wait_for_nessus_ready() {
    local attempt

    for ((attempt = 0; attempt < 180; attempt++)); do
        if curl -sk --max-time 5 https://127.0.0.1:8834/server/status |
            python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(not (d.get("status") == "ready" and d.get("pluginData") is True))' 2>/dev/null; then
            return 0
        fi
        sleep 10
    done

    echo 'Nessus did not finish loading plugins within 30 minutes' >&2
    return 1
}

# Wait for Nessus to initialize its database before creating the login.
# lsuser also makes this safe to retry on a later boot if setup was interrupted.
ensure_nessus_user() {
    local attempt users adduser_result

    for ((attempt = 1; attempt <= 80; attempt++)); do
        if users=$("$nessus_cli" lsuser 2>&1) &&
           ! printf '%s\n' "$users" | grep -Fqi 'global.db is not ready yet'; then
            if printf '%s\n' "$users" | grep -Fxq 'Nessus'; then
                echo "Verified Nessus account exists."
                return 0
            fi

            # adduser needs a terminal for its prompts. Keep the transcript
            # private because it can contain the password echoed by the pty.
            if ! adduser_result=$(printf 'Nessus\nNessus\ny\n\ny\n' |
                script -qec "$nessus_cli adduser Nessus" /dev/null) ||
               [[ "$adduser_result" != *"This user will have 'system administrator' privileges"* ]] ||
               [[ "$adduser_result" != *"User added"* ]]; then
                echo "Nessus account creation failed on attempt $attempt." >&2
            elif users=$("$nessus_cli" lsuser 2>&1) &&
               printf '%s\n' "$users" | grep -Fxq 'Nessus'; then
                echo "Created and verified Nessus account."
                return 0
            fi
        fi

        if [ "$attempt" -lt 80 ]; then
            echo "Waiting for Nessus database/account (attempt $attempt of 80)..."
            sleep 15
        fi
    done

    echo "Nessus account was not verified after 20 minutes." >&2
    return 1
}

# Fetch the latest Nessus release JSON data
json=$(wget -qO- https://www.tenable.com/downloads/api/v2/pages/nessus)

# Extract the download URL for the latest Debian package
download_url=$(echo "$json" | jq -r '.releases.latest | to_entries[] | .value[] | select(.file | contains("debian")) | .file_url')

nessus_setup_ok=false
if [ -n "$download_url" ] && [ "$download_url" != "null" ]; then
    echo "Downloading the latest Nessus Debian package from: $download_url"
    if wget -O Nessus.deb "$download_url" && sudo dpkg -i Nessus.deb; then
        # Register Nessus, wait for plugins, then create its local login.
        if ensure_nessus_registered && systemctl enable --now nessusd.service &&
           { echo 'Waiting for the initial Nessus plugin load...'; wait_for_nessus_ready; } &&
           ensure_nessus_user && systemctl restart nessusd.service &&
           { echo 'Waiting for Nessus after restart...'; wait_for_nessus_ready; } &&
           "$nessus_cli" lsuser &&
           systemctl is-active --quiet nessusd.service; then
            nessus_setup_ok=true
        else
            echo "Nessus setup is incomplete; the first-boot job will retry." >&2
        fi
    else
        echo "Failed to download or install Nessus; the first-boot job will retry." >&2
    fi

    rm -f Nessus.deb
else
    echo "Failed to find the Nessus Debian package URL; the first-boot job will retry." >&2
fi
unset activation_code1 activation_code2 activation_code3

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

# Install and configure Tailscale
curl -fsSL https://tailscale.com/install.sh -o tsinstall.sh
sh tsinstall.sh
tailscale up --auth-key="$tsauthkey" --ssh=true --advertise-tags tag:dropbox

# Upgrade packages. Keep the boot job until the Nessus account is verified.
upgrade_ok=false
if sudo apt-get upgrade -y; then
    upgrade_ok=true
fi

if [ "$upgrade_ok" = true ] && [ "$nessus_setup_ok" = true ]; then
    # Remove the line containing the script entry from the crontab
    sed -i '\|root/preseed_post.sh|d' /etc/crontab
else
    echo "First-boot setup is incomplete; leaving the boot job in place." >&2
    exit 1
fi
