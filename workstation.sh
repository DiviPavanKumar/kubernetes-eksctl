#!/bin/bash

# DevOps Workstation Setup Script for RHEL EC2
# Author: Pavan Kumar Divi | Generated on 2025-07-31 13:00:45

# ───── Colors ─────
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
RESET='\033[0m'

# ───── Logging ─────
TIMESTAMP=$(date +%F-%H-%M-%S)
LOG_DIR="/tmp/devops-install-logs-$TIMESTAMP"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/workstation-install.log"

log()    { echo -e "${BLUE}[INFO]${RESET} $1" | tee -a "$LOG_FILE"; }
success(){ echo -e "${GREEN}[✔]${RESET} $1" | tee -a "$LOG_FILE"; }
error()  { echo -e "${RED}[✘]${RESET} $1" | tee -a "$LOG_FILE"; }

# ───── Root Check ─────
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}Please run this script as root or using sudo${RESET}"
  exit 1
fi

log "Starting DevOps tools installation..."
log "Logs stored at: $LOG_FILE"

# ───── Docker ─────
log "Installing Docker..."
dnf remove -y docker* podman runc >> "$LOG_FILE" 2>&1
dnf -y install dnf-plugins-core >> "$LOG_FILE" 2>&1
dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo >> "$LOG_FILE" 2>&1
dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >> "$LOG_FILE" 2>&1
systemctl enable --now docker >> "$LOG_FILE" 2>&1 && success "Docker service started" || error "Docker service failed"
usermod -aG docker ec2-user >> "$LOG_FILE" 2>&1
log "${YELLOW}NOTE:${RESET} Reboot the EC2 instance to apply Docker group membership"
success "Docker installed successfully"

# ───── eksctl ─────
log "Installing eksctl..."
ARCH=amd64
PLATFORM=$(uname -s)_$ARCH
curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz" >> "$LOG_FILE" 2>&1
tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl
success "eksctl installed"

# ───── kubectl ─────
log "Installing kubectl..."
KUBECTL_VER=$(curl -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VER}/bin/linux/amd64/kubectl" >> "$LOG_FILE" 2>&1
curl -LO "https://dl.k8s.io/release/${KUBECTL_VER}/bin/linux/amd64/kubectl.sha256" >> "$LOG_FILE" 2>&1

if [[ -f "kubectl" && -f "kubectl.sha256" ]]; then
  echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check >> "$LOG_FILE" 2>&1
  chmod +x kubectl
  mv kubectl /usr/local/bin/kubectl
  KUBE_VERSION_OUTPUT=$(kubectl version --client --short 2>/dev/null || echo "Not available")
  success "kubectl installed. Version: $KUBE_VERSION_OUTPUT"
else
  error "kubectl or checksum file missing. Install failed"
fi

# ───── kubens ─────
log "Installing kubens..."
curl -sS https://webi.sh/kubens | sh >> "$LOG_FILE" 2>&1
source ~/.config/envman/PATH.env >> "$LOG_FILE" 2>&1
success "kubens installed"

# ───── Homebrew ─────
log "Installing Homebrew with dependencies..."
dnf install -y gcc git curl file bzip2 >> "$LOG_FILE" 2>&1
export NONINTERACTIVE=1
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" >> "$LOG_FILE" 2>&1

BREW_PREFIX="/home/linuxbrew/.linuxbrew"
if [[ -x "$BREW_PREFIX/bin/brew" ]]; then
  eval "$($BREW_PREFIX/bin/brew shellenv)"
  echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> /etc/profile.d/brew.sh
  success "Homebrew installed and configured"
else
  error "Homebrew install failed or brew not found"
fi

# ───── k9s ─────
log "Installing k9s..."
if command -v brew &>/dev/null; then
  brew install derailed/k9s/k9s >> "$LOG_FILE" 2>&1 && success "k9s installed" || error "k9s installation failed"
else
  error "Skipping k9s: Homebrew not available"
fi

# ───── Done ─────
log "${GREEN}All tools installed successfully.${RESET}"
log "${YELLOW}Please REBOOT the instance to complete Docker group access.${RESET}"
log "View logs: $LOG_FILE"
