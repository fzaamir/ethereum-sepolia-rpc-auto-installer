#!/bin/bash

set -euo pipefail
trap 'echo -e "\033[1;31m❌ Error at line $LINENO. Exiting.\033[0m"' ERR

GREEN="\033[1;32m"; BLUE="\033[1;34m"; YELLOW="\033[1;33m"; CYAN="\033[1;36m"; RED="\033[1;31m"; NC="\033[0m"

BASE_DIR="/opt/eth-rpc-node"
JWT_PATH="$BASE_DIR/jwt.hex"
LOG_FILE="$BASE_DIR/node_setup.log"

EXECUTION_RPC=8545
CONSENSUS_RPC=3500
AUTH_RPC=8551
P2P_PORT=30303

mkdir -p "$BASE_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

step_counter=1

separator() {
  echo -e "${BLUE}--------------------------------------------------${NC}"
}

loading_dots() {
  local pid=$1
  local msg=$2
  local delay=0.5
  local dots=""
  while ps -p $pid > /dev/null 2>&1; do
    dots="${dots}."
    [[ ${#dots} -gt 3 ]] && dots="."
    echo -ne "   $msg$dots\r"
    sleep $delay
  done
  echo -ne "\r\033[K"
}

run_step() {
  local msg="$1"
  shift
  echo -e "${YELLOW}[Step $step_counter] $msg${NC}"
  step_counter=$((step_counter+1))
  ("$@") >/dev/null 2>&1 &
  pid=$!
  loading_dots $pid "$msg"
  wait $pid
  if [ $? -eq 0 ]; then
    echo -e "   ${GREEN}✅ $msg completed.${NC}"
  else
    echo -e "   ${RED}❌ $msg failed.${NC}"
    exit 1
  fi
  separator
}

get_json_field() {
  echo "$1" | jq -r "$2" 2>/dev/null || echo ""
}

IP_ADDR="$(curl -s --max-time 5 ifconfig.me || true)"
if [ -z "$IP_ADDR" ]; then
  IP_ADDR="$(hostname -I | awk '{print $1}')"
fi

print_banner() {
  clear
  echo -e "${YELLOW}"
  echo "███████╗███████╗     █████╗      █████╗ ███╗   ███╗██╗██████╗ "
  echo "██╔════╝╚══███╔╝    ██╔══██╗    ██╔══██╗████╗ ████║██║██╔══██╗"
  echo "█████╗    ███╔╝     ███████║    ███████║██║╔████╔██║██║██████╔╝"
  echo "██╔══╝   ███╔╝      ██╔══██║    ██╔══██║██║╚██╔╝██║██║██╔══██╗"
  echo "██║     ███████╗    ██║  ██║    ██║  ██║██║ ╚═╝ ██║██║██║  ██║"
  echo "╚═╝     ╚══════╝    ╚═╝  ╚═╝    ╚═╝  ╚═╝╚═╝     ╚═╝╚═╝╚═╝  ╚═╝"
  echo -e "${CYAN}                   🚀 POWERED BY: FZ_AAMIR 💻${NC}"
  echo -e "${BLUE}=============================="
  echo " Ethereum Sepolia Node Menu"
  echo -e "==============================${NC}"
  echo "1) 🚀 Install & Start Node"
  echo "2) 📜 View Logs"
  echo "3) 📶 Check Node Status"
  echo "4) ❌ Exit"
  echo -en "${NC}Choose an option [1-4]: "
}

install_dependencies() {
  run_step "Updating system packages" apt update -y
  run_step "Upgrading system packages" apt upgrade -y
  local packages=(curl jq net-tools iproute2 iptables build-essential git wget lz4 make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip ufw openssl)
  for pkg in "${packages[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
      run_step "Installing $pkg" apt-get install -y "$pkg"
    else
      echo -e "   ${YELLOW}ℹ️ $pkg already installed.${NC}"
    fi
  done
}

install_docker() {
  if ! command -v docker &>/dev/null; then
    run_step "Removing old Docker versions" apt-get remove -y docker docker-engine docker.io containerd runc
    run_step "Installing prerequisites for Docker" apt-get install -y ca-certificates gnupg
    run_step "Adding Docker GPG key" bash -c "install -m 0755 -d /etc/apt/keyrings && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && chmod a+r /etc/apt/keyrings/docker.gpg"
    run_step "Adding Docker repository" bash -c "echo 'deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \$(. /etc/os-release && echo \$VERSION_CODENAME) stable' | tee /etc/apt/sources.list.d/docker.list > /dev/null"
    run_step "Updating apt cache" apt-get update -y
    run_step "Installing Docker Engine" apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    run_step "Enabling Docker service" systemctl enable docker
    run_step "Restarting Docker service" systemctl restart docker
  else
    echo -e "   ${YELLOW}ℹ️ Docker already installed.${NC}"
  fi
}

check_ports() {
  echo -e "${YELLOW}🕵️ Checking port availability...${NC}"
  local conflicts
  conflicts=$(ss -tulpen | grep -E "$P2P_PORT|$EXECUTION_RPC|8546|$AUTH_RPC|4000|$CONSENSUS_RPC" || true)
  if [ -n "$conflicts" ]; then
    echo -e "${RED}❌ Ports in use:\n$conflicts${NC}"
    exit 1
  fi
  echo -e "${GREEN}✅ Required ports are free.${NC}"
  separator
}

create_directories() {
  run_step "Creating directories & JWT secret" bash -c "mkdir -p $BASE_DIR/execution $BASE_DIR/consensus && rm -f $JWT_PATH && openssl rand -hex 32 > $JWT_PATH"
}

write_compose_file() {
  echo -e "${YELLOW}📝 Writing docker-compose.yml...${NC}"
  cat > "$BASE_DIR/docker-compose.yml" <<EOF
version: '3.8'
services:
  execution:
    image: ethereum/client-go:stable
    container_name: geth
    network_mode: host
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://127.0.0.1:$EXECUTION_RPC"]
      interval: 30s
      retries: 5
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
      - --authrpc.port=$AUTH_RPC
      - --syncmode=snap
      - --datadir=/data

  consensus:
    image: gcr.io/prysmaticlabs/prysm/beacon-chain:stable
    container_name: prysm
    network_mode: host
    restart: unless-stopped
    depends_on:
      - execution
    healthcheck:
      test: ["CMD", "curl", "-f", "http://127.0.0.1:$CONSENSUS_RPC/eth/v1/node/health"]
      interval: 30s
      retries: 5
    volumes:
      - ./consensus:/data
      - ./jwt.hex:/data/jwt.hex
    command:
      - --sepolia
      - --accept-terms-of-use
      - --datadir=/data
      - --disable-monitoring
      - --rpc-host=0.0.0.0
      - --execution-endpoint=http://127.0.0.1:$AUTH_RPC
      - --jwt-secret=/data/jwt.hex
      - --rpc-port=4000
      - --grpc-gateway-host=0.0.0.0
      - --grpc-gateway-port=$CONSENSUS_RPC
      - --min-sync-peers=3
      - --checkpoint-sync-url=https://checkpoint-sync.sepolia.ethpandaops.io
      - --genesis-beacon-api-url=https://checkpoint-sync.sepolia.ethpandaops.io
EOF
  echo -e "${GREEN}✅ Compose file created.${NC}"
  separator
}

start_services() {
  run_step "Starting Ethereum Sepolia services" bash -c "cd $BASE_DIR && docker compose up -d"
}

monitor_sync() {
  echo -e "${CYAN}📡 Monitoring sync status...${NC}"
  while true; do
    geth_sync=$(curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' http://127.0.0.1:$EXECUTION_RPC || true)
    if [[ "$geth_sync" == *"false"* ]]; then
      echo -e "${GREEN}✅ Geth fully synced.${NC}"
    else
      current=$(get_json_field "$geth_sync" ".result.currentBlock")
      highest=$(get_json_field "$geth_sync" ".result.highestBlock")
      current_dec=$((current))
      highest_dec=$((highest))
      if [ "$highest_dec" -gt 0 ]; then
        percent=$(awk "BEGIN {printf \"%.2f\", ($current_dec/$highest_dec)*100}")
        echo -e "${YELLOW}🔄 Geth syncing: $current_dec / $highest_dec (~$percent%)${NC}"
      fi
    fi
    prysm_sync=$(curl -s http://127.0.0.1:$CONSENSUS_RPC/eth/v1/node/syncing || true)
    distance=$(get_json_field "$prysm_sync" ".data.sync_distance")
    head=$(get_json_field "$prysm_sync" ".data.head_slot")
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
  echo -e "${CYAN}\n🎉 Ethereum Sepolia Node Setup Complete${NC}\n"
  echo -e "${BLUE}Services Health:${NC}"
  local geth_status=$(docker inspect --format='{{.State.Health.Status}}' geth 2>/dev/null || echo "unknown")
  local prysm_status=$(docker inspect --format='{{.State.Health.Status}}' prysm 2>/dev/null || echo "unknown")
  if [[ "$geth_status" == "healthy" ]]; then
    echo -e "  ✅ Geth (Execution) — healthy"
  else
    echo -e "  ❌ Geth (Execution) — $geth_status"
  fi
  if [[ "$prysm_status" == "healthy" ]]; then
    echo -e "  ✅ Prysm (Consensus) — healthy"
  else
    echo -e "  ❌ Prysm (Consensus) — $prysm_status"
  fi
  echo -e "\n${BLUE}RPC Endpoints:${NC}"
  echo -e "${GREEN}📎 Geth:     http://$IP_ADDR:$EXECUTION_RPC${NC}"
  echo -e "${GREEN}📎 Prysm:    http://$IP_ADDR:$CONSENSUS_RPC${NC}"
  echo -e "${BLUE}\n🎉 Setup complete — Powered by FZ_AAMIR ✨${NC}"
}

check_node_status() {
  echo -e "${CYAN}📡 Live Ethereum Sepolia Node Status (refreshing every 10s, Ctrl+C to exit)...${NC}"
  while true; do
    clear
    echo -e "${CYAN}🔍 Checking Ethereum Sepolia node status...${NC}\n"
    geth_sync=$(curl -s -X POST -H "Content-Type: application/json" \
      --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
      http://127.0.0.1:$EXECUTION_RPC || true)

    if [[ "$geth_sync" == *"false"* ]]; then
      echo -e "✅ ${GREEN}Geth (Execution) is fully synced.${NC}"
    else
      current=$(get_json_field "$geth_sync" ".result.currentBlock")
      highest=$(get_json_field "$geth_sync" ".result.highestBlock")
      current_dec=$((current))
      highest_dec=$((highest))
      percent=$(awk "BEGIN {printf \"%.2f\", ($current_dec/$highest_dec)*100}")
      echo -e "🔄 ${YELLOW}Geth syncing: $current_dec / $highest_dec (~$percent%)${NC}"
    fi

    prysm_sync=$(curl -s http://127.0.0.1:$CONSENSUS_RPC/eth/v1/node/syncing || true)
    distance=$(get_json_field "$prysm_sync" ".data.sync_distance")
    head=$(get_json_field "$prysm_sync" ".data.head_slot")
    if [[ "$distance" == "0" ]]; then
      echo -e "✅ ${GREEN}Prysm (Consensus) is fully synced.${NC}"
    else
      echo -e "🔄 ${YELLOW}Prysm syncing: $distance slots behind (head: $head)${NC}"
    fi

    sleep 10
  done
}


handle_choice() {
  case "$1" in
    1) install_dependencies; install_docker; check_ports; create_directories; write_compose_file; start_services; monitor_sync; print_endpoints ;;
    2) [ -f "$BASE_DIR/docker-compose.yml" ] && cd "$BASE_DIR" && docker compose logs -f || echo -e "${RED}❌ No docker-compose.yml found.${NC}" ;;
    3) check_node_status ;;
    4) echo -e "${CYAN}👋 Goodbye!${NC}"; exit 0 ;;
    *) echo -e "${RED}❌ Invalid input.${NC}" ;;
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
