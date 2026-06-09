#!/usr/bin/env bash
# Install DPDK + build tools (Ubuntu/Debian). Works in WSL2 — no VM, no NIC.
set -euo pipefail

sudo apt-get update
sudo apt-get install -y build-essential meson ninja-build pkg-config \
    libdpdk-dev dpdk python3-matplotlib

echo
pkg-config --modversion libdpdk >/dev/null 2>&1 \
    && echo "DPDK $(pkg-config --modversion libdpdk) ready" \
    || { echo "libdpdk pkg-config not found"; exit 1; }
echo "Next: sudo ./scripts/hugepages.sh 2m 1024   (then build + run)"
