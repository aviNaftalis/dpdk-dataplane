#!/usr/bin/env bash
# Sweep the comparison and write results/bench.csv. Two stories:
#   1. cumulative build-up: naive -> +mempool -> +lockless -> +batching ->
#      +zerocopy -> +pinned(full), one technique added per step.
#   2. page-size sweep (4k/2m/1g) on full DPDK.
# Each config runs REPS times; we keep the MEDIAN by Mpps so noise can't invert
# the order. Needs: make (built) + hugepages (scripts/hugepages.sh 2m ...).
set -euo pipefail

PKTS=${PKTS:-10000000}
SIZE=${SIZE:-256}        # big enough that zero-copy has a copy worth avoiding
REPS=${REPS:-5}
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

median() { sort -t, -k3 -g | awk "NR==int(($REPS+1)/2)"; }  # middle line by Mpps

med_dpdk() {  # $1=label $2=page  $3..=app flags
    local label=$1 page=$2; shift 2
    local lines=()
    for i in $(seq 1 "$REPS"); do
        # shellcheck disable=SC2046
        lines+=("$("$PIPE" -l 0-2 --no-pci $(eal_page "$page") --file-prefix "${label}_$i" -- \
            --label "$label" --packets "$PKTS" --size "$SIZE" "$@" | tail -1)")
    done
    printf '%s\n' "${lines[@]}" | median | tee -a "$OUT"
}

med_udp() {
    local lines=()
    for i in $(seq 1 "$REPS"); do
        lines+=("$("$UDP" --label kernel-udp --packets "$PKTS" --size "$SIZE" | tail -1)")
    done
    printf '%s\n' "${lines[@]}" | median | tee -a "$OUT"
}

echo "config,packets,mpps,gbps,ns_per_pkt" | tee "$OUT"

med_udp   # OS-default reference

# cumulative build-up: each step removes one "disable" flag
med_dpdk 0-naive        2m --malloc --locked-queue --burst 1 --copy --no-pin
med_dpdk 1-mempool      2m --locked-queue --burst 1 --copy --no-pin
med_dpdk 2-lockless     2m --burst 1 --copy --no-pin
med_dpdk 3-batching     2m --copy --no-pin
med_dpdk 4-zerocopy     2m --no-pin
med_dpdk 5-pinned-full  2m

# page-size sweep on full DPDK
med_dpdk page-4k 4k
med_dpdk page-2m 2m
med_dpdk page-1g 1g || echo "(page-1g skipped — reserve 1G hugepages first)"

echo "wrote $OUT"
