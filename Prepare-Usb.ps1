# Run after Rufus writes the official amd64 Installer ISO in ISO Image mode.
param(
    [Parameter(Mandatory = $true)]
    [string]$UsbRoot,
    [string]$PreseedPath = (Join-Path $PSScriptRoot 'preseed_installer.local.cfg'),
    [string]$SecretsPath = (Join-Path $PSScriptRoot 'deployment.env')
)

$ErrorActionPreference = 'Stop'
function Convert-ToLf([string]$value) {
    return $value.Replace("`r`n", "`n").Replace("`r", "`n")
}

$root = (Resolve-Path -LiteralPath $UsbRoot).Path
$defaultPreseed = Join-Path $root 'simple-cdd/default.preseed'
$grubConfig = Join-Path $root 'boot/grub/grub.cfg'
$installerKernel = Join-Path $root 'install.amd/vmlinuz'
$installerInitrd = Join-Path $root 'install.amd/initrd.gz'
$required = @($defaultPreseed, $grubConfig, $installerKernel, $installerInitrd, $PreseedPath, $SecretsPath)
foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing $path. Use the full amd64 Installer ISO in Rufus ISO Image mode."
    }
}

$preseed = Convert-ToLf ([System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $PreseedPath).Path))
$secrets = Convert-ToLf ([System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $SecretsPath).Path))
# Older local preseeds set an empty hostname. Supply a valid default, then
# clear its seen flag so netcfg asks for the hostname inside the installer.
$preseed = [regex]::Replace($preseed, '(?m)^d-i netcfg/(?:get_hostname|hostname) (?:string[ \t]*(?:CTDropbox1|CTDropbox)?|seen false[ \t]*)\n', '')
if ($preseed -match '(?m)^d-i netcfg/(?:get_hostname|hostname)\s') {
    throw 'Remove custom netcfg hostname settings from the preseed; the installer asks for the hostname.'
}
$preseed = "d-i netcfg/get_hostname string CTDropbox1`nd-i netcfg/get_hostname seen false`n" + $preseed.TrimStart()
$partmanStart = 'd-i partman/early_command string \'
if (-not $preseed.Contains('debconf-set debconf/priority critical')) {
    if (-not $preseed.Contains($partmanStart)) {
        throw 'The selected preseed is missing the partman early command.'
    }
    $preseed = $preseed.Replace($partmanStart, "$partmanStart`n    debconf-set debconf/priority critical; \`n")
}
$password = [regex]::Match($preseed, '(?m)^d-i passwd/user-password password (.+)$').Groups[1].Value.Trim()
$passwordAgain = [regex]::Match($preseed, '(?m)^d-i passwd/user-password-again password (.+)$').Groups[1].Value.Trim()
if (-not $password -or $password -eq 'changeme' -or $password -ne $passwordAgain) {
    throw 'Set the same non-default Kali user password in both lines of your local preseed copy.'
}
foreach ($setting in @('d-i apt-setup/use_mirror boolean false', 'd-i pkgsel/upgrade select none', 'in-target /bin/sh /root/late-upgrade.sh')) {
    if (-not $preseed.Contains($setting)) {
        throw "The selected preseed is missing: $setting"
    }
}
foreach ($name in @('ACTIVATION_CODE_1', 'ACTIVATION_CODE_2', 'ACTIVATION_CODE_3', 'TAILSCALE_AUTH_KEY')) {
    if ($secrets -notmatch "(?m)^$name='[^']+'[ \t]*$") {
        throw "Set $name as a single-quoted value in deployment.env."
    }
}
if ($secrets -match 'replace-me') {
    throw 'Replace every placeholder in deployment.env before preparing the USB.'
}

$needle = 'preseed/file=/cdrom/simple-cdd/default.preseed'
$replacement = 'auto=true priority=critical preseed/file=/cdrom/preseed.cfg'
$grubText = [System.IO.File]::ReadAllText($grubConfig)
if (-not $grubText.Contains($needle) -and -not $grubText.Contains($replacement)) {
    throw "Expected boot parameter was not found in $grubConfig; this ISO layout needs review."
}

$blockStart = '# BEGIN KaliUnattended UEFI entry'
$blockEnd = '# END KaliUnattended UEFI entry'
if ($grubText.Contains($blockStart) -ne $grubText.Contains($blockEnd)) {
    throw "Incomplete KaliUnattended boot entry in $grubConfig. Restore the original ISO files before retrying."
}
$customGrub = @'
# BEGIN KaliUnattended UEFI entry
menuentry 'Kali unattended install (hostname in installer)' --id=kaliunattended {
    linux /install.amd/vmlinuz net.ifnames=0 auto=true priority=high preseed/file=/cdrom/preseed.cfg simple-cdd/profiles=kali desktop=xfce vga=788 --- quiet
    initrd /install.amd/initrd.gz
}
set default=kaliunattended
set timeout_style=countdown
set timeout=2
# END KaliUnattended UEFI entry
'@

$utf8 = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText((Join-Path $root 'preseed.cfg'), $preseed.Trim() + "`n", $utf8)

$deployment = Join-Path $root 'deployment'
New-Item -ItemType Directory -Path $deployment -Force | Out-Null
foreach ($name in @('late-upgrade.sh', 'preseed_post.sh', 'logon-script.sh')) {
    $scriptText = Convert-ToLf ([System.IO.File]::ReadAllText((Join-Path $PSScriptRoot $name)))
    [System.IO.File]::WriteAllText((Join-Path $deployment $name), $scriptText, $utf8)
}
[System.IO.File]::WriteAllText((Join-Path $deployment 'deployment.env'), $secrets.TrimEnd() + "`n", $utf8)

$configFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'boot/grub') -Filter '*.cfg' -File -Recurse)
$isolinux = Join-Path $root 'isolinux'
if (Test-Path -LiteralPath $isolinux -PathType Container) {
    $configFiles += @(Get-ChildItem -LiteralPath $isolinux -Filter '*.cfg' -File -Recurse)
}
foreach ($file in $configFiles) {
    $text = [System.IO.File]::ReadAllText($file.FullName)
    # Undo the boot-parameter replacement made by earlier script versions.
    if ($text.Contains($replacement)) {
        [System.IO.File]::WriteAllText($file.FullName, $text.Replace($replacement, $needle), $utf8)
    }
}
if ($grubText.Contains($blockStart)) {
    $start = $grubText.IndexOf($blockStart)
    $endMarker = $grubText.IndexOf($blockEnd, $start)
    if ($endMarker -lt 0) {
        throw "Malformed KaliUnattended boot entry in $grubConfig. Restore the original ISO files before retrying."
    }
    $end = $endMarker + $blockEnd.Length
    $grubText = $grubText.Remove($start, $end - $start)
}
$grubText = (Convert-ToLf $grubText).Replace($replacement, $needle).TrimEnd() + "`n`n" + $customGrub.Trim() + "`n"
[System.IO.File]::WriteAllText($grubConfig, $grubText, $utf8)

Write-Host "USB prepared at $root. UEFI boots the installer automatically; enter a unique hostname when Kali asks."
