#!/bin/bash

# DevOps Workstation Setup Script for RHEL EC2
# Installs Docker Engine, eksctl, kubectl, kubens, k9s
# Author: Pavan Kumar Divi

# ─────────────────────────────────────────────────────────────
# Color codes
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"
RESET="\e[0m"

# Timestamped logs in /tmp
LOG_DIR="/tmp/devops-install-logs-$(date +%F-%H-%M-%S)"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/workstation-install.log"

# Logging helpers
log()    { echo -e "${BLUE}[INFO]${RESET} $1" | tee -a "$LOG_FILE"; }
success(){ echo -e "${GREEN}[✔]${RESET} $1" | tee -a "$LOG_FILE"; }
error()  { echo -e "${RED}[✘]${RESET} $1" | tee -a "$LOG_FILE"; }

# Require sudo/root
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}Please run this script with sudo or as root${RESET}"
  exit 1
fi

# ─────────────────────────────────────────────────────────────
log "Starting DevOps tools installation..."
log "Logs stored in: $LOG_FILE"

# ====== Docker ======
log "Installing Docker Engine..."
dnf remove -y docker docker-client docker-client-latest docker-common \
docker-latest docker-latest-logrotate docker-logrotate docker-engine \
podman runc >> "$LOG_FILE" 2>&1

dnf -y install dnf-plugins-core >> "$LOG_FILE" 2>&1
dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo >> "$LOG_FILE" 2>&1
dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >> "$LOG_FILE" 2>&1
systemctl enable --now docker >> "$LOG_FILE" 2>&1
usermod -aG docker ec2-user >> "$LOG_FILE" 2>&1

success "Docker installed successfully"
log "${YELLOW}Note: Reboot the EC2 instance to apply Docker group membership for ec2-user${RESET}"

# ====== eksctl ======
log "Installing eksctl..."
ARCH=amd64
PLATFORM=$(uname -s)_$ARCH
curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz" >> "$LOG_FILE" 2>&1
tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl

success "eksctl installed"

# ====== kubectl ======
log "Installing kubectl..."
KUBECTL_VER=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VER}/bin/linux/amd64/kubectl" >> "$LOG_FILE" 2>&1
curl -LO "https://dl.k8s.io/release/${KUBECTL_VER}/bin/linux/amd64/kubectl.sha256" >> "$LOG_FILE" 2>&1
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check >> "$LOG_FILE" 2>&1

install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
chmod +x kubectl
mkdir -p ~/.local/bin
mv ./kubectl ~/.local/bin/kubectl

success "kubectl installed. Version: $(kubectl version --client --short)"

# ====== kubens ======
log "Installing kubens..."
curl -sS https://webi.sh/kubens | sh >> "$LOG_FILE" 2>&1
source ~/.config/envman/PATH.env >> "$LOG_FILE" 2>&1
success "kubens installed"

# ====== Homebrew & k9s ======
if ! command -v brew &>/dev/null; then
  log "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" >> "$LOG_FILE" 2>&1
  echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> ~/.bashrc
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  success "Homebrew installed"
else
  success "Homebrew already installed"
fi

log "Installing k9s..."
brew install derailed/k9s/k9s >> "$LOG_FILE" 2>&1 && success "k9s installed" || error "k9s installation failed"

# ─────────────────────────────────────────────────────────────
log "${GREEN}All tools installed successfully.${RESET}"
log "${YELLOW}Please reboot the instance for Docker group changes to take effect.${RESET}"
log "Installation logs: $LOG_FILE"
