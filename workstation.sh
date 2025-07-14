#!/bin/bash
###############################################################################
# workstation.sh – Multi‑distro installer
# Installs: Docker Engine, kubectl, eksctl, Helm, kubens
# Supported: RHEL 8/9 (incl. Alma & Rocky), CentOS 7/8‑Stream, Ubuntu 20.04/22.04/24.04
# Usage   : sudo bash workstation.sh [--yes]        # add $OS_CHOICE=1|2|3 for CI
# chmod +x workstation.sh
# sudo bash workstation.sh          # interactive
# sudo bash workstation.sh --yes    # skip yes/no prompt
# In automation, also set:   OS_CHOICE=1  or 2 or 3
###############################################################################
set -euo pipefail

# ───────────── Versions (blank = latest) ─────────────────────────────────────
KUBECTL_VERSION=""
EKSCTL_VERSION="v0.181.0"
HELM_INSTALL_SCRIPT="https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3"

# ───────────── Colour codes ─────────────────────────────────────────────────
R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[34m'; N=$'\e[0m'

# ───────────── Globals ──────────────────────────────────────────────────────
SCRIPT_NAME=$(basename "$0")
DATE=$(date +%F)
LOGFILE="/tmp/${SCRIPT_NAME}-${DATE}.log"
AUTO_YES="${1:-}"               # optional --yes

# ───────────── Helper functions ─────────────────────────────────────────────
say()     { echo -e "${B}[$(date +%T)]${N} $*"; }
success() { echo -e "  ↳ ${G}OK${N}"; }
fatal()   { echo -e "${R}ERROR:${N} $*"; exit 1; }
cmd()     { "$@" &>>"$LOGFILE"; }
validate(){ [[ "$1" -eq 0 ]] && success || fatal "$2 failed – see $LOGFILE"; }
require_root(){ [[ "$(id -u)" -eq 0 ]] || fatal "Run as root (sudo)."; }

confirm() {
  if [[ "$AUTO_YES" == "--yes" ]]; then
    say "Auto‑proceed enabled (--yes)"
  else
    read -rp "Proceed with installation? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || { say "Aborted."; exit 0; }
  fi
}

# ───────────── OS selection ────────────────────────────────────────────────
require_root
say "Select target OS:"
echo "  1) RHEL / Alma / Rocky (8 or 9)"
echo "  2) CentOS 7 / 8‑Stream"
echo "  3) Ubuntu 20.04 / 22.04 / 24.04"
if [[ -z "${OS_CHOICE:-}" ]]; then
  read -rp "Enter 1, 2 or 3: " OS_CHOICE
fi
[[ "$OS_CHOICE" =~ ^[123]$ ]] || fatal "Invalid selection (choose 1, 2, or 3)."

confirm
say "Log file  : $LOGFILE"

# ───────────── 1. Base packages per distro ─────────────────────────────────
if [[ "$OS_CHOICE" == "1" ]]; then
  # ----- RHEL / Alma / Rocky -----
  say "1. Installing prerequisites (dnf) ..."
  cmd dnf install -y dnf-plugins-core curl git tar gnupg
  validate $? "prerequisites"

  say "2. Adding Docker repo ..."
  cmd dnf config-manager --add-repo \
    https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/docker-ce.repo
  validate $? "docker repo"

  PKG_INSTALL="dnf install -y"
  SVC_ENABLE="systemctl enable --now"

elif [[ "$OS_CHOICE" == "2" ]]; then
  # ----- CentOS -----
  say "1. Installing prerequisites (yum) ..."
  cmd yum install -y yum-utils curl git tar gnupg
  validate $? "prerequisites"

  say "2. Adding Docker repo ..."
  cmd yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  validate $? "docker repo"

  PKG_INSTALL="yum install -y"
  SVC_ENABLE="systemctl enable --now"

else
  # ----- Ubuntu -----
  say "1. Updating apt cache & installing prerequisites ..."
  cmd apt-get update -y
  cmd apt-get install -y curl git tar gnupg lsb-release ca-certificates
  validate $? "prerequisites"

  ARCH=$(dpkg --print-architecture)
  CODENAME=$(lsb_release -cs)
  KEYRING="/etc/apt/keyrings/docker.gpg"
  cmd install -m 0755 -d /etc/apt/keyrings
  TMP_ASC=$(mktemp); TMP_GPG=$(mktemp)
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$TMP_ASC"
  gpg --batch --yes --dearmor -o "$TMP_GPG" "$TMP_ASC"
  cmd install -m 644 "$TMP_GPG" "$KEYRING"
  echo "deb [arch=$ARCH signed-by=$KEYRING] https://download.docker.com/linux/ubuntu $CODENAME stable" \
    | tee /etc/apt/sources.list.d/docker.list >/dev/null
  PKG_INSTALL="apt-get install -y"
  SVC_ENABLE="systemctl enable --now"
  cmd apt-get update -y
fi

# ───────────── 2. Docker Engine ─────────────────────────────────────────────
say "2. Installing Docker Engine ..."
cmd $PKG_INSTALL docker-ce docker-ce-cli containerd.io \
                 docker-buildx-plugin docker-compose-plugin
validate $? "docker install"

say "2. Enabling Docker service ..."
cmd $SVC_ENABLE docker
validate $? "docker service"

INVOCATOR=${SUDO_USER:-$(logname)}
say "2. Adding user '$INVOCATOR' to docker group ..."
cmd groupadd -f docker
cmd usermod -aG docker "$INVOCATOR"
validate $? "docker group"

# ───────────── 3. eksctl ────────────────────────────────────────────────────
say "3. Installing eksctl ..."
[[ -z "$EKSCTL_VERSION" ]] && \
  EKSCTL_VERSION=$(curl -s https://api.github.com/repos/weaveworks/eksctl/releases/latest \
                    | grep -m1 tag_name | cut -d '"' -f4)
EKS_TAR=/tmp/eksctl.tar.gz
cmd curl -sL "https://github.com/weaveworks/eksctl/releases/download/${EKSCTL_VERSION}/eksctl_Linux_amd64.tar.gz" -o "$EKS_TAR"
cmd tar -xzf "$EKS_TAR" -C /tmp
cmd install -m 755 /tmp/eksctl /usr/local/bin/eksctl
validate $? "eksctl"

# ───────────── 4. kubectl ───────────────────────────────────────────────────
say "4. Installing kubectl ..."
[[ -z "$KUBECTL_VERSION" ]] && \
  KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
cmd curl -sL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl
cmd chmod 755 /usr/local/bin/kubectl
validate $? "kubectl"

# ───────────── 5. kubens helper ─────────────────────────────────────────────
say "5. Installing kubens ..."
cmd git clone --depth 1 https://github.com/ahmetb/kubectx /opt/kubectx
cmd ln -sf /opt/kubectx/kubens /usr/local/bin/kubens
validate $? "kubens"

# ───────────── 6. Helm 3 ────────────────────────────────────────────────────
say "6. Installing Helm ..."
cmd curl -fsSL -o get_helm.sh "$HELM_INSTALL_SCRIPT"
cmd chmod 700 get_helm.sh
cmd ./get_helm.sh
validate $? "helm"

# ───────────── Finished ────────────────────────────────────────────────────
say "${G}All tools installed successfully.${N}"
echo -e "${Y}→ Log out/in (or run \`newgrp docker\`) to use Docker without sudo.${N}"
echo "→ Full log: $LOGFILE"