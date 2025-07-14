#!/usr/bin/env bash
###############################################################################
# workstation.sh (Ubuntu)
# Installs: Docker Engine, kubectl, eksctl, helm, kubens
# Usage   : sudo bash workstation.sh [--yes]
###############################################################################
set -euo pipefail

# ───────────── Versions ──────────────────────────────────────────────────────
KUBECTL_VERSION=""             # e.g., v1.30.1; blank = latest stable
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

validate()   { [[ "$1" -eq 0 ]] && success || fatal "$2 failed – see $LOGFILE"; }

confirm() {
  if [[ "$AUTO_YES" == "--yes" ]]; then
    say "Auto‑proceed enabled (--yes)"
  else
    read -rp "Proceed with installation? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || { say "Aborted."; exit 0; }
  fi
}

# ───────────── Pre‑flight ────────────────────────────────────────────────────
[[ "$(id -u)" -eq 0 ]] || fatal "Run this script as root (sudo)."
OS_NAME=$(lsb_release -ds)
say "Target OS : $OS_NAME"
say "Log file  : $LOGFILE"
confirm

# ───────────── 1. Basic tools ────────────────────────────────────────────────
say "1. Updating apt cache and installing prerequisites ..."
cmd apt-get update -y
cmd apt-get install -y curl git tar gnupg lsb-release ca-certificates
validate $? "prerequisites"

# ───────────── 2. Docker Engine ──────────────────────────────────────────────
say "2. Setting up Docker repository ..."
ARCH=$(dpkg --print-architecture)
CODENAME=$(lsb_release -cs)

cmd install -m 0755 -d /etc/apt/keyrings
cmd curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg
validate $? "Docker GPG key"

echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $CODENAME stable" \
| tee /etc/apt/sources.list.d/docker.list >/dev/null
validate $? "Docker repo"

say "2. Installing Docker components ..."
cmd apt-get update -y
cmd apt-get install -y docker-ce docker-ce-cli containerd.io \
                       docker-buildx-plugin docker-compose-plugin
validate $? "Docker install"

say "2. Enabling and starting Docker service ..."
cmd systemctl enable --now docker
validate $? "Docker service"

INVOCATOR=${SUDO_USER:-$(logname)}
say "2. Adding users to docker group ..."
cmd usermod -aG docker "$INVOCATOR"
cmd usermod -aG docker ubuntu || true   # ignore if 'ubuntu' user does not exist
validate 0 "docker group membership"

# ───────────── 3. eksctl ─────────────────────────────────────────────────────
say "3. Installing eksctl (${EKSCTL_VERSION:-latest}) ..."
[[ -z "$EKSCTL_VERSION" ]] && \
  EKSCTL_VERSION=$(curl -s https://api.github.com/repos/weaveworks/eksctl/releases/latest \
                   | grep -m1 tag_name | cut -d '"' -f4)
EKSCTL_TAR="/tmp/eksctl.tar.gz"
EKSCTL_URL="https://github.com/weaveworks/eksctl/releases/download/${EKSCTL_VERSION}/eksctl_Linux_amd64.tar.gz"

cmd curl -sL "$EKSCTL_URL" -o "$EKSCTL_TAR"
validate $? "eksctl download"

cmd tar -xzf "$EKSCTL_TAR" -C /tmp
cmd install -m 755 /tmp/eksctl /usr/local/bin/eksctl
validate $? "eksctl install"

# ───────────── 4. kubectl ────────────────────────────────────────────────────
say "4. Installing kubectl (${KUBECTL_VERSION:-stable}) ..."
[[ -z "$KUBECTL_VERSION" ]] && \
  KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)

cmd curl -sL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    -o /usr/local/bin/kubectl
cmd chmod 755 /usr/local/bin/kubectl
validate $? "kubectl"

# ───────────── 5. kubens ─────────────────────────────────────────────────────
say "5. Installing kubens ..."
cmd git clone --depth 1 https://github.com/ahmetb/kubectx /opt/kubectx
cmd ln -sf /opt/kubectx/kubens /usr/local/bin/kubens
validate $? "kubens"

# ───────────── 6. Helm 3 ─────────────────────────────────────────────────────
say "6. Installing Helm 3 ..."
cmd curl -fsSL -o get_helm.sh "$HELM_INSTALL_SCRIPT"
cmd chmod 700 get_helm.sh
cmd ./get_helm.sh
validate $? "Helm"

# ───────────── Done ──────────────────────────────────────────────────────────
say "${G}All tools installed successfully.${N}"
echo -e "${Y}→ Docker group changes applied. Please **log out and log back in** (or run \`newgrp docker\`) so they take effect.${N}"
echo "→ Full installation log: $LOGFILE"
