#!/usr/bin/env bash
# Run every sweep and render ONE combined image (results/dpdk_all.png):
#   ladder, hugepage size, zero-copy vs copy, batching burst size, lockless vs mutex.
# Run with sudo (DPDK needs hugepages). Takes a few minutes.
#   sudo ./scripts/run_all.sh
set -euo pipefail

export REPS=${REPS:-3}            # median of 3 keeps the full sweep quick
export PKTS=${PKTS:-10000000}
export SIZE=${SIZE:-256}
PIPE=./build/dpdk_pipeline
mkdir -p results

median() { sort -t, -k3 -g | awk "NR==int(($REPS+1)/2)"; }
run() {  # $1=out $2=label  $3..=flags  (median row appended to $1)
    local out=$1 label=$2; shift 2
    local lines=()
    for i in $(seq 1 "$REPS"); do
        # shellcheck disable=SC2046
        lines+=("$("$PIPE" -l 0-2 --no-pci --huge-dir /mnt/huge2M --file-prefix "${label}_${i}_$$" -- \
            --label "$label" --packets "$PKTS" --size "$SIZE" "$@" | tail -1)")
    done
    printf '%s\n' "${lines[@]}" | median >> "$out"
}

# 1 + 2) cumulative ladder and hugepage-size sweep  -> bench.csv
./scripts/run_bench.sh
# 3) zero-copy vs copy across payload size          -> zerocopy.csv
./scripts/run_zerocopy.sh

# 4) batching: sweep burst size                     -> burst.csv
echo "config,packets,mpps,gbps,ns_per_pkt,size,burst" > results/burst.csv
for b in 1 2 4 8 16 32 64; do run results/burst.csv batching --burst "$b"; done

# 5) lockless ring vs mutex, across burst size      -> lockless.csv
echo "config,packets,mpps,gbps,ns_per_pkt,size,burst" > results/lockless.csv
for b in 1 2 4 8 16 32; do
    run results/lockless.csv ring  --burst "$b"
    run results/lockless.csv mutex --burst "$b" --locked-queue
done

python3 results/plot_all.py
