late_command script file for Kali Linux installs.

Preseed file should include:

	d-i preseed/late_command string \
	    in-target export activation_code1="<key1>"; \
	    in-target export activation_code2="<key2>"; \
	    in-target export activation_code3="<key3>"; \
	    in-target export tsauthkey="<tskey>"; \
	    in-target wget <path to preseed_post.sh> -O /tmp/preseed_post.sh; \
	    in-target chmod +x /tmp/preseed_post.sh; \
	    in-target bash /tmp/preseed_post.sh;

To build ISO:

	sudo apt update
	sudo apt install -y git live-build cdebootstrap devscripts simple-cdd
	git clone https://gitlab.com/kalilinux/build-scripts/live-build-config.git
	cp <YOUR PRESEED FILE> ./live-build-config/kali-config/common/includes.installer/
	./build.sh --installer -vv

 Then when ready to write ISO to USB:
 		
	 sudo dd bs=4M if=./images/kali-linux-rolling-installer-amd64.iso of=/dev/sda status=progress oflag=sync
