#!/usr/bin/env bash
set -euo pipefail

# New scanners link directly through the Sensor Proxy used by TVSAPI.
# The linking key is supplied by the private deployment.env on the USB.
proxy_host=canarytrap.tail92b79.ts.net
proxy_port=9443
ca_path=/etc/nessus-sensor-proxy-ca.pem
nessus_cli=/opt/nessus/sbin/nessuscli

if [[ ${EUID} -ne 0 ]]; then
    echo 'Nessus setup must run as root.' >&2
    exit 1
fi
if [[ ! ${TENABLE_LINK_KEY:-} =~ ^[A-Za-z0-9]{64}$ ]]; then
    echo 'TENABLE_LINK_KEY must be a 64-character Tenable scanner linking key.' >&2
    exit 1
fi
if [[ ! -s $ca_path ]] || ! grep -q -- '-----BEGIN CERTIFICATE-----' "$ca_path"; then
    echo "Missing Sensor Proxy CA certificate at $ca_path." >&2
    exit 1
fi

scanner_name=$(hostname -s)
if [[ ${scanner_name,,} =~ ^ctdropbox([0-9]+)$ ]]; then
    scanner_name="CTDropbox${BASH_REMATCH[1]}"
else
    echo 'Scanner hostname must be CTDropbox followed by a number.' >&2
    exit 1
fi

if ! dpkg-query -W -f='${Status}' nessus 2>/dev/null | grep -Fxq 'install ok installed'; then
    json=$(curl -fsSL https://www.tenable.com/downloads/api/v2/pages/nessus)
    download_url=$(jq -er '[.releases.latest | to_entries[].value[] |
        select((.file | ascii_downcase | contains("debian")) and
               (.file | ascii_downcase | contains("amd64"))) | .file_url][0] // empty' <<<"$json")
    package=$(mktemp --suffix=.deb)
    trap 'rm -f "$package"' EXIT
    echo 'Downloading the latest Nessus Debian amd64 package.'
    curl -fsSL "$download_url" -o "$package"
    dpkg -i "$package"
    rm -f "$package"
    trap - EXIT
fi

systemctl enable --now nessusd.service

status=$("$nessus_cli" managed status 2>&1 || true)
if [[ $status == *"Linked to $proxy_host:$proxy_port"* ]]; then
    echo 'Nessus is already linked through Sensor Proxy.'
elif [[ $status == *'Linked to '* ]]; then
    echo 'Nessus is linked to a different manager; refusing to change it.' >&2
    exit 1
else
    # Check the staged CA and tailnet route before changing scanner state.
    curl -fsS --retry 5 --retry-delay 10 --cacert "$ca_path" -o /dev/null \
        --connect-timeout 10 --max-time 20 "https://$proxy_host:$proxy_port/"
    if ! "$nessus_cli" managed link \
        --key="$TENABLE_LINK_KEY" --host="$proxy_host" --port="$proxy_port" \
        --name="$scanner_name" --ca-path="$ca_path" >/dev/null 2>&1; then
        echo 'Nessus could not link through Sensor Proxy; first-boot setup will retry.' >&2
        exit 1
    fi
fi

for ((attempt = 1; attempt <= 12; attempt++)); do
    status=$("$nessus_cli" managed status 2>&1 || true)
    if [[ $status == *"Linked to $proxy_host:$proxy_port"* ]] &&
       systemctl is-active --quiet nessusd.service; then
        echo 'Nessus is active and linked through Sensor Proxy.'
        exit 0
    fi
    sleep 10
done

echo 'Nessus link or service was not ready after two minutes; first-boot setup will retry.' >&2
exit 1
