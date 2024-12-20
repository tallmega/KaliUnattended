export SELFIP=$(ip -4 addr show eth0 | grep -oP "(?<=inet )\d+\.\d+\.\d+\.\d+")
# Check if DOMAIN was successfully extracted
if [ -n "$SELFIP" ]; then
    echo "SELFIP: $SELFIP"
fi

# Extract the last domain from the 'search' line in /etc/resolv.conf
DOMAIN=$(grep -oP '(?<=search ).*' /etc/resolv.conf | awk '{print $NF}')

# Check if DOMAIN was successfully extracted
if [ -n "$DOMAIN" ]; then
    echo "DOMAIN: $DOMAIN"
else
    echo "Domain not found in /etc/resolv.conf"
fi

# Ensure DOMAIN is set
if [ -z "$DOMAIN" ]; then
    echo "DOMAIN not identified."
fi

# Perform nslookup and get the first two responses
NSLOOKUP_RESULTS=$(nslookup "$DOMAIN" | grep -oP "(?<=Address: ).*")

# Read the results into variables
DC1=$(echo "$NSLOOKUP_RESULTS" | sed -n '1p')
DC2=$(echo "$NSLOOKUP_RESULTS" | sed -n '2p')

# Check and display the results
if [ -n "$DC1" ]; then
    echo "DC1: $DC1"
else
    echo "No DC response found (DC1)"
fi

if [ -n "$DC2" ]; then
    echo "DC2: $DC2"
else
    echo "No second DC response found (DC2)"
fi
