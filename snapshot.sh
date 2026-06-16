#!/bin/bash
set -e  # stop immediately if any command fails

set -a # automatically export variables
source .env
set +a

if [[ -z "${SNAPSHOT_DL_DIR:-}" ]]; then
  echo "expected SNAPSHOT_DL_DIR to be set" 1>&2
  exit 1
fi
if [[ -z "${SNAPSHOT_EXT_DIR:-}" ]]; then
  echo "expected SNAPSHOT_EXT_DIR to be set" 1>&2
  exit 1
fi

LATEST_SNAPSHOT=$(curl -s https://mainnet-reth-$SNAPSHOT_TYPE-snapshots.base.org/latest)
echo "Latest snapshot: $LATEST_SNAPSHOT"

if [[ -z "${LATEST_SNAPSHOT:-}" ]]; then
  echo "unable to get latest snapshot" 1>&2
  exit 1
fi

# download the pruned snapshot using aria2
echo "Step 1: downloading snapshot..."
apt install -y aria2
aria2c -c -x 16 -s 16 -d $SNAPSHOT_DL_DIR "https://mainnet-reth-$SNAPSHOT_TYPE-snapshots.base.org/$LATEST_SNAPSHOT"
echo "Snapshot downloaded to $SNAPSHOT_DL_DIR"

sleep 20

# unpack the snapshot
echo "Step 2: extracting archive..."
tar -I zstd -xvf $SNAPSHOT_DL_DIR/$LATEST_SNAPSHOT -C $SNAPSHOT_EXT_DIR
echo "Snapshot extracted to $SNAPSHOT_EXT_DIR"

sleep 20

# move snapshot data to host data dir
echo "Step 3: moving files..."
mkdir -p -m 775 $HOST_DATA_DIR
mv $SNAPSHOT_EXT_DIR/snapshots/mainnet/download/* $HOST_DATA_DIR
echo "Snapshot moved to $HOST_DATA_DIR"

sleep 20

echo "Step 4: starting docker compose..."
docker compose up -d --build

echo "DONE!"
