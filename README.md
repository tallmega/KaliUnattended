Preseed file and late_command script file for Kali Linux installs.

In the preseed.cfg file update [password], [key1], [key2], [key3], [tskey], [URL to preseed_post.sh]:

	d-i preseed/late_command string \
	    wget https://raw.githubusercontent.com/tallmega/preseed/refs/heads/main/preseed_post.sh -O /target/root/preseed_post.sh >> /target/root/preseed_log 2>&1 || true; \
	    chmod +x /target/root/preseed_post.sh >> /target/root/preseed_log 2>&1 || true; \
	    echo -e "\n@reboot root /root/preseed_post.sh \"<key1>\" \"<key2>\" \"<key3>\" \"<tskey>?ephemeral=false&preauthorized=true\"" >> /target/etc/crontab || true;

To build ISO:

	sudo apt update
	sudo apt install -y git live-build cdebootstrap devscripts simple-cdd
	git clone https://gitlab.com/kalilinux/build-scripts/live-build-config.git
	cp <YOUR PRESEED FILE> ./live-build-config/kali-config/common/includes.installer/preseed.cfg
	cd live-build-config	
 	./build.sh --installer -vv

 Then when ready to write ISO to USB (its sda for me, PLEASE don't overwrite your OS disk):
 		
	 sudo dd bs=4M if=./images/kali-linux-rolling-installer-amd64.iso of=/dev/sda status=progress oflag=sync

  ToDo:
  - Set UEFI BIOS options?
  - Make Grub select graphical install by default.
  - Automatically select Locale, Keyboard, Language.
  - Set default hostname and generate a proper one programmatically in post-install script.
