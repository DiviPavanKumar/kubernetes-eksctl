#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "🔧 Step 1: Installing Docker..."

# Update package list
sudo yum update -y

# Install Docker
sudo yum install -y docker

# Enable and start Docker service
sudo systemctl enable docker
sudo systemctl start docker

echo "✅ Docker installed and running."

# Add current user (ec2-user) to docker group to run Docker without sudo
echo "➕ Adding ec2-user to docker group..."
sudo usermod -aG docker ec2-user

# Apply group changes without logout/login
# 'newgrp docker' starts a new shell with the new group applied
# Using heredoc to execute in same script
echo "🔄 Applying group changes for docker without logout..."
newgrp docker <<EONG
echo "✅ Group change applied using 'newgrp docker'. Docker is now usable without sudo."
EONG

echo "🐳 Docker setup complete."

# --------------------------------------------------------------------

echo "🔧 Step 2: Installing kubectl (Kubernetes CLI)..."

# Download the latest stable kubectl binary (from AWS EKS repo)
curl -o kubectl https://s3.us-west-2.amazonaws.com/amazon-eks/1.29.1/2024-05-31/bin/linux/amd64/kubectl

# Make the binary executable
chmod +x kubectl

# Move it to a directory in PATH
sudo mv kubectl /usr/local/bin/

# Verify installation
echo "✅ kubectl installed. Version:"
kubectl version --client

# --------------------------------------------------------------------

echo "🔧 Step 3: Installing eksctl (EKS management CLI)..."

# Download and extract the latest eksctl release
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz

# Move the binary to PATH
sudo mv eksctl /usr/local/bin

# Verify installation
echo "✅ eksctl installed. Version:"
eksctl version

# --------------------------------------------------------------------

echo "🎉 All tools installed successfully: Docker, kubectl, eksctl."
echo "📌 Note: If you're using SSH, and 'docker' command still needs sudo,"
echo "         run this command manually in your terminal:"
echo "         👉 newgrp docker"