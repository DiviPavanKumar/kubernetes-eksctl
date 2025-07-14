#!/usr/bin/env bash
###############################################################################
# workstation.sh (Ubuntu)
# Installs: Docker Engine, kubectl, eksctl, helm, kubens
# Usage   : sudo bash workstation.sh [--yes]
###############################################################################

set -euo pipefail

# ───────────── Versions ──────────────────────────────────────────────────────
KUBECTL_VERSION=""            # e.g., v1.30.1; blank = latest stable
EKSCTL_VERSION="v0.181.0"
HELM_INSTALL_SCRIPT="https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3"

# ───────────── Colours ───────────────────────────────────────────────────────
R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[34m'; N=$'\e[0m'

# ───────────── Globals ───────────────────────────────────────────────────────
SCRIPT_NAME=$(basename "$0")
DATE=$(date +%F)
LOGFILE="/tmp/${SCRIPT_NAME}-${DATE}.log"
AUTO_YES="${1:-}"

# ───────────── Functions ─────────────────────────────────────────────────────
say()        { echo -e "${B}[$(date +%T)]${N} $*"; }
success()    { echo -e "  ↳ ${G}OK${N}"; }
fatal()      { echo -e "${R}ERROR:${N} $*"; exit 1; }

cmd()        { "$@" &>>"$LOGFILE"; }

validate() {
  [[ "$1" -eq 0 ]] && success || fatal "$2 failed – see $LOGFILE"
}

confirm() {
  if [[ "$AUTO_YES" == "--yes" ]]; then
    say "Auto‑proceed enabled (--yes)"
  else
    read -rp "Proceed with installation? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || { say "Aborted."; exit 0; }
  fi
}

# ───────────── Pre-checks ────────────────────────────────────────────────────
[[ "$(id -u)" -eq 0 ]] || fatal "Run this script as root (sudo)."
OS_NAME=$(lsb_release -ds)
say "Target OS : $OS_NAME"
say "Log file  : $LOGFILE"
confirm

# ───────────── 1. Basic tools ────────────────────────────────────────────────
say "1. Installing prerequisites ..."
cmd apt-get update
cmd apt-get install -y curl git tar gnupg lsb-release ca-certificates
validate $? "base package install"

# ───────────── 2. Docker Engine ──────────────────────────────────────────────
say "2. Setting up Docker repository ..."
ARCH=$(dpkg --print-architecture)
CODENAME=$(lsb_release -cs)

cmd install -m 0755 -d /etc/apt/keyrings
cmd curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
validate $? "Docker GPG key"

echo \
  "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $CODENAME stable" \
  | tee /etc/apt/sources.list.d/docker.list >/dev/null
validate $? "Docker repo added"

say "2. Installing Docker packages ..."
cmd apt-get update
cmd apt-get install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
validate $? "Docker install"

say "2. Enabling and starting Docker service ..."
cmd systemctl enable --now docker
validate $? "Docker service started"

INVOCATOR=${SUDO_USER:-$(logname)}
say "2. Adding user '$INVOCATOR' to docker group ..."
cmd usermod -aG docker "$INVOCATOR"
validate $? "User added to docker group"

# ───────────── 3. eksctl ─────────────────────────────────────────────────────
say "3. Installing eksctl (${EKSCTL_VERSION:-latest}) ..."
if [[ -z "$EKSCTL_VERSION" ]]; then
  EKSCTL_VERSION=$(curl -s https://api.github.com/repos/weaveworks/eksctl/releases/latest | grep tag_name | cut -d '"' -f4)
  say "   Detected latest version: $EKSCTL_VERSION"
fi

EKSCTL_TAR="/tmp/eksctl.tar.gz"
EKSCTL_URL="https://github.com/weaveworks/eksctl/releases/download/${EKSCTL_VERSION}/eksctl_Linux_amd64.tar.gz"

cmd curl -sL "$EKSCTL_URL" -o "$EKSCTL_TAR"
validate $? "eksctl downloaded"

cmd tar -xzf "$EKSCTL_TAR" -C /tmp
cmd install -m 755 /tmp/eksctl /usr/local/bin/eksctl
validate $? "eksctl installed"

# ───────────── 4. kubectl ────────────────────────────────────────────────────
say "4. Installing kubectl (${KUBECTL_VERSION:-latest stable}) ..."
if [[ -z "$KUBECTL_VERSION" ]]; then
  KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
fi

cmd curl -sL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
  -o /usr/local/bin/kubectl
cmd chmod 755 /usr/local/bin/kubectl
validate $? "kubectl installed"

# ───────────── 5. kubens ─────────────────────────────────────────────────────
say "5. Installing kubens helper ..."
cmd git clone --depth 1 https://github.com/ahmetb/kubectx /opt/kubectx
cmd ln -sf /opt/kubectx/kubens /usr/local/bin/kubens
validate $? "kubens installed"

# ───────────── 6. Helm 3 ─────────────────────────────────────────────────────
say "6. Installing Helm 3 ..."
cmd curl -fsSL -o get_helm.sh "$HELM_INSTALL_SCRIPT"
cmd chmod 700 get_helm.sh
cmd ./get_helm.sh
validate $? "Helm installed"

# ───────────── Done ──────────────────────────────────────────────────────────
say "${G}All tools installed successfully.${N}"
echo -e "${Y}→ Please log out and back in, or run \`newgrp docker\` to apply Docker group changes.${N}"
echo "→ Full log saved at: $LOGFILE"