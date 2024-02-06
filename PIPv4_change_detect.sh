#!/bin/bash
# Script that checks if the public ipv4 address has changed

# Vars
ip_file="./.pubip.txt"
ip=$(curl -s http://ipv4.icanhazip.com)
mail_receiver="example@gmail.com"

# Cloudflare vars
take_action=true
zone_id="zone_id"
api_token="api_token"
DOMAINS=(mail.julete.xyz)

# Make sure script isn't running as root
if [ $EUID -eq 0 ]; then
    echo "NO NEED TO RUN AS ROOT!"
    exit 1
fi

# Wait for the network to be up
counter=1
until ping -q -c1 -W1 1.1.1.1   || [ "$counter" -gt 12 ]; do
    echo "Waiting for network. Attempt ($counter/12)."
    sleep 10
    counter=$((counter+1))
done

# Check if the network is up, if not, exit
if [ "$counter" -gt 12 ]; then
    echo "Network not available. Exiting..."
    exit 1
fi

# Check if the $IP is empty
if [ -z "$ip" ]; then
    echo "Failed to get the public ip. Maybe wait for the next run. Exiting..."
    exit 1
fi

# Check if the file exists
if [ -f $ip_file ]; then
    chmod 644 $ip_file
    old_ip=$(cat $ip_file)

    # Check if the ip has changed
    if [ "$ip" != "$old_ip" ]; then
	    changed=true
        # Save the new ip
        echo "$ip" > $ip_file
        # Send an email
        echo "The public ip has changed to $ip" | mail -s "Public ip changed" "$mail_receiver"
    else
        echo "The public ip hasn't changed. Exiting..."
        exit 0
    fi

else
    # Save the ip
    echo "Creating $ip_file for the next run. Exiting without errors..."
    echo "$ip" > $ip_file
    chmod 644 $ip_file
    exit 0
fi

if [[ $take_action = true && $changed = true ]]; then
    encountered_error=false

    # Modify cludflare DNS record for each domain
    for i in "${DOMAINS[@]}"; do

        if nslookup $i | grep NXDOMAIN ; then
            echo "Domain $i not found, skipping"
            continue
        fi

	    # Extract all the zone data and store it in variables
	    record_data=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=A&name=$i" \
                        -H "Content-Type: application/json" \
	                    -H "Authorization: Bearer $api_token" | jq . )

        record_id=$(echo "$record_data" | grep '"id":' | cut -d '"' -f 4)
        type=$(echo "$record_data" | grep '"type":' | cut -d '"' -f 4)
        name=$(echo "$record_data" | grep '"name":' | cut -d '"' -f 4)
        ttl=$(echo "$record_data" | grep '"ttl":' | cut -d ":" -f 2 | cut -d "," -f 1 | cut -d " " -f 2)
        proxied=$(echo "$record_data" | grep '"proxied":' | cut -d ":" -f 2 | cut -d "," -f 1 | cut -d " " -f 2)

        echo ""
        echo " ** THIS IS THE RECORD DATA FOR: $i"

        echo "THIS IS THE RECORD ID: $record_id"
        echo "THIS IS THE TYPE: $type"
        echo "THIS IS THE NAME: $name"
        echo "THIS IS THE CONTENT: $ip"
        echo "THIS IS THE TTL: $ttl"
        echo "THIS IS THE PROXIED: $proxied"

	    # Update the ip of the record using the Cloudflare API
	    update_request=$(curl -X PUT \
            --url "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $api_token" \
            --data '{"type":"'$type'","name":"'$name'","content":"'$ip'","ttl":'$ttl',"proxied":'$proxied'}' | jq .)

        # Check if the update was successful
        if grep '"success":true,' "$update_request" ; then
            echo "Successfully updated DNS record for $i"
        else
            encountered_error=true
            echo "Failed to update DNS record for $i"
        fi        

    done

	if [ $encountered_error = true ]; then
        # Send an email
    	echo "One or more DNS records failed to update" | mail -s "Failed to update DNS records" "$mail_receiver"
    	exit 1
	fi
fi

exit 0
