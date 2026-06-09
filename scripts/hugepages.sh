#!/usr/bin/env bash
# Reserve + mount hugepages for a given size so we can benchmark page size as a
# variable.  sudo ./scripts/hugepages.sh <4k|2m|1g> [count]
#   sudo ./scripts/hugepages.sh 2m 1024   # 1024 x 2M = 2 GB
#   sudo ./scripts/hugepages.sh 1g 4      # 4 x 1G  (needs boot-time reservation)
set -euo pipefail

size=${1:-2m}
count=${2:-1024}

case "$size" in
  4k)
    echo "4 KB: nothing to reserve — run the benchmark with --page 4k (DPDK --no-huge)."
    ;;
  2m)
    echo "$count" | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages >/dev/null
    sudo mkdir -p /mnt/huge2M
    mountpoint -q /mnt/huge2M || sudo mount -t hugetlbfs -o pagesize=2M none /mnt/huge2M
    ;;
  1g)
    echo "$count" | sudo tee /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages >/dev/null 2>&1 || true
    got=$(cat /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages 2>/dev/null || echo 0)
    if [[ "$got" -lt "$count" ]]; then
      echo "!! 1G pages unavailable at runtime (got $got). Reserve at boot:"
      echo "   WSL2: in %USERPROFILE%\\.wslconfig under [wsl2]:"
      echo "           kernelCommandLine = default_hugepagesz=1G hugepagesz=1G hugepages=$count"
      echo "         then run:  wsl --shutdown"
      echo "   VM/bare metal: add the same to the GRUB cmdline and reboot."
      exit 1
    fi
    sudo mkdir -p /mnt/huge1G
    mountpoint -q /mnt/huge1G || sudo mount -t hugetlbfs -o pagesize=1G none /mnt/huge1G
    ;;
  *)
    echo "usage: $0 <4k|2m|1g> [count]"; exit 2 ;;
esac

grep -i huge /proc/meminfo
