#!/usr/bin/env bash
# Sweep the comparison matrix and write results/bench.csv:
#   kernel UDP -> naive userspace -> DPDK full -> DPDK minus each technique
#   -> DPDK across page sizes (4k/2m/1g).
# Needs: make (built), and hugepages reserved (scripts/hugepages.sh 2m ...).
set -euo pipefail

PKTS=${PKTS:-20000000}
SIZE=${SIZE:-64}
PIPE=./build/dpdk_pipeline
UDP=./build/udp_bench
OUT=results/bench.csv
mkdir -p results

eal_page() {  # page size -> EAL hugepage flag
    case "$1" in
        4k) echo "--no-huge -m 1024" ;;
        2m) echo "--huge-dir /mnt/huge2M" ;;
        1g) echo "--huge-dir /mnt/huge1G" ;;
    esac
}

run_dpdk() {  # $1=label $2=page  $3..=app flags
    local label=$1 page=$2; shift 2
    # shellcheck disable=SC2046
    "$PIPE" -l 0-2 --no-pci $(eal_page "$page") --file-prefix "$label" -- \
        --label "$label" --packets "$PKTS" --size "$SIZE" "$@" | tee -a "$OUT"
}

echo "config,packets,mpps,gbps,cycles_per_pkt" | tee "$OUT"

"$UDP" --label kernel-udp --packets "$PKTS" --size "$SIZE" | tee -a "$OUT"

# naive userspace: every technique off
run_dpdk naive 2m --malloc --locked-queue --copy --burst 1 --no-pin

# full DPDK, then remove one technique at a time
run_dpdk dpdk-full    2m
run_dpdk no-batching  2m --burst 1
run_dpdk no-zerocopy  2m --copy
run_dpdk locked-queue 2m --locked-queue
run_dpdk no-pin       2m --no-pin

# page-size sweep (full DPDK on each)
run_dpdk page-4k 4k
run_dpdk page-2m 2m
run_dpdk page-1g 1g || echo "(page-1g skipped — reserve 1G hugepages first)"

echo "wrote $OUT"
