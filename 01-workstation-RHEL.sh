#!/usr/bin/env bash
###############################################################################
# workstation.sh
# Installs: Docker Engine, kubectl, eksctl, helm, kubens
# Tested  : RHEL 9.x (should work on Alma/Rocky 9 too)
# Usage   : sudo bash workstation.sh [--yes]
###############################################################################
set -euo pipefail

# ───────────── Versions (set blank to auto‑detect latest) ────────────────────
KUBECTL_VERSION=""            # e.g. v1.30.1; empty = latest stable
EKSCTL_VERSION="v0.181.0"     # pin to this known‑good release
HELM_INSTALL_SCRIPT="https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3"

# ───────────── Colour codes ──────────────────────────────────────────────────
R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[34m'; N=$'\e[0m'

# ───────────── Globals ───────────────────────────────────────────────────────
SCRIPT_NAME=$(basename "$0")
DATE=$(date +%F)
LOGFILE="/tmp/${SCRIPT_NAME}-${DATE}.log"
AUTO_YES="${1:-}"

# ───────────── Helper functions ──────────────────────────────────────────────
say()        { echo -e "${B}[$(date +%T)]${N} $*"; }
success()    { echo -e "  ↳ ${G}OK${N}"; }
fatal()      { echo -e "${R}ERROR:${N} $*"; exit 1; }

cmd() { "$@" &>>"$LOGFILE"; }  # run and log

validate() {                   # $1 = exit‑code, $2 = msg
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

# ───────────── Pre‑flight ────────────────────────────────────────────────────
[[ "$(id -u)" -eq 0 ]] || fatal "Run as root (sudo)."
say "Target OS : RHEL $(rpm -q --queryformat '%{VERSION}' redhat-release)"
say "Log file  : $LOGFILE"
confirm

# ───────────── 1. Basic tools ────────────────────────────────────────────────
say "1. Installing dnf‑plugins‑core ..."
cmd dnf install -y dnf-plugins-core
validate $? "dnf-plugins-core"

# ───────────── 2. Docker Engine ──────────────────────────────────────────────
say "2. Adding Docker CE repository ..."
cmd dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
validate $? "docker-ce repo"

say "2. Installing Docker components ..."
cmd dnf install -y docker-ce docker-ce-cli containerd.io \
                  docker-buildx-plugin docker-compose-plugin
validate $? "docker-ce install"

say "2. Enabling and starting Docker ..."
cmd systemctl enable --now docker
validate $? "docker service"

INVOCATOR=${SUDO_USER:-$(logname)}
say "2. Adding user '${INVOCATOR}' to docker group ..."
cmd usermod -aG docker "$INVOCATOR"
validate $? "docker group"

# ───────────── 3. eksctl ────────────────────────────────────────────────────
say "3. Installing eksctl (${EKSCTL_VERSION:-latest}) ..."
if [[ -z "$EKSCTL_VERSION" ]]; then
  # fetch tag dynamically
  EKSCTL_VERSION="$(curl -s https://api.github.com/repos/weaveworks/eksctl/releases/latest \
                     | grep -m1 tag_name | cut -d '"' -f4)"
  say "   Detected latest version: $EKSCTL_VERSION"
fi

EKSCTL_URL="https://github.com/weaveworks/eksctl/releases/download/${EKSCTL_VERSION}/eksctl_Linux_amd64.tar.gz"
EKSCTL_TAR="/tmp/eksctl.tar.gz"

cmd curl -sL "$EKSCTL_URL" -o "$EKSCTL_TAR"
validate $? "Downloaded eksctl archive"

[[ -s "$EKSCTL_TAR" ]] || fatal "eksctl archive is empty or corrupt"

cmd tar -xzf "$EKSCTL_TAR" -C /tmp
cmd install -m 755 /tmp/eksctl /usr/local/bin/eksctl
validate $? "Installed eksctl"

# ───────────── 4. kubectl ────────────────────────────────────────────────────
say "4. Installing kubectl (${KUBECTL_VERSION:-stable}) ..."
if [[ -z "$KUBECTL_VERSION" ]]; then
  KUBECTL_VERSION="$(curl -sL https://dl.k8s.io/release/stable.txt)"
fi

cmd curl -sL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    -o /usr/local/bin/kubectl
cmd chmod 755 /usr/local/bin/kubectl
validate $? "kubectl"

# ───────────── 5. kubens helper ─────────────────────────────────────────────
say "5. Installing kubens ..."
cmd git clone --depth 1 https://github.com/ahmetb/kubectx /opt/kubectx
cmd ln -sf /opt/kubectx/kubens /usr/local/bin/kubens
validate $? "kubens"

# ───────────── 6. Helm 3 ────────────────────────────────────────────────────
say "6. Installing Helm 3 ..."
cmd curl -fsSL -o get_helm.sh "$HELM_INSTALL_SCRIPT"
cmd chmod 700 get_helm.sh
cmd ./get_helm.sh
validate $? "helm"

# ───────────── Finished ─────────────────────────────────────────────────────
say "${G}All tools installed successfully.${N}"
echo -e "${Y}→ Log out/in or run \`newgrp docker\` for group changes to take effect.${N}"
echo "Full log is at $LOGFILE"
