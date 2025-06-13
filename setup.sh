#!/bin/bash

set -euo pipefail
trap 'echo -e "\033[1;31m❌ Error occurred at line $LINENO. Exiting.\033[0m"' ERR

GREEN="\033[1;32m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
RED="\033[1;31m"
NC="\033[0m"

BASE_DIR="/opt/eth-rpc-node"
JWT_PATH="$BASE_DIR/jwt.hex"
IP_ADDR="$(curl -s ifconfig.me || hostname -I | awk '{print $1}')"

print_banner() {
  clear
  echo -e "${YELLOW}"
  echo "███████╗███████╗     █████╗      █████╗ ███╗   ███╗██╗██████╗ "
  echo "██╔════╝╚══███╔╝    ██╔══██╗    ██╔══██╗████╗ ████║██║██╔══██╗"
  echo "█████╗    ███╔╝     ███████║    ███████║██╔████╔██║██║██████╔╝"
  echo "██╔══╝   ███╔╝      ██╔══██║    ██╔══██║██║╚██╔╝██║██║██╔══██╗"
  echo "██║     ███████╗    ██║  ██║    ██║  ██║██║ ╚═╝ ██║██║██║  ██║"
  echo "╚═╝     ╚══════╝    ╚═╝  ╚═╝    ╚═╝  ╚═╝╚═╝     ╚═╝╚═╝╚═╝  ╚═╝"
  echo -e "${CYAN}                   🚀 POWERED BY: FZ_AAMIR 💻${NC}\n"
  echo -e "${BLUE}=============================="
  echo " Ethereum Sepolia Node Menu"
  echo "==============================${NC}"
  echo "1) 🚀 Install & Start Node"
  echo "2) 📜 View Logs"
  echo "3) 📶 Check Node Status"
  echo "4) ❌ Exit"
  echo -n "Choose an option [1-4]: "
}

install_dependencies() {
  echo -e "${YELLOW}🔧 Installing required packages...${NC}"
  apt update -y && apt upgrade -y
  local packages=(curl jq net-tools iptables build-essential git wget lz4 make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip ufw)
  for pkg in "${packages[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
      apt-get install -y "$pkg"
      echo -e "${GREEN}✅ Installed $pkg${NC}"
    fi
  done
}

install_docker() {
  if ! command -v docker &>/dev/null; then
    echo -e "${CYAN}🐳 Installing Docker...${NC}"
    apt-get remove docker docker-engine docker.io containerd runc -y || true
    apt-get install -y ca-certificates gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable docker
    systemctl restart docker
    echo -e "${GREEN}✅ Docker installed${NC}"
  else
    echo -e "${CYAN}ℹ️ Docker already installed. Skipping.${NC}"
  fi
}

check_ports() {
  echo -e "${YELLOW}🕵️ Checking port availability...${NC}"
  local conflicts
  conflicts=$(netstat -tuln | grep -E '30303|8545|8546|8551|4000|3500' || true)
  if [ -n "$conflicts" ]; then
    echo -e "${RED}❌ Ports in use. Please resolve conflicts:\n$conflicts${NC}"
    exit 1
  fi
  echo -e "${GREEN}✅ Required ports are free.${NC}"
}

create_directories() {
  echo -e "${YELLOW}📁 Creating data directories...${NC}"
  rm -rf "$BASE_DIR/execution" "$BASE_DIR/consensus"
  mkdir -p "$BASE_DIR/execution" "$BASE_DIR/consensus"
  rm -f "$JWT_PATH"
  if ! command -v openssl >/dev/null 2>&1; then
    echo -e "${RED}❌ OpenSSL not found. Aborting.${NC}"
    exit 1
  fi
  openssl rand -hex 32 > "$JWT_PATH"
  echo -e "${GREEN}✅ JWT secret created.${NC}"
}

write_compose_file() {
  echo -e "${YELLOW}📝 Writing docker-compose.yml...${NC}"
  cat > "$BASE_DIR/docker-compose.yml" <<EOF
services:
  execution:
    image: ethereum/client-go:stable
    container_name: geth
    network_mode: host
    restart: unless-stopped
    ports:
      - 30303:30303
      - 30303:30303/udp
      - 8545:8545
      - 8546:8546
      - 8551:8551
    volumes:
      - ./execution:/data
      - ./jwt.hex:/data/jwt.hex
    command:
      - --sepolia
      - --http
      - --http.api=eth,net,web3
      - --http.addr=0.0.0.0
      - --authrpc.addr=0.0.0.0
      - --authrpc.vhosts=*
      - --authrpc.jwtsecret=/data/jwt.hex
      - --authrpc.port=8551
      - --syncmode=snap
      - --datadir=/data

  consensus:
    image: gcr.io/prysmaticlabs/prysm/beacon-chain
    container_name: prysm
    network_mode: host
    restart: unless-stopped
    depends_on:
      - execution
    volumes:
      - ./consensus:/data
      - ./jwt.hex:/data/jwt.hex
    ports:
      - 4000:4000
      - 3500:3500
    command:
      - --sepolia
      - --accept-terms-of-use
      - --datadir=/data
      - --disable-monitoring
      - --rpc-host=0.0.0.0
      - --execution-endpoint=http://$IP_ADDR:8551
      - --jwt-secret=/data/jwt.hex
      - --rpc-port=4000
      - --grpc-gateway-host=0.0.0.0
      - --grpc-gateway-port=3500
      - --min-sync-peers=3
      - --checkpoint-sync-url=https://checkpoint-sync.sepolia.ethpandaops.io
      - --genesis-beacon-api-url=https://checkpoint-sync.sepolia.ethpandaops.io
EOF
  echo -e "${GREEN}✅ Compose file created.${NC}"
}

