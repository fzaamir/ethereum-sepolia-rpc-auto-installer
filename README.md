# ✨ Ethereum Sepolia RPC Auto-Installer

**Automated Geth + Prysm Node Deployment**

---

## 🔥 Features

✅ One-command setup

📦 Geth (Execution Layer) node

🛰️ Prysm (Consensus Layer) node

🔐 Secure JWT auth generation

🌐 Local & external RPC endpoints

📊 Real-time sync progress tracking

🛡️ Port conflict detection

🐳 Fully Docker-based, dependency-aware

---

## 🛠️ System Requirements

* **OS:** Ubuntu 20.04+ / Debian 11+
* **RAM:** 16 GB minimum
* **Disk:** 500 GB+ SSD
* **Privileges:** Root/sudo access

---

## 🚀 Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/fzaamir/ethereum-sepolia-rpc-auto-installer/main/setup.sh | bash
```

📦 This will:

* ⚙️ Install all required packages & Docker
* 🛠️ Configure Geth + Prysm nodes
* 🔐 Generate JWT secrets
* 🚀 Launch nodes & display RPC endpoints

---

## 🌐 RPC Endpoints

After syncing completes:

| Layer    | Description            | Endpoint                |
| -------- | ---------------------- | ----------------------- |
| ⚙️ Geth  | Execution RPC (ETH)    | `http://<your-ip>:8545` |
| 🔗 Prysm | Beacon RPC (Consensus) | `http://<your-ip>:3500` |

> 🔒 Accessible externally or locally


## 🙌 Contribute

Open to PRs, issues, and forks! Submit your ideas or improvements anytime.

---


Made with 🛠️ by contributors who love Ethereum.
