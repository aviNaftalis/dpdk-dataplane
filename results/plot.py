#!/usr/bin/env python3
"""Bar charts from results/bench.csv: throughput and per-packet cost by config.

    python3 results/plot.py [results/bench.csv]
"""
import csv
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "results/bench.csv"
    rows = list(csv.DictReader(open(src)))
    if not rows:
        sys.exit(f"no rows in {src} — run scripts/run_bench.sh first")

    labels = [r["config"] for r in rows]
    mpps = [float(r["mpps"]) for r in rows]
    ns = [float(r["ns_per_pkt"]) for r in rows]

    fig, (a1, a2) = plt.subplots(1, 2, figsize=(14, 6))
    a1.bar(labels, mpps)
    a1.set_ylabel("throughput (Mpps)")
    a1.set_title("Throughput — cumulative techniques + page size")
    a2.bar(labels, ns)
    a2.set_ylabel("ns / packet")
    a2.set_title("Per-packet time (lower is better)")
    for ax in (a1, a2):
        ax.tick_params(axis="x", rotation=45)
        for lbl in ax.get_xticklabels():
            lbl.set_ha("right")
    fig.suptitle("DPDK data plane — technique contributions & page size")
    fig.tight_layout()
    fig.savefig("results/dpdk_results.png", dpi=120)
    print("wrote results/dpdk_results.png")


if __name__ == "__main__":
    main()