start_services() {
  echo -e "${CYAN}🚀 Starting Ethereum Sepolia services...${NC}"
  cd "$BASE_DIR"
  docker compose up -d
  echo -e "${GREEN}✅ Services started.${NC}"
}

monitor_sync() {
  echo -e "${CYAN}📡 Monitoring sync status...${NC}"
  while true; do
    local geth_sync=$(curl -s -X POST -H "Content-Type: application/json" \
      --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' http://$IP_ADDR:8545)
    local prysm_sync=$(curl -s http://$IP_ADDR:3500/eth/v1/node/syncing)

    if [[ "$geth_sync" == *"false"* ]]; then
      echo -e "${GREEN}✅ Geth fully synced.${NC}"
    else
      local current=$(echo "$geth_sync" | jq -r .result.currentBlock)
      local highest=$(echo "$geth_sync" | jq -r .result.highestBlock)
      local percent=$(awk "BEGIN {printf \"%.2f\", (0x${current}/0x${highest})*100}")
      echo -e "${YELLOW}🔄 Geth syncing: Block $current of $highest (~$percent%)${NC}"
    fi

    local distance=$(echo "$prysm_sync" | jq -r '.data.sync_distance')
    local head=$(echo "$prysm_sync" | jq -r '.data.head_slot')

    if [[ "$distance" == "0" ]]; then
      echo -e "${GREEN}✅ Prysm fully synced.${NC}"
    else
      echo -e "${YELLOW}🔄 Prysm syncing: $distance slots behind (head: $head)${NC}"
    fi

    [[ "$geth_sync" == *"false"* && "$distance" == "0" ]] && break
    sleep 10
  done
}

print_endpoints() {
  echo -e "${CYAN}\n🔗 Ethereum Sepolia RPC Endpoints:${NC}"
  echo -e "${GREEN}📎 Geth:     http://$IP_ADDR:8545${NC}"
  echo -e "${GREEN}📎 Prysm:    http://$IP_ADDR:3500${NC}"
  echo -e "${BLUE}\n🎉 Setup complete — Powered by FZ_AAMIR ✨${NC}"
}

check_node_status() {
  echo -e "${CYAN}🔍 Checking Ethereum Sepolia node status...${NC}"
  local geth_sync=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' http://$IP_ADDR:8545)
  local prysm_sync=$(curl -s http://$IP_ADDR:3500/eth/v1/node/syncing)
  echo ""
  if [[ "$geth_sync" == *"false"* ]]; then
    echo -e "✅ ${GREEN}Geth (Execution Layer) is fully synced.${NC}"
  else
    local current=$(echo "$geth_sync" | jq -r .result.currentBlock)
    local highest=$(echo "$geth_sync" | jq -r .result.highestBlock)
    local percent=$(awk "BEGIN {printf \"%.2f\", (0x${current}/0x${highest})*100}")
    echo -e "🔄 ${YELLOW}Geth is syncing: Block $current of $highest (~$percent%)${NC}"
  fi
  local distance=$(echo "$prysm_sync" | jq -r '.data.sync_distance')
  local head=$(echo "$prysm_sync" | jq -r '.data.head_slot')
  if [[ "$distance" == "0" ]]; then
    echo -e "✅ ${GREEN}Prysm (Consensus Layer) is fully synced.${NC}"
  else
    echo -e "🔄 ${YELLOW}Prysm is syncing: $distance slots behind (head: $head)${NC}"
  fi
  echo ""
}

handle_choice() {
  case "$1" in
    1)
      install_dependencies
      install_docker
      check_ports
      create_directories
      write_compose_file
      start_services
      monitor_sync
      print_endpoints
      ;;
    2)
      if [ -f "$BASE_DIR/docker-compose.yml" ]; then
        cd "$BASE_DIR"
        echo -e "${YELLOW}📜 Showing logs... Ctrl+C to exit.${NC}"
        docker compose logs -f
      else
        echo -e "${RED}❌ No docker-compose.yml found. Please run installation first.${NC}"
      fi
      ;;
    3)
      check_node_status
      ;;
    4)
      echo -e "${CYAN}👋 Goodbye!${NC}"
      exit 0
      ;;
    *)
      echo -e "${RED}❌ Invalid input. Enter 1, 2, 3, or 4.${NC}"
      ;;
  esac
}

main() {
  while true; do
    print_banner
    read -r choice
    handle_choice "$choice"
    echo ""
    read -rp "Press Enter to return to the menu..."
  done
}

main
