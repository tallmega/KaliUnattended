#!/bin/sh
# Runs in the installed system from d-i's preseed/late_command. The installer
# itself keeps using the kernel and modules bundled on the full Installer ISO.
set -eu

PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none

test -s /usr/share/keyrings/kali-archive-keyring.gpg

# The USB supplied the base packages. Only the installed system uses the live
# rolling repository, so a two-year-old USB can install today's target kernel.
cat > /etc/apt/sources.list <<'EOF'
deb [signed-by=/usr/share/keyrings/kali-archive-keyring.gpg] http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware
EOF
rm -f /etc/apt/sources.list.d/kali.sources

apt-get update
apt-get install -y linux-image-amd64
apt-get -y full-upgrade
apt-get install -y cron openssh-server wget curl git sudo isc-dhcp-client network-manager firmware-misc-nonfree
update-grub

dpkg-query -W -f='${Package} ${Version}\n' linux-image-amd64 > /root/installed-kernel-package.txt
