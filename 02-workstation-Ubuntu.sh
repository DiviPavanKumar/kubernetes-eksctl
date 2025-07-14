#!/bin/bash
###############################################################################
# workstation.sh  — Ubuntu edition
# Installs: Docker Engine, kubectl, eksctl, Helm, kubens
# Tested  : Ubuntu 20.04, 22.04, 24.04
# Usage   : sudo bash workstation.sh [--yes]
###############################################################################
set -euo pipefail

# ───────────── Versions (blank = auto‑detect latest) ─────────────────────────
KUBECTL_VERSION=""            # e.g., v1.30.1
EKSCTL_VERSION="v0.181.0"
HELM_INSTALL_SCRIPT="https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3"

# ───────────── Colours ───────────────────────────────────────────────────────
R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[34m'; N=$'\e[0m'

# ───────────── Globals ───────────────────────────────────────────────────────
SCRIPT_NAME=$(basename "$0")
DATE=$(date +%F)
LOGFILE="/tmp/${SCRIPT_NAME}-${DATE}.log"
AUTO_YES="${1:-}"

# ───────────── Helpers ───────────────────────────────────────────────────────
say()     { echo -e "${B}[$(date +%T)]${N} $*"; }
success() { echo -e "  ↳ ${G}OK${N}"; }
fatal()   { echo -e "${R}ERROR:${N} $*"; exit 1; }
cmd()     { "$@" &>>"$LOGFILE"; }

validate() { [[ "$1" -eq 0 ]] && success || fatal "$2 failed – see $LOGFILE"; }

confirm() {
  if [[ "$AUTO_YES" == "--yes" ]]; then
    say "Auto‑proceed enabled (--yes)"
  else
    read -rp "Proceed with installation? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || { say "Aborted."; exit 0; }
  fi
}

# ───────────── Pre‑flight ────────────────────────────────────────────────────
[[ "$(id -u)" -eq 0 ]] || fatal "Run as root (sudo)."
OS_NAME=$(lsb_release -ds)
say "Target OS : $OS_NAME"
say "Log file  : $LOGFILE"
confirm

# ───────────── 1. Prerequisites ──────────────────────────────────────────────
say "1. Updating apt cache & installing prerequisites ..."
cmd apt-get update -y
cmd apt-get install -y curl git tar gnupg lsb-release ca-certificates
validate $? "prerequisites"

# ───────────── 2. Docker Engine ──────────────────────────────────────────────
say "2. Setting up Docker GPG key and repository ..."
ARCH=$(dpkg --print-architecture)
CODENAME=$(lsb_release -cs)
KEYRING="/etc/apt/keyrings/docker.gpg"
cmd install -m 0755 -d /etc/apt/keyrings

TMP_ASC=$(mktemp)
TMP_GPG=$(mktemp)

say "→ Downloading Docker GPG key ..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$TMP_ASC"
gpg --batch --yes --dearmor -o "$TMP_GPG" "$TMP_ASC"
cmd install -m 644 "$TMP_GPG" "$KEYRING"
rm -f "$TMP_ASC" "$TMP_GPG"
success "Docker GPG key installed"

echo \
  "deb [arch=$ARCH signed-by=$KEYRING] https://download.docker.com/linux/ubuntu $CODENAME stable" \
  | tee /etc/apt/sources.list.d/docker.list >/dev/null
validate $? "Docker repo setup"

# ───────────── 3. eksctl ─────────────────────────────────────────────────────
say "3. Installing eksctl (${EKSCTL_VERSION:-latest}) ..."
if [[ -z "$EKSCTL_VERSION" ]]; then
  EKSCTL_VERSION=$(curl -s https://api.github.com/repos/weaveworks/eksctl/releases/latest \
                   | grep -m1 tag_name | cut -d '"' -f4)
  say "   Detected latest eksctl: $EKSCTL_VERSION"
fi
EKS_TAR=/tmp/eksctl.tar.gz
cmd curl -sL "https://github.com/weaveworks/eksctl/releases/download/${EKSCTL_VERSION}/eksctl_Linux_amd64.tar.gz" -o "$EKS_TAR"
cmd tar -xzf "$EKS_TAR" -C /tmp
cmd install -m 755 /tmp/eksctl /usr/local/bin/eksctl
validate $? "eksctl"

# ───────────── 4. kubectl ────────────────────────────────────────────────────
say "4. Installing kubectl (${KUBECTL_VERSION:-stable}) ..."
[[ -z "$KUBECTL_VERSION" ]] && KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
cmd curl -sL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl
cmd chmod 755 /usr/local/bin/kubectl
validate $? "kubectl"

# ───────────── 5. kubens ─────────────────────────────────────────────────────
say "5. Installing kubens ..."
cmd git clone --depth 1 https://github.com/ahmetb/kubectx /opt/kubectx
cmd ln -sf /opt/kubectx/kubens /usr/local/bin/kubens
validate $? "kubens"

# ───────────── 6. Helm ───────────────────────────────────────────────────────
say "6. Installing Helm 3 ..."
cmd curl -fsSL -o get_helm.sh "$HELM_INSTALL_SCRIPT"
cmd chmod 700 get_helm.sh
cmd ./get_helm.sh
validate $? "Helm"

# ───────────── Finished ─────────────────────────────────────────────────────
say "${G}All tools installed successfully.${N}"
echo -e "${Y}→ Log out and back in (or run \`newgrp docker\`) for Docker group changes to take effect.${N}"
echo "→ Full log: $LOGFILE"
