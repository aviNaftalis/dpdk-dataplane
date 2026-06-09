#!/usr/bin/env python3
"""Zero-copy vs copy throughput as payload size grows.

    python3 results/plot_zerocopy.py [results/zerocopy.csv]
"""
import csv
import sys
from collections import defaultdict

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "results/zerocopy.csv"
    series = defaultdict(list)  # config -> [(size, gbps)]
    for r in csv.DictReader(open(src)):
        series[r["config"]].append((int(r["size"]), float(r["gbps"])))
    if not series:
        sys.exit(f"no rows in {src} — run scripts/run_zerocopy.sh first")

    plt.figure(figsize=(8, 5))
    for name, pts in sorted(series.items()):
        pts.sort()
        xs, ys = zip(*pts)
        plt.plot(xs, ys, marker="o", label=name)
    plt.xscale("log", base=2)
    plt.xlabel("payload size (bytes)")
    plt.ylabel("throughput (Gbps)")
    plt.title("Zero-copy vs copy — the gap grows with payload")
    plt.legend()
    plt.grid(True, which="both", alpha=0.3)
    plt.tight_layout()
    plt.savefig("results/zerocopy.png", dpi=120)
    print("wrote results/zerocopy.png")


if __name__ == "__main__":
    main()
