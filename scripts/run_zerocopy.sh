#!/usr/bin/env bash
# Zero-copy vs copy as the payload grows: its win is ~free at 256B but huge at
# 64KB. Each size moves a fixed ~2GB (packet count = budget/size) so runs stay
# short. Writes results/zerocopy.csv. Median of REPS by Mpps.
set -euo pipefail

REPS=${REPS:-5}
BUDGET=${BUDGET:-2000000000}   # ~2 GB moved per run
PIPE=./build/dpdk_pipeline
OUT=results/zerocopy.csv
mkdir -p results

median() { sort -t, -k3 -g | awk "NR==int(($REPS+1)/2)"; }

run() {  # $1=label $2=size  $3..=flags
    local label=$1 size=$2; shift 2
    local pkts=$((BUDGET / size))
    [ "$pkts" -lt 20000 ] && pkts=20000
    local lines=()
    for i in $(seq 1 "$REPS"); do
        lines+=("$("$PIPE" -l 0-2 --no-pci --huge-dir /mnt/huge2M --file-prefix "${label}_${size}_$i" -- \
            --label "$label" --packets "$pkts" --size "$size" "$@" | tail -1)")
    done
    printf '%s\n' "${lines[@]}" | median | tee -a "$OUT"
}

echo "config,packets,mpps,gbps,ns_per_pkt,size" | tee "$OUT"
for sz in 256 1024 4096 16384 65000; do
    run copy     "$sz" --copy   # consumer memcpy's the payload
    run zerocopy "$sz"          # consumer works in place
done
echo "wrote $OUT — plot with: python3 results/plot_zerocopy.py"
