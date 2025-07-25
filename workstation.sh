#!/bin/bash 
###############################################################################
# workstation.sh – RHEL EC2 Docker Setup (Safe EC2 Version)
# Installs: Docker Engine, kubectl, eksctl, Helm, kubens
# Supported: RHEL 8/9 (incl. Alma & Rocky) – ONLY
###############################################################################
set -euo pipefail

KUBECTL_VERSION=""
EKSCTL_VERSION="v0.181.0"
HELM_INSTALL_SCRIPT="https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3"

R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[34m'; N=$'\e[0m'
SCRIPT_NAME=$(basename "$0")
DATE=$(date +%F)
LOGFILE="/tmp/${SCRIPT_NAME}-${DATE}.log"
AUTO_YES="${1:-}"

docker_user="ec2-user"

say()     { echo -e "${B}[$(date +%T)]${N} $*"; }
success() { echo -e "  → ${G}OK${N}"; }
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

require_root
confirm
say "Log file  : $LOGFILE"

say "1. Installing prerequisites (dnf) ..."
cmd dnf install -y dnf-plugins-core curl git tar gnupg lsb-release
validate $? "prerequisites"

say "2. Adding Docker repo ..."
cmd dnf config-manager --add-repo \
  https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/docker-ce.repo
validate $? "docker repo"

say "3. Installing Docker Engine ..."
cmd dnf install -y docker-ce docker-ce-cli containerd.io \
                 docker-buildx-plugin docker-compose-plugin
validate $? "docker install"

say "4. Enabling and starting Docker service ..."
cmd systemctl enable --now docker
validate $? "docker service"

say "5. Verifying ec2-user exists ..."
if id "$docker_user" &>/dev/null; then
  say " → ec2-user found. Checking and updating shell if necessary ..."
  USER_SHELL=$(getent passwd $docker_user | cut -d: -f7)
  if [[ "$USER_SHELL" != "/bin/bash" ]]; then
    say " → Changing shell to /bin/bash for $docker_user ..."
    cmd chsh -s /bin/bash $docker_user
  fi
else
  fatal "ec2-user not found on this system."
fi

say "6. Adding ec2-user to docker group (safe method) ..."
cmd groupadd -f docker
say " → Groups before: $(id -nG $docker_user)"
cmd usermod -aG docker $docker_user
say " → Groups after: $(id -nG $docker_user)"
validate $? "docker group assignment"

echo -e "${Y}NOTE:${N} ec2-user must run 'newgrp docker' or reboot the instance to apply group changes."
echo -e "Do NOT log out and log in immediately after this script if using SSH without reboot – it may cause connection issues."

echo ""
say "7. Installing eksctl ..."
[[ -z "$EKSCTL_VERSION" ]] && \
  EKSCTL_VERSION=$(curl -s https://api.github.com/repos/weaveworks/eksctl/releases/latest \
                    | grep -m1 tag_name | cut -d '"' -f4)
EKS_TAR=/tmp/eksctl.tar.gz
cmd curl -sL "https://github.com/weaveworks/eksctl/releases/download/${EKSCTL_VERSION}/eksctl_Linux_amd64.tar.gz" -o "$EKS_TAR"
cmd tar -xzf "$EKS_TAR" -C /tmp
cmd install -m 755 /tmp/eksctl /usr/local/bin/eksctl
validate $? "eksctl"

say "8. Installing kubectl ..."
[[ -z "$KUBECTL_VERSION" ]] && \
  KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
cmd curl -sL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl
cmd chmod 755 /usr/local/bin/kubectl
validate $? "kubectl"

say "9. Installing kubens ..."
cmd git clone --depth 1 https://github.com/ahmetb/kubectx /opt/kubectx
cmd ln -sf /opt/kubectx/kubens /usr/local/bin/kubens
validate $? "kubens"

say "10. Installing Helm ..."
cmd curl -fsSL -o get_helm.sh "$HELM_INSTALL_SCRIPT"
cmd chmod 700 get_helm.sh
cmd ./get_helm.sh
validate $? "helm"

say "${G}✔ All tools installed successfully.${N}"
echo -e "${Y}→ To use Docker without sudo, run: ${N}newgrp docker${Y} or reboot the instance.${N}"
echo "→ Log saved at: $LOGFILE"