#!/usr/bin/env bash
# Run every sweep and render ONE image (results/dpdk_all.png) with four panels:
#   1. cumulative techniques (Mpps)        3. lockless ring vs mutex (Mpps vs burst)
#   2. batching: burst size (Mpps)         4. OPTIMAL MAP: per-packet time vs payload
#                                              size, one line per page-size x copy-mode
#                                              -> lowest line = best config for that size
# Run with sudo (DPDK needs hugepages). Takes a few minutes.
set -euo pipefail

export REPS=${REPS:-3}
export PKTS=${PKTS:-10000000}
export SIZE=${SIZE:-256}
BUDGET=${BUDGET:-2000000000}   # ~2 GB moved per run (so big payloads stay quick)
PIPE=./build/dpdk_pipeline
mkdir -p results
H="config,packets,mpps,gbps,ns_per_pkt,size,burst"

eal_page() {
    case "$1" in
        4k) echo "--no-huge -m 1024" ;;
        2m) echo "--huge-dir /mnt/huge2M" ;;
        1g) echo "--huge-dir /mnt/huge1G" ;;
    esac
}
median() { sort -t, -k3 -g | awk "NR==int(($REPS+1)/2)"; }
run() {  # $1=out $2=label $3=page $4=size  $5..=flags
    local out=$1 label=$2 page=$3 size=$4; shift 4
    local pkts=$((BUDGET / size)); [ "$pkts" -lt 50000 ] && pkts=50000
    local tag="${label//[^a-zA-Z0-9]/_}_${size}"
    local lines=()
    for i in $(seq 1 "$REPS"); do
        # shellcheck disable=SC2046
        lines+=("$("$PIPE" -l 0-2 --no-pci --log-level '*:error' $(eal_page "$page") \
            --file-prefix "${tag}_${i}_$$" -- \
            --label "$label" --packets "$pkts" --size "$size" "$@" | tail -1)")
    done
    printf '%s\n' "${lines[@]}" | median >> "$out"
}

# 1) cumulative ladder (kernel-udp + DPDK steps), one page only -> bench.csv
PAGES=2m ./scripts/run_bench.sh

# 2) batching: burst size -> burst.csv
echo "$H" > results/burst.csv
BURSTS=${BURSTS:-"1 2 4 8 16 32 64"}
for b in $BURSTS; do run results/burst.csv batching 2m 256 --burst "$b"; done

# 3) lockless ring vs mutex across burst -> lockless.csv
echo "$H" > results/lockless.csv
for b in 1 2 4 8 16 32; do
    run results/lockless.csv ring  2m 256 --burst "$b"
    run results/lockless.csv mutex 2m 256 --burst "$b" --locked-queue
done

# 4) OPTIMAL MAP: page-size x copy-mode across payload size -> optimal.csv
echo "$H" > results/optimal.csv
SIZES=${SIZES:-"64 256 1024 4096 16384 65000"}
PAGES=${PAGES:-"4k 2m"}
for pg in $PAGES; do
    [ "$pg" = 1g ] && ! mountpoint -q /mnt/huge1G 2>/dev/null && continue
    for sz in $SIZES; do
        run results/optimal.csv "$pg-copy"     "$pg" "$sz" --copy
        run results/optimal.csv "$pg-zerocopy" "$pg" "$sz"
    done
done

python3 results/plot_all.py
