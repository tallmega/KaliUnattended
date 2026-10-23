# Repeatable Kali installs from Windows

Prepare one USB on Windows, then use it to install any number of machines. The USB runs the **full Kali Installer ISO**, whose installer kernel and driver modules match each other. Near the end of each installation, the installed system downloads the current `kali-rolling` kernel and runs a full upgrade. The next boot uses that newly installed kernel. You can keep using the USB later without rebuilding it just to follow Kali kernel updates.

The older `preseed.cfg` and netboot workflow are not used by this process. Netboot can fail when its installer kernel no longer matches the modules on a rolling mirror.

## Prepare the USB once

Do this on a Windows computer with this repository, Rufus, and an 8 GB or larger USB drive. **Writing the ISO erases the USB.** The eventual Kali installation also erases the first NVMe disk selected by the preseed.

1. Download the **Installer** amd64 ISO from [Kali's official download page](https://www.kali.org/get-kali/). Choose Installer rather than NetInstaller or Live.
2. Insert the USB, open Rufus, select that USB under **Device**, select the downloaded ISO under **Boot selection**, and click **Start**. If Rufus asks between **ISO Image mode** and **DD Image mode**, choose **ISO Image mode**; the preparation script needs to edit files on the USB. Confirm the USB erase prompt and wait until Rufus finishes.
3. In File Explorer, note the USB drive letter (for example, `E:`). Check that the drive contains `E:\simple-cdd\default.preseed`, `E:\boot\grub\grub.cfg`, `E:\install.amd\vmlinuz`, and `E:\install.amd\initrd.gz`, replacing `E:` with your drive letter. These are the files `Prepare-Usb.ps1` expects; if they are missing, check that you used the full amd64 Installer ISO in ISO Image mode.
4. Open this repository folder in File Explorer, type `powershell` in the address bar, and press Enter. Create the two local configuration files:

   ```powershell
   Copy-Item .\preseed_installer.cfg .\preseed_installer.local.cfg
   Copy-Item .\deployment.env.example .\deployment.env
   notepad .\preseed_installer.local.cfg
   notepad .\deployment.env
   ```

  In `preseed_installer.local.cfg`, replace both `changeme` password placeholders with the same Kali user password. Review the `partman/early_command` disk selection: it takes the first `/dev/nvme` disk and **erases it during installation**. Change that command if your intended target is different. In `deployment.env`, replace all four `replace-me` values with your three Nessus activation codes and Tailscale auth key. Keep each value inside single quotes. Both local files are ignored by Git. The password and deployment values are copied to the USB in plaintext; the deployment values also reach the installed system.
5. Run the script from the same PowerShell window, replacing `E:\` with your USB drive root:

   ```powershell
   .\Prepare-Usb.ps1 -UsbRoot 'E:\'
   ```

   Wait for `USB prepared at E:\` before removing the drive. If PowerShell blocks local scripts, run `Set-ExecutionPolicy -Scope Process Bypass` in that window, then retry the command. This policy change lasts only for that PowerShell process.
6. Confirm the USB contains `E:\preseed.cfg`, `E:\deployment\deployment.env`, and `E:\deployment\late-upgrade.sh`. Also check that `E:\boot\grub\grub.cfg` contains `Kali unattended install (hostname in installer)` and `set default=kaliunattended`. Then eject the USB in Windows. The script copies `preseed_post.sh` and `logon-script.sh` and adds an automatic UEFI boot entry that uses `/cdrom/preseed.cfg` with `auto=true priority=high`. The preseed lowers the priority to `critical` before partitioning.

The script leaves the ISO's original `simple-cdd/default.preseed` intact. You can edit your local preseed or credentials and rerun `Prepare-Usb.ps1` on the same USB. Keep the original ISO and a copy of this repository so you can prepare another USB later.

## Install each machine

1. Boot the prepared USB in UEFI mode. A short countdown starts the **Kali unattended install (hostname in installer)** entry automatically. If you interrupt the countdown, select that entry yourself. The stock **Install** entry starts Kali's interactive installer.
2. When Kali's installer asks for the hostname, replace the suggested `CTDropbox1` with a unique name such as `CTDropbox41`, `CTDropbox57`, or `CTDropbox75`, and continue. Reuse the same USB for the next machine and enter its hostname at this installer screen. The number selects the Nessus activation code on first boot: 1–10 use the first key, 11–20 use the second key, and 21 or higher use the third key.
3. Leave the USB connected while installation finishes. The installer uses packages on the USB for its own kernel and the base system. Its late command downloads the current Kali archive keyring, configures `kali-rolling` on the target disk, installs the current `linux-image-amd64`, and runs `apt-get full-upgrade` there. This step requires working internet access and stops the install if it fails.
4. The machine halts when installation finishes. Remove the USB and start the machine from its internal disk. The installed kernel is the one downloaded during that machine's installation. The first-boot script then installs extra tools, Nessus, and Tailscale. It starts Nessus before creating its administrator account, waits up to 20 minutes for the database, and verifies the account with `nessuscli lsuser`. If that check fails, the boot job stays in place to retry on the next boot.

Repeat these steps with the same USB. Kali's mirror is expected to change over time; only the **installed system** consults it, after the installer has loaded its matching drivers from the ISO. A future machine may need a newer Installer ISO if its hardware needs newer installer drivers or the old image can no longer upgrade cleanly. Prepare a USB from a newer full Installer ISO and test it on one machine in that case.

For later installs, refresh `deployment.env` if the Tailscale key or activation codes have changed, then rerun `Prepare-Usb.ps1` against the same USB. Reflashing the ISO is not needed for a credential or script change. If the USB still stops at the stock Kali installer menu or reports `Hostname "" was invalid`, rerun the updated script and check the UEFI entry in `boot\grub\grub.cfg` before booting again.

## Files

- `preseed_installer.cfg`: full Installer preseed template; hostname prompt, local base install, online late upgrade.
- `late-upgrade.sh`: runs inside the target system before installation finishes.
- `preseed_post.sh`: runs on first boot for application setup.
- `Prepare-Usb.ps1`: prepares a Rufus ISO-mode USB on Windows.
- `preseed.cfg`: previous netboot preseed, retained for reference.
