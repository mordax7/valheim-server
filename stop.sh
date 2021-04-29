#!/usr/bin/env bash

set -e
set -o pipefail

if [[ -z "$1" ]]; then
  echo "Please pass on an API token as a single argument"
  exit
fi

servers=$(curl -s -H "Authorization: Bearer $1" 'https://api.hetzner.cloud/v1/servers' | jq '.servers | select(.[].name|test("valheim"))' --raw-output)
numberOfServers=$(echo $servers | jq '. | length')

if [[ "$numberOfServers" != "1" ]]; then
  echo "There is not exactly one valheim server running. Exiting..."
  exit
fi

serverId=$(echo $servers | jq '.[].id')

echo "Stopping the server..."
curl -s -X POST -H "Authorization: Bearer $1" "https://api.hetzner.cloud/v1/servers/$serverId/actions/shutdown" > /dev/null

echo "Waiting for the server to stop"
until [[ $serverStatus == "off" ]]; do
  echo "Checking..."
  serverStatus=$(curl -s \
          -H "Authorization: Bearer $1" \
          "https://api.hetzner.cloud/v1/servers/$serverId" | jq '.server.status' --raw-output)
  sleep 2
done

echo "Server stopped successfully, taking a snapshot"
snapshotDetails=$(curl \
        -s \
        -X POST \
        -H "Authorization: Bearer $1" \
        -H "Content-Type: application/json" \
        -d '{"description":"valheim-'"$(date +%F_%T)"'","type":"snapshot"}' \
        "https://api.hetzner.cloud/v1/servers/$serverId/actions/create_image")

snapshotId=$(echo $snapshotDetails | jq '.image.id')

echo "Waiting for the snapshot to be created"
until [[ $snapshotStatus == "available" ]]; do
  echo "Checking..."
  snapshotStatus=$(curl \
    -s \
    -H "Authorization: Bearer $1" \
    "https://api.hetzner.cloud/v1/images/$snapshotId" | jq '.image.status' --raw-output)
  sleep 10
done

echo "Snapshot created, verifying that there are at least two valheim snapshots"

echo "Deleting the server $(curl -H "Authorization: Bearer $1" "https://api.hetzner.cloud/v1/servers/$serverId" | jq '.')"
read -r -p "Is this okay? [y/N] " deleteServer
case "$deleteServer" in
    [yY][eE][sS]|[yY])
        curl -X DELETE -H "Authorization: Bearer $1" "https://api.hetzner.cloud/v1/servers/$serverId"
        ;;
    *)
        exit
        ;;
esac

snapshots=$(curl -s -H "Authorization: Bearer $1" 'https://api.hetzner.cloud/v1/images?type=snapshot')
snapshotIdToDelete=$(echo "$snapshots" | jq '.images[] | select(.description|test("valheim")) | .id' | sort | head -n 1)

echo "Will delete the snapshot with the ID $snapshotIdToDelete. It is called $(curl -s -H "Authorization: Bearer $1" "https://api.hetzner.cloud/v1/images/$snapshotIdToDelete" | jq '.image.description')"
echo "and was created $(curl -s -H "Authorization: Bearer $1" "https://api.hetzner.cloud/v1/images/$snapshotIdToDelete" | jq '.image.created')"
read -r -p "Is this okay? [y/N] " deleteSnapshot
case "$deleteSnapshot" in
    [yY][eE][sS]|[yY])
        curl \
          -X DELETE \
          -H "Authorization: Bearer $1" \
          "https://api.hetzner.cloud/v1/images/$snapshotIdToDelete"
        ;;
    *)
        exit
        ;;
esac

