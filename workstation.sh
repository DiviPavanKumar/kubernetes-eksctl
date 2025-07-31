#!/bin/bash

# ─────────────────────────────────────────────────────────────
# DevOps Workstation Setup Script for RHEL/CentOS/Amazon Linux
# Installs: Docker Engine, eksctl, kubectl, kubens, k9s
# Author: Pavan Kumar Divi
# ─────────────────────────────────────────────────────────────

# ====== Colors ======
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"
RESET="\e[0m"

# ====== Timestamped log folder ======
LOG_DIR="$HOME/devops-install-logs-$(date +%F-%H-%M-%S)"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/workstation-install.log"

# ====== Check for root/sudo ======
if [[ $EUID -ne 0 ]]; then
  echo -e "${YELLOW}Switching to sudo...${RESET}"
  exec sudo bash "$0" "$@"
fi

# ====== Logging functions ======
log()    { echo -e "${BLUE}[INFO]${RESET} $1" | tee -a "$LOG_FILE"; }
success(){ echo -e "${GREEN}[✔]${RESET} $1" | tee -a "$LOG_FILE"; }
error()  { echo -e "${RED}[✘]${RESET} $1" | tee -a "$LOG_FILE"; }

# ====== Background Execution Using screen ======
if [[ "$1" != "internal" ]]; then
  SCREEN_NAME="devops-install-$(date +%H%M%S)"

  if ! command -v screen &>/dev/null; then
    echo -e "${YELLOW}[WARN] 'screen' not found. Installing it...${RESET}"
    dnf install -y screen >> "$LOG_FILE" 2>&1 || {
      echo -e "${RED}[ERROR] Failed to install 'screen'. Running in foreground...${RESET}"
      bash "$0" internal
      exit 0
    }
  fi

  screen -dmS "$SCREEN_NAME" bash "$0" internal
  echo -e "${GREEN}[INFO]${RESET} Running in screen session: ${BLUE}$SCREEN_NAME${RESET}"
  echo -e "${YELLOW}Use: screen -r $SCREEN_NAME${RESET} to view logs"
  exit 0
fi

# ─────────────────────────────────────────────────────────────
log "Starting DevOps tools installation..."

# ====== Docker Installation ======
log "Removing any old Docker versions..."
dnf remove -y docker docker-client docker-client-latest docker-common \
docker-latest docker-latest-logrotate docker-logrotate docker-engine \
podman runc >> "$LOG_FILE" 2>&1

log "Installing Docker..."
dnf -y install dnf-plugins-core >> "$LOG_FILE" 2>&1
dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo >> "$LOG_FILE" 2>&1
dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >> "$LOG_FILE" 2>&1
systemctl enable --now docker >> "$LOG_FILE" 2>&1
usermod -aG docker ec2-user >> "$LOG_FILE" 2>&1
log "${YELLOW}NOTE:${RESET} Added ec2-user to docker group. Please REBOOT the instance after this script completes."

success "Docker installed successfully."

# ====== eksctl Installation ======
log "Installing eksctl..."
ARCH=amd64
PLATFORM=$(uname -s)_$ARCH
curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl
success "eksctl installed."

# ====== kubectl Installation ======
log "Installing kubectl..."
KUBECTL_VER=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VER}/bin/linux/amd64/kubectl"
curl -LO "https://dl.k8s.io/release/${KUBECTL_VER}/bin/linux/amd64/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check || { error "kubectl checksum failed"; exit 1; }

install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
chmod +x kubectl
mkdir -p ~/.local/bin
mv ./kubectl ~/.local/bin/kubectl
success "kubectl installed. Version: $(kubectl version --client --short)"

# ====== kubens Installation ======
log "Installing kubens..."
curl -sS https://webi.sh/kubens | sh
source ~/.config/envman/PATH.env
success "kubens installed. Usage: kubens"

# ====== Homebrew + k9s Installation ======
if ! command -v brew &>/dev/null; then
  log "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> ~/.bashrc
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  success "Homebrew installed."
else
  success "Homebrew already present."
fi

log "Installing k9s..."
brew install derailed/k9s/k9s >> "$LOG_FILE" 2>&1 && success "k9s installed." || error "k9s install failed."

# ─────────────────────────────────────────────────────────────
log "${GREEN}All tools installed successfully.${RESET}"
log "${YELLOW}Please REBOOT the instance to apply Docker group changes.${RESET}"
log "Logs saved to: $LOG_FILE"