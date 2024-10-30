#!/bin/bash

# Ensure gcloud is installed
if ! command -v gcloud &> /dev/null
then
    echo "gcloud could not be found, please install it first."
    exit 1
fi

# Function to delete regional static IP addresses
delete_regional_static_ips() {
    # Get all regions
    regions=$(gcloud compute regions list --format="value(name)")

    for region in $regions; do
        echo "Scanning region: $region"

        # List regional static IPs in the region
        ips=$(gcloud compute addresses list --filter="region:($region) status=RESERVED" --format="value(name,addressType)")

        if [ -z "$ips" ]; then
            echo "No regional static IPs found in region: $region"
        else
            while IFS= read -r ip; do
                ip_name=$(echo $ip | cut -d' ' -f1)
                ip_type=$(echo $ip | cut -d' ' -f2)
                echo "Found regional static IP: $ip_name ($ip_type) in region: $region"
                echo "Deleting regional static IP: $ip_name in region: $region"
                gcloud compute addresses delete $ip_name --region=$region --quiet
            done <<< "$ips"
        fi
    done
}

# Function to delete global static IP addresses
delete_global_static_ips() {
    echo "Scanning for global static IPs"

    # List global static IPs
    ips=$(gcloud compute addresses list --global --filter="status=RESERVED" --format="value(name,addressType)")

    if [ -z "$ips" ]; then
        echo "No global static IPs found"
    else
        while IFS= read -r ip; do
            ip_name=$(echo $ip | cut -d' ' -f1)
            ip_type=$(echo $ip | cut -d' ' -f2)
            echo "Found global static IP: $ip_name ($ip_type)"
            echo "Deleting global static IP: $ip_name"
            gcloud compute addresses delete $ip_name --global --quiet
        done <<< "$ips"
    fi
}

# Execute the functions
delete_regional_static_ips
delete_global_static_ips

echo "Static IP deletion process completed."
