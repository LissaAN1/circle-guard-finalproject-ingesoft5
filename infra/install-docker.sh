#!/usr/bin/env bash
# Idempotent Docker Engine + Compose plugin install for Ubuntu 24.04.
# Usage: install-docker.sh [SWAP_GB]   (runs as root, e.g. from user-data)
set -euo pipefail
SWAP_GB="${1:-2}"
export DEBIAN_FRONTEND=noninteractive

if ! command -v docker >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg lsb-release git
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi
systemctl enable --now docker
id ubuntu >/dev/null 2>&1 && usermod -aG docker ubuntu

# Neo4j/SonarQube/Elasticsearch need this kernel setting
sysctl -w vm.max_map_count=262144 >/dev/null
grep -q '^vm.max_map_count' /etc/sysctl.conf || echo 'vm.max_map_count=262144' >> /etc/sysctl.conf

if [[ "$SWAP_GB" -gt 0 ]] && ! swapon --show | grep -q /swapfile; then
  fallocate -l "${SWAP_GB}G" /swapfile
  chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
touch /var/lib/cloud/instance/circleguard-bootstrap.done
