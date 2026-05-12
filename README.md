## 1. Build Machine Requirements

Use a real Debian or Kali Linux system.

Do **not** use WSL.

```bash
sudo apt update
sudo apt install -y wget cpio gzip xorriso grub-efi-amd64-bin grub-pc-bin mtools
```

---

## 2. Create Working Directory

```
mkdir -p ~/kali-netboot-preseed
cd ~/kali-netboot-preseed
```

---

## 3. Download Kali Netboot Installer

```
wget https://http.kali.org/kali/dists/kali-rolling/main/installer-amd64/current/images/netboot/netboot.tar.gztar -xzf netboot.tar.gz
```

You should now have:

```
debian-installer/amd64/linuxdebian-installer/amd64/initrd.gz
```

---

## 4. Create the Preseed File

Create:

```
nano debian-installer/amd64/preseed.cfg
```
## 5. Embed the Preseed into the Initrd

```
cd ~/kali-netboot-preseed/debian-installer/amd64
gunzip initrd.gz
echo preseed.cfg | cpio -H newc -o -A -F initrd
gzip initrd
```

You should now have:

```
initrd.gz
linux
preseed.cfg
```

---

## 6. Build the Tiny Boot ISO

Create the ISO directory:

```
mkdir -p ~/kali-netboot-iso/boot/grub
cd ~/kali-netboot-iso
cp ~/kali-netboot-preseed/debian-installer/amd64/linux boot/linux
cp ~/kali-netboot-preseed/debian-installer/amd64/initrd.gz boot/initrd.gz
```

Create the GRUB config:

```
cat > boot/grub/grub.cfg <<'EOF'  
set timeout=5  
set default=0  
  
menuentry "Automated Kali Netboot Installer" {  
linux /boot/linux auto=true auto-install/enable=true priority=high vga=788 net.ifnames=0 ---  
initrd /boot/initrd.gz  
}  
EOF
```

Build the ISO:

```
grub-mkrescue -o ~/kali-netboot-preseed.iso ~/kali-netboot-iso
```

---

## 7. Verify the ISO Contents

```
mkdir -p /tmp/kali-netboot-checksudo mount -o loop ~/kali-netboot-preseed.iso /tmp/kali-netboot-checkcat /tmp/kali-netboot-check/boot/grub/grub.cfgls -lh /tmp/kali-netboot-check/boot/linux /tmp/kali-netboot-check/boot/initrd.gzsudo umount /tmp/kali-netboot-check
```

You should see:

```
auto=true auto-install/enable=true priority=high
```

---

## 8. Write the USB

Identify the USB carefully:

```
lsblk
```

Set variables:

```
ISO=~/kali-netboot-preseed.isoUSB=/dev/sdX
```

Write the ISO:

```
sudo umount ${USB}?* 2>/dev/nullsudo wipefs --force -a "$USB"sudo dd if="$ISO" of="$USB" bs=8M oflag=direct conv=fsync status=progresssyncsudo cmp -n "$(stat -c%s "$ISO")" "$ISO" "$USB"
```

If `cmp` returns no output, the USB matches the ISO.

Alternatively, use Rufus > GPT / UEFI
