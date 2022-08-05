#! /bin/bash

## Install essential packages
wget https://repo.zabbix.com/zabbix/6.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_6.0-1+ubuntu20.04_all.deb
sudo dpkg -i zabbix-release_6.0-1+ubuntu20.04_all.deb
rm zabbix-release_6.0-1+ubuntu20.04_all.deb
sudo apt update
sudo apt update && sudo apt install make build-essential gcc git jq chrony wireguard zabbix-agent2 -y
sudo snap install go --classic 
echo "PATH=~/go/bin:$PATH" >> ~/.profile
source ~/.profile

## Clone odin repo and build from source
git clone https://github.com/ODIN-PROTOCOL/odin-core.git
cd odin-core
git fetch --tags
git checkout v0.5.5
make all
mkdir -p ~/.odin/cosmovisor/genesis/bin
cp ~/go/bin/odind ~/.odin/cosmovisor/genesis/bin/
cd ..
odind version

## Download cosmovisor
wget https://github.com/cosmos/cosmos-sdk/releases/download/cosmovisor%2Fv1.1.0/cosmovisor-v1.1.0-linux-amd64.tar.gz ; tar xvfz  cosmovisor-v1.1.0-linux-amd64.tar.gz -C ~/go/bin/

## Set external_address in config.toml
sed -i "s/external_address = \"\"/external_address = \"$(echo $(curl ifconfig.me):26656)\"/" .odin/config/config.toml

## Setup statesync
## Official ODIN RPC Node Address.
SNAP_RPC="http://34.79.179.216:26657,http://34.140.252.7:26657,http://35.241.221.154:26657,http://35.241.238.207:26657"
RPC_ADDR="http://34.79.179.216:26657"
INTERVAL=2000

LATEST_HEIGHT=$(curl -s $RPC_ADDR/block | jq -r .result.block.header.height);
BLOCK_HEIGHT=$(($LATEST_HEIGHT-$INTERVAL))
TRUST_HASH=$(curl -s "$RPC_ADDR/block?height=$BLOCK_HEIGHT" | jq -r .result.block_id.hash)

SEED="4529fc24a87ff5ab105970f425ced7a6c79f0b8f@odin-seed-01.mercury-nodes.net:29536,c8ee9f66163f0c1220c586eab1a2a57f6381357f@odin.seed.rhinostake.com:16658"
## Displaying Height and hash
echo "TRUST HEIGHT: $BLOCK_HEIGHT"
echo "TRUST HASH: $TRUST_HASH"

## editing config.toml with correct values
sed -i.bak -E "s|^(enable[[:space:]]+=[[:space:]]+).*$|\1true| ; \
s|^(rpc_servers[[:space:]]+=[[:space:]]+).*$|\1\"$SNAP_RPC\"| ; \
s|^(trust_height[[:space:]]+=[[:space:]]+).*$|\1$BLOCK_HEIGHT| ; \
s|^(trust_hash[[:space:]]+=[[:space:]]+).*$|\1\"$TRUST_HASH\"| ; \
s|^(seeds[[:space:]]+=[[:space:]]+).*$|\1\"$SEED\"|" $HOME/.odin/config/config.toml
export ODIN_STATESYNC_ENABLE=true
export ODIN_STATESYNC_RPC_SERVERS="$SNAP_RPC"
export ODIN_STATESYNC_TRUST_HEIGHT=$BLOCK_HEIGHT
export ODIN_STATESYNC_TRUST_HASH=$TRUST_HASH


sed -i 's/minimum-gas-prices = ""/minimum-gas-prices = "0.0001loki"/' .odin/config/app.toml
sed -i 's/pruning = "default"/pruning = "custom"/' .odin/config/app.toml 
sed -i 's/pruning-keep-recent = "0"/pruning-keep-recent = "107"/' .odin/config/app.toml
sed -i 's/pruning-interval = "0"/pruning-interval = "10"/' .odin/config/app.toml

curl https://raw.githubusercontent.com/ODIN-PROTOCOL/networks/master/mainnets/odin-mainnet-freya/genesis.json > ~/.odin/config/genesis.json

echo "[Unit]
Description=Odin Cosmovisor Daemon
After=network-online.target

[Service]
User=cosmovisor
ExecStart=/home/cosmovisor/go/bin/cosmovisor run start
Restart=on-failure
RestartSec=3
LimitNOFILE=infinity

Environment="DAEMON_HOME=/home/cosmovisor/.odin"
Environment="DAEMON_NAME=odind"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"

[Install]
WantedBy=multi-user.target" > odind.service
sudo cp odind.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable odind
odind unsafe-reset-all
sudo systemctl start odind
echo "Odin has been built from source, configured, and started.  Please check the log file with 'journalctl -fu odind' to verify node operational."

