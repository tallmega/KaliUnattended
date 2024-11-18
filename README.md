Preseed file and late_command script file for Kali Linux installs.

In the preseed.cfg file update [password], [key1], [key2], [key3], [tskey], [URL to preseed_post.sh]:

	d-i passwd/user-password password <password>
 	d-i passwd/user-password-again password <password>
	d-i preseed/late_command string \
		in-target wget https://raw.githubusercontent.com/tallmega/preseed/refs/heads/main/preseed_post.sh -O /tmp/preseed_post.sh >> /tmp/preseed_log 2>&1 || true; \
   		in-target chmod +x /tmp/preseed_post.sh >> /tmp/preseed_log 2>&1 || true; \
    	in-target bash /tmp/preseed_post.sh "<key1>" "<key2>" "<key3>" "<key4>" >> /tmp/preseed_log 2>&1 || true;

To build ISO:

	sudo apt update
	sudo apt install -y git live-build cdebootstrap devscripts simple-cdd
	git clone https://gitlab.com/kalilinux/build-scripts/live-build-config.git
	cp <YOUR PRESEED FILE> ./live-build-config/kali-config/common/includes.installer/preseed.cfg
	./live-build-config/build.sh --installer -vv

 Then when ready to write ISO to USB (its sda for me, PLEASE don't overwrite your OS disk):
 		
	 sudo dd bs=4M if=./images/kali-linux-rolling-installer-amd64.iso of=/dev/sda status=progress oflag=sync
