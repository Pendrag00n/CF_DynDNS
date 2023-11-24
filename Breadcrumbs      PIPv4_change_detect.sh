#!/bin/bash
# Script that checks if the public IPv4 address has changed

# Vars
IP_FILE="./.pubip.txt"
IP=$(curl -s http://ipv4.icanhazip.com)
mail_receiver="example@gmail.com"

# Cloudflare vars
take_action="false"
ZONE_ID="zoneide"
RECORD_ID="RECORD_ID"
EMAIL="juliofelipeHI@gmail.com"
ACCOUNT_ID="accountid"
API_TOKEN="apitoken"
DOMAINS=(sub.domain.com sub2.domain.com sub3.domain.com)

# Wait for the network to be up
counter=0
until ping -c1 -W1 1.1.1.1 || [ "$counter" -gt 12 ]; do
    echo "Waiting for network"
    sleep 10
    counter=$((counter+1))
done

# Check if the network is up, if not, exit
if [ "$counter" -gt 12 ]; then
    echo "Network not available"
    exit 1
fi

# Check if the file exists
if [ -f $IP_FILE ]; then
    # Get the old IP
    OLD_IP=$(cat $IP_FILE)
    # Check if the IP has changed
    if [ "$IP" != "$OLD_IP" ]; then
        # Save the new IP
        echo "$IP" > $IP_FILE
        # Send an email
        echo "The public IP has changed to $IP" | mail -s "Public IP changed" "$mail_receiver"
    fi
else
        # Save the IP
        echo "Creating $IP_FILE"
        echo "$IP" > $IP_FILE
fi
if [ "$take_action" = "true" ]; then
    encountered_error="false"

    # Modify cludflare DNS record for each domain
    for i in "${DOMAINS[@]}"; do
        if nslookup $i | grep NXDOMAIN ; then
            echo "Domain $i not found, skipping"
            continue
        fi

        curl -X PUT \
        --url "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
        -H "X-Auth-Email: $EMAIL" \
        -H "X-Auth-Key: $API_TOKEN" \
        -H "Content-Type: application/json" \
        --data '{"type":"A","name":"'$i'","content":"'$IP'", "ttl":"", "proxied":""}'

        if [ $? -ne 0 ]; then
            encountered_error="true"
        else
            echo "DNS record for $i updated. Now pointing to $IP"
        fi
    done
fi
if [ "$encountered_error" = "true" ]; then
    # Send an email
    echo "One or more DNS records failed to update" | mail -s "Failed to update DNS records" "$mail_receiver"
    exit 1
fi
exit 0
