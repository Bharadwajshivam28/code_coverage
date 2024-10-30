#!/usr/bin/env bash

# Function to log in to gcloud
login() {
  gcloud -q config set project "${project_id}" || exit 1
}

# Function to generate deletion commands for VM instances
generate_vm_deletion_commands() {
  local instances=$(gcloud -q compute instances list --format="table[no-heading](name,zone)")
  local instances_array=($(echo "${instances}" | tr ' ' '\n'))

  if [ -n "${instances}" ]; then
    echo >&2 "Listed ${#instances_array[@]} VM instances"
  fi

  for ((i=0; i < ${#instances_array[@]}; i+=2)); do
    instance=${instances_array[$i]}
    zone=${instances_array[$i+1]}
    echo "gcloud compute instances delete --project ${project_id} -q ${instance} --zone ${zone} ${async_ampersand}"
  done
}

# Function to generate deletion commands for static IPs
generate_static_ip_deletion_commands() {
  local static_ips=$(gcloud -q compute addresses list --format="table[no-heading](name,region)")
  local static_ips_array=($(echo "${static_ips}" | tr '\n' ' '))

  if [ -n "${static_ips}" ]; then
    echo >&2 "Listed ${#static_ips_array[@]} static IP addresses"
  fi

  for ((i=0; i < ${#static_ips_array[@]}; i+=2)); do
    static_ip=${static_ips_array[$i]}
    region=${static_ips_array[$i+1]}
    
    # Check if the static IP is associated with a Cloud Run service
    local service_name=$(gcloud run services list --platform managed --format="value(metadata.name)" --region="${region}" --filter="status=READY --address=${static_ip}")

    if [ -n "${service_name}" ]; then
      # Clear the address from the Cloud Run service first
      echo "gcloud run services update ${service_name} --platform managed --region ${region} --clear-addresses --project ${project_id} ${async_ampersand}"
    fi

    # Delete the static IP address
    echo "gcloud compute addresses delete --project ${project_id} -q ${static_ip} --region ${region} ${async_ampersand}"
  done
}

# Function to generate deletion commands for subnets
generate_subnet_deletion_commands() {
  local networks=$(gcloud -q compute networks list --format="table[no-heading](name)")
  local networks_array=($(echo "${networks}" | tr ' ' '\n'))

  if [ -n "${networks}" ]; then
    echo >&2 "Listed ${#networks_array[@]} networks"
  fi

  for network in "${networks_array[@]}"; do
    echo >&2 "Listing subnets in network ${network}"

    subnets=$(gcloud -q compute networks subnets list --filter="network:${network}" --format="table[no-heading](name,region)")
    subnets_array=($(echo "${subnets}" | tr '\n' ' '))

    if [ -n "${subnets}" ]; then
      echo >&2 "Listed ${#subnets_array[@]} subnets in network ${network}"
    fi

    for ((i=0; i < ${#subnets_array[@]}; i+=2)); do
      subnet=${subnets_array[$i]}
      region=${subnets_array[$i+1]}
      echo "gcloud compute networks subnets delete --project ${project_id} -q ${subnet} --region ${region} ${async_ampersand}"
    done
  done
}


# Function to generate deletion commands for other resources
generate_deletion_commands() {
  local component=$1
  local resource_types=$2
  local use_uri=$3

  if [ "${use_uri}" == "true" ]; then
    identifier_option="--uri"
  else
    identifier_option="--format=table[no-heading](name)"
  fi

  if [ -z "${resource_types}" ]; then
    resource_types_array=("")
  else
    resource_types_array=($(echo "${resource_types}" | tr ' ' '\n'))
  fi

  for resource_type in "${resource_types_array[@]}"; do
    echo >&2 "Listing ${component} ${resource_type}"

    resources=$(gcloud -q "${component}" ${resource_type} list --filter "${filter}" "${identifier_option}")
    resources_array=($(echo "$resources" | tr ' ' '\n'))

    if [ -n "${resources}" ]; then
      echo >&2 "Listed ${#resources_array[@]} ${component} ${resource_type}"
    fi

    for resource in "${resources_array[@]}"; do
      extra_flag=""
      extra_flagvalue=""

      if [ "${resource_type}" == "clusters" ]; then
        if [[ "${resource}" =~ "zones" ]]; then
          extra_flag="--zone"
          extra_flagvalue=$(echo "${resource}" | grep -o 'zones\/[a-z1-9-].*\/clusters' | cut -d'/' -f 2)
          resource=$(echo "${resource}"| rev | cut -d'/' -f 1| rev)
        fi
        if [[ "${resource}" =~ "locations" ]]; then
          extra_flag="--region"
          extra_flagvalue=$(echo "${resource}" | grep -o 'locations\/[a-z0-9-].*\/clusters' | cut -d'/' -f 2)
          resource=$(echo "${resource}"| rev | cut -d'/' -f 1| rev)
        fi
      fi

      echo "gcloud ${component} ${resource_type} delete --project ${project_id} -q ${resource} ${extra_flag} ${extra_flagvalue} ${async_ampersand}"
    done
  done
}

# Function to generate deletion commands for buckets
generate_bucket_deletion_commands() {
  local buckets=$(gsutil ls)
  local buckets_array=($(echo "${buckets}" | tr ' ' '\n'))

  if [ -n "${buckets}" ]; then
    echo >&2 "Listed ${#buckets_array[@]} buckets"
  fi

  for bucket in "${buckets_array[@]}"; do
    echo "gsutil rm -r ${bucket} ${async_ampersand}"
  done
}

# Function to print usage
usage() {
  echo "Usage: $0 -p project_id [-b]"
  echo "  -p Project ID"
  echo "  -b Run commands asynchronously"
  exit 1
}

# Parse command-line arguments
while getopts 'p:bf:' OPTION; do
  case "$OPTION" in
    p)
      project_id="$OPTARG"
      ;;
    b)
      async_ampersand="&"
      ;;
    ?)
      usage
      ;;
  esac
done

if [ -z "${project_id}" ]; then
  usage
fi

# Login to gcloud
login

# Add set -x to the file we create for easier tracking when it is run.
echo "set -x"

# Generate deletion commands for VM instances
generate_vm_deletion_commands

# Generate deletion commands for static IPs
generate_static_ip_deletion_commands

# Generate deletion commands for subnets
generate_subnet_deletion_commands

# Generate deletion commands for other resources
generate_deletion_commands container clusters "true"
generate_deletion_commands compute "target-http-proxies target-https-proxies target-grpc-proxies url-maps backend-services forwarding-rules health-checks http-health-checks https-health-checks instance-templates firewall-rules routes networks target-pools target-tcp-proxies" "true"
generate_deletion_commands sql instances "false"
generate_deletion_commands app "services firewall-rules" "true"
generate_deletion_commands pubsub "subscriptions topics snapshots" "true"
generate_deletion_commands functions "" "false"

# Generate deletion commands for buckets
generate_bucket_deletion_commands

###################################################################################3

#!/bin/bash

# List of Cloud Run regions
REGIONS=(
    "asia-east1"
    "asia-northeast1"
    "asia-northeast2"
    "asia-northeast3"
    "asia-south1"
    "asia-southeast1"
    "asia-southeast2"
    "australia-southeast1"
    "europe-central2"
    "europe-north1"
    "europe-west1"
    "europe-west2"
    "europe-west3"
    "europe-west4"
    "europe-west6"
    "northamerica-northeast1"
    "southamerica-east1"
    "us-central1"
    "us-east1"
    "us-east4"
    "us-west1"
    "us-west2"
    "us-west3"
    "us-west4"
)

# Function to delete a Cloud Run service
delete_service() {
    local service_name=$1
    local region=$2
    echo "Deleting Cloud Run service: $service_name in region $region"
    gcloud run services delete "$service_name" --platform=managed --region="$region" --quiet
    if [ $? -eq 0 ]; then
        echo "Service $service_name deleted successfully."
    else
        echo "Failed to delete service $service_name."
    fi
}

# Iterate over all regions and attempt to delete Cloud Run services
for REGION in "${REGIONS[@]}"; do
    echo "Checking for services in region: $REGION"
    mapfile -t SERVICES < <(gcloud run services list --platform=managed --region="$REGION" --format="value(metadata.name)")
    for service in "${SERVICES[@]}"; do
        delete_service "$service" "$REGION"
    done
done

################################################################################################

#!/bin/bash

# List of regions where Artifact Registry might be deployed
REGIONS=(
    "africa-south1"
    "asia"
    "asia-east1"
    "asia-east2"
    "asia-northeast1"
    "asia-northeast2"
    "asia-northeast3"
    "asia-south1"
    "asia-south2"
    "asia-southeast1"
    "asia-southeast2"
    "australia-southeast1"
    "australia-southeast2"
    "europe"
    "europe-central2"
    "europe-north1"
    "europe-southwest1"
    "europe-west1"
    "europe-west10"
    "europe-west12"
    "europe-west2"
    "europe-west3"
    "europe-west4"
    "europe-west6"
    "europe-west8"
    "europe-west9"
    "me-central1"
    "me-central2"
    "me-west1"
    "northamerica-northeast1"
    "northamerica-northeast2"
    "southamerica-east1"
    "southamerica-west1"
    "us"
    "us-central1"
    "us-east1"
    "us-east4"
    "us-east5"
    "us-south1"
    "us-west1"
    "us-west2"
    "us-west3"
    "us-west4"
)

# Function to delete an Artifact Registry repository
delete_repository() {
    local repo_name=$1
    local region=$2
    echo "Deleting Artifact Registry repository: $repo_name in region $region"
    gcloud artifacts repositories delete "$repo_name" --location="$region" --quiet
    if [ $? -eq 0 ]; then
        echo "Repository $repo_name deleted successfully."
    else
        echo "Failed to delete repository $repo_name."
    fi
}

# Iterate over all regions and attempt to delete Artifact Registry repositories
for REGION in "${REGIONS[@]}"; do
    echo "Checking for repositories in region: $REGION"
    mapfile -t REPOSITORIES < <(gcloud artifacts repositories list --location="$REGION" --format="value(name)")
    for repo in "${REPOSITORIES[@]}"; do
        delete_repository "$repo" "$REGION"
    done
done

####################################################################################################