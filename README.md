![Base](logo.webp)

# Base Node

Base is a secure, low-cost, developer-friendly Ethereum L2 built on Optimism's [OP Stack](https://docs.optimism.io/). This repository contains a Docker build for running a Base node with `base-reth-node` and `base-consensus`.

[![Website base.org](https://img.shields.io/website-up-down-green-red/https/base.org.svg)](https://base.org)
[![Docs](https://img.shields.io/badge/docs-up-green)](https://docs.base.org/)
[![Discord](https://img.shields.io/discord/1067165013397213286?label=discord)](https://base.org/discord)
[![Twitter Base](https://img.shields.io/twitter/follow/Base?style=social)](https://x.com/Base)
[![Farcaster Base](https://img.shields.io/badge/Farcaster_Base-3d8fcc)](https://farcaster.xyz/base)

# Deploying Base Reth Node Guide

## Minimum Requirements
- Modern Multicore CPU 8+ cores (recommended 16+ cores)
- 32GB RAM (64 - 128GB Recommended)
- Storage: 4+ TB NVMe SSD drive locally attached (RAID0) for pruned node (2 * current chain size + snapshot size + 20% buffer) (to accommodate future growth)
- Docker and Docker Compose
- Ideally Ubuntu 24.04 LTS x64

**NOTE**: DigitalOcean is not suitable since it has network attached storage blocks

# Host Machine Setup
- update pkgs
```bash
sudo apt upgrade
```
- install docker and docker compose (check docker docs)

- ideally configure ssh to prevent root and password login (only through ssh pubkey login):
```bash
sudo nano /etc/ssh/sshd_config
```
and then:
```txt
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
```

- update firewall:
```bash
# set firewall
sudo ufw default deny incoming
sudo ufw default allow outgoing

sudo ufw allow OpenSSH
sudo ufw allow 80
sudo ufw allow 443
sudo ufw allow 18545 # rpc http
sudo ufw allow 18546 # rpc websocket
sudo ufw allow 9222 # p2p for sync
sudo ufw allow 30303 # p2p for sync
sudo ufw allow 13100 # loki rpc metrics
sudo ufw allow 19090 # prometheus node metrics
```

- add system swap:
```bash
sudo fallocate -l 64G /path/to/swapfile
sudo chmod 600 /path/to/swapfile
sudo mkswap /path/to/swapfile
sudo swapon /path/to/swapfile

# add to fstab so it is persisted through reboot
echo '/path/to/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# optionally configure swappiness, more value means more favorable towards swap, less mean more favorable towards RAM
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# check that swap is added
free -h
```

- instal nginx, this allows us the set configurations for rpc such as api keys, rate limiting, etc:
```bash
sudo apt install -y nginx
```

- configure nginx default config:
```sh
sudo nano /etc/nginx/nginx.conf
```

then enable `multi_accept on;` and `worker_connections 2048;` on events block and enable or add the following lines to `http {}` block under `Basic Settings`:
```txt
map_hash_bucket_size 128;
map_hash_max_size 4096;
```

example:
```txt
events {
	worker_connections 2048;
	multi_accept on;
}

http {

	##
	# Basic Settings
	##
	map_hash_bucket_size 128;
	map_hash_max_size 4096;
	sendfile on;
	tcp_nopush on;
	types_hash_max_size 2048;
	# server_tokens off;

	# server_names_hash_bucket_size 64;
	# server_name_in_redirect off;

    .
    .
    .
}
```

configure `rotate` field in `logrotate.d` for nginx log rotation.
```sh
sudo nano /etc/logrotate.d/nginx
```

example:
```txt
/var/log/nginx/*.log {
	daily
	missingok
	rotate 14 # this is set to 14 days log rotation
	compress
	delaycompress
	notifempty
	create 0640 www-data adm
	sharedscripts
	prerotate
		if [ -d /etc/logrotate.d/httpd-prerotate ]; then \
			run-parts /etc/logrotate.d/httpd-prerotate; \
		fi \
	endscript
	postrotate
		invoke-rc.d nginx rotate >/dev/null 2>&1
	endscript
}
```

## Repo Setup
Start by cloning this repo and go to the repo directory:
```sh
git clone https://github.com/rainlanguage/base-node.git /path/to/repo
cd /path/to/repo
```

- generate api key (as many as u wish) for rpc and put them in `./nginx/api_keys.map`:
```sh
openssl rand -hex 32
```

```sh
sudo nano ./nginx/api_keys.map
```

example:
```txt
# Maps API-KEY arg to a valid flag
map $arg_apikey $valid_key {
    default 0;    # deny by default
    d601800e8321fcd5884921e52bee932fd1d6f433f8933df5922441f649dde756 1; # admin key
    7b96008e7ba2aecd523db06e0ddf315b1f271ec361f08e9cff5efca61f879c35 1; # user key
    .
    .
    .
}
```

- enable and link the nginx rpc config:
```bash
sudo ln -s ./nginx/rpc.conf /etc/nginx/sites-enabled/
sudo ln -s ./nginx/api_keys.map /etc/nginx/
```

and test the config:
```sh
sudo nginx -t
sudo nginx -s reload
```

- create folder for promtail + loki data for rpc metrics:
```sh
sudo mkdir -m 775 -p ./nginx/loki-data
sudo mkdir -m 775 -p ./nginx/promtail-positions
```

- next run the docker compose for promtail + loki:
```sh
cd ./nginx
sudo docker compose up -d
cd ..
```

## Starting the Node
- configure the mainnet env varibales in `.env.mainnet`, those are L1, L1 Beacon RPC and JWT auth 32bytes length secrete:
```env
# [REQUIRED] L1 CONFIGURATION
# ---------------------------
# Replace these values with your L1 (Ethereum) node endpoints
BASE_NODE_L1_ETH_RPC=<your-preferred-l1-rpc>
BASE_NODE_L1_BEACON=<your-preferred-l1-beacon>

# ENGINE CONFIGURATION
# --------------------
BASE_NODE_L2_ENGINE_AUTH_RAW=<your-jwt-32-bytes-hex-secrete>
```

- configure the general `.env` (specify snapshot download and extraction directories if you are starting the node from a snapshot):
```env
# dir for node data
HOST_DATA_DIR=./reth-data

# snapshot type, either of "archive" or "pruned" (default pruned)
SNAPSHOT_TYPE=pruned

# absolute path to where snapshot tar willbe downloaded to
SNAPSHOT_DL_DIR=

# absolute path to where snapshot tar will be unpacked to
SNAPSHOT_EXT_DIR=

# prometehus (node metrics db) retention config
PROM_RETENTION_TIME=30d
PROM_RETENTION_SIZE=40GiB
```

- make dir for prometheus data:
```sh
sudo mkdir -m 775 -p prometheus-data
```

- if you are starting the node from snapshot, first specify the varibales for it in `.env` and the run (since this process takes some time, we use `tmux` to let the process continue even if ssh session end):
```sh
tmux new -s snapshot
```
and then in `tmux` session:
```sh
sudo ./snapshot.sh
```
this downloads the latest snapshot and unpacks it into specified directories and then starts the the node dcoker compose.

for detaching from `tmux`: Ctrl + B, then D
for reattaching to the tmux session:
```sh
tmux attach -t snapshot
```
for killing the session: Ctrl + D

- if you are not starting from any snapshot or already have the data, run:
```sh
sudo docker compose up -d --build
```

## Monitor Sync Process
- priodically check container logs:
```bash
sudo docker logs --since 100s execution
sudo docker logs --since 100s consensus
```
and check for errors in them:

```bash
sudo docker logs execution | grep -i "error"
sudo docker logs consensus | grep -i "error"
```

- monitor VM (if available) panel for system usage, sometime sudden drops in RAM usage may indicate that one of the container has unexpectedly restarted, you can confirm that with:
```bash
# check the `CREATED` time vs `STATUS` time of each container
sudo docker ps
```

or you can check sysem for `oom` errors:
```bash
sudo dmesg | grep -i kill
```

- Sync process may take some time (days), so be patiant but keep an eye on it and watch for possible errors and/or container restarts.

- You can check if the L2 blocks are increasing by:
```sh
echo $(($(curl -X POST http://127.0.0.1:8545 \
-H "Content-Type: application/json" \
--data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":["latest"],"id":1}' | jq -r .result )))
```

- You can check L1 sync with (this is the mai sync command in base docs, but it can get left behind during sync process, so plz be patient):
```bash
echo Latest synced block behind by: $((($(date +%s)-$( \
curl -d '{"id":0,"jsonrpc":"2.0","method":"optimism_syncStatus"}' \
-H "Content-Type: application/json" http://localhost:7545 | \
jq -r .result.unsafe_l2.timestamp))/60)) minutes
```

# Using The Node RPC
- HTTP URL
`http://droplet-public-ip:18545/?apikey=<your-api-key>`

- WS URL
`ws://droplet-public-ip:18546/?apikey=<your-api-key>`

## Setting up Grafana Monitor Dashboard
The node metrics are exposed on `19090` port and rpc metrics on `13100` with known api keys and can be set in grafana with prometheus data source and some pre built reth dashboard that can be found in `grafana` folder.

---
Section below is original Documentation
---

## Quick Start

1. Ensure you have an Ethereum L1 full node RPC and beacon endpoint available.
2. Choose your network:
   - For mainnet: use `.env.mainnet`
   - For testnet: use `.env.sepolia`
3. Configure your L1 endpoints in the appropriate `.env` file:
   ```bash
   BASE_NODE_L1_ETH_RPC=<your-preferred-l1-rpc>
   BASE_NODE_L1_BEACON=<your-preferred-l1-beacon>
   ```
4. Start the node:

   ```bash
   # For mainnet (default):
   docker compose up --build

   # For testnet:
   NETWORK_ENV=.env.sepolia docker compose up --build
   ```

## Supported Clients

- Execution: `base-reth-node`
- Consensus: `base-consensus`

## Requirements

### Minimum Requirements

- Modern multicore CPU
- 32GB RAM (64GB recommended)
- NVMe SSD drive
- Storage: (2 * [current chain size](https://base.org/stats) + [snapshot size](https://basechaindata.vercel.app) + 20% buffer) to accommodate future growth
- Docker and Docker Compose

### Production Hardware Specifications

The following are the hardware specifications we use in production:

#### Reth Archive Node (recommended)

- **Instance**: AWS i7i.12xlarge
- **Storage**: RAID 0 of all local NVMe drives (`/dev/nvme*`)
- **Filesystem**: ext4

## Configuration

### Required Settings

- `BASE_NODE_L1_ETH_RPC`: your Ethereum L1 node RPC endpoint
- `BASE_NODE_L1_BEACON`: your L1 beacon node endpoint
- `BASE_NODE_NETWORK`: `base` or `base-sepolia`
- `RETH_CHAIN`: `base` or `base-sepolia`

### Network Settings

- Mainnet:
  - `RETH_CHAIN=base`
  - `BASE_NODE_NETWORK=base`
  - Sequencer: `https://mainnet-sequencer.base.org`
- Sepolia:
  - `RETH_CHAIN=base-sepolia`
  - `BASE_NODE_NETWORK=base-sepolia`
  - Sequencer: `https://sepolia-sequencer.base.org`

### Optional Features

- Flashblocks: set `RETH_FB_WEBSOCKET_URL`. When set, the execution client runs in Flashblocks mode; otherwise it runs in vanilla mode.
- Follow mode: set `BASE_NODE_SOURCE_L2_RPC`
- Pruning: set `RETH_PRUNING_ARGS`

For full configuration options, see `.env.mainnet` or `.env.sepolia`.

### Testing Flashblocks RPC Methods

When running in Flashblocks mode, you can query a pending block using the Flashblocks RPC:

```bash
curl -X POST \
  --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["pending", false],"id":1}' \
  http://localhost:8545
```

## Snapshots

Snapshots are available to help you sync your node more quickly. See [docs.base.org](https://docs.base.org/chain/run-a-base-node#snapshots) for links and more details on how to restore from a snapshot.

## Supported Networks

| Network | Status |
| ------- | ------ |
| Mainnet | ✅ |
| Testnet | ✅ |

## Troubleshooting

For support please join our [Discord](https://discord.gg/buildonbase) and post in `🛠｜node-operators`. You can alternatively open a new GitHub issue.

## Disclaimer

THE NODE SOFTWARE IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND. We make no guarantees about asset protection or security. Usage is subject to applicable laws and regulations.

For more information, visit [docs.base.org](https://docs.base.org/).
