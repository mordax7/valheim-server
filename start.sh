#!/usr/bin/env bash

set -e
set -o pipefail

if [[ -z "$1" ]]; then
  echo "Please pass on an API token as a single argument"
  exit
fi

numberOfServers=$(curl -s -H "Authorization: Bearer $1" 'https://api.hetzner.cloud/v1/servers' | jq '.servers | select(.[].name|test("valheim"))' --raw-output)

if [[ -n "$numberOfServers"  ]]; then
  echo "There are servers running, please verify manually!"
  echo "The running server(s) is/are called"
  curl -s -H "Authorization: Bearer $1" 'https://api.hetzner.cloud/v1/servers' | jq '.servers[].name' --raw-output
  exit
fi

snapshots=$(curl -s -H "Authorization: Bearer $1" 'https://api.hetzner.cloud/v1/images?type=snapshot')
latestSnapshotId=$(echo "$snapshots" | jq '.images[] | select(.description|test("valheim")) | .id' | sort -r | head -n 1)
snapshotDetails=$(curl -s -H "Authorization: Bearer $1" "https://api.hetzner.cloud/v1/images/$latestSnapshotId")

echo "Will create a new server from the following snapshot:"
echo "ID: $(echo "$snapshotDetails" | jq '.image.id')"
echo "Description: $(echo "$snapshotDetails" | jq '.image.description')"

read -r -p "Is this okay? [y/N] " response
case "$response" in
    [yY][eE][sS]|[yY])
        serverDetails=$(curl \
          -s \
          -X POST \
          -H "Authorization: Bearer $1" \
          -H "Content-Type: application/json" \
          -d '{"name":"valheim","location":"nbg1","server_type":"cx41","start_after_create":true,"image":'"${latestSnapshotId}"',"volumes":[],"networks":[],"user_data":"#cloud-config\nruncmd:\n- [touch, /root/cloud-init-worked]\n","labels":{},"automount":false}' \
          'https://api.hetzner.cloud/v1/servers')
        ;;
    *)
        exit
        ;;
esac

echo "Successfully created server $(echo "$serverDetails" | jq '.server.name') with IP $(echo "$serverDetails" | jq '.server.public_net.ipv4.ip') and root password $(echo "$serverDetails" | jq '.root_password')"

