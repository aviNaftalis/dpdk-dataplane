#!/usr/bin/env python3
"""One image, four panels, from the CSVs scripts/run_all.sh writes.

    python3 results/plot_all.py   ->  results/dpdk_all.png
"""
import csv
import os
from collections import defaultdict

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def rows(path):
    return list(csv.DictReader(open(path))) if os.path.exists(path) else []


def main():
    fig, ax = plt.subplots(2, 2, figsize=(15, 11))
    a = ax.flat

    # 1) cumulative ladder (Mpps)
    ladder = [r for r in rows("results/bench.csv") if not r["config"].startswith("page")]
    if ladder:
        a[0].bar([r["config"] for r in ladder], [float(r["mpps"]) for r in ladder])
        a[0].set_title("Cumulative techniques"); a[0].set_ylabel("Mpps")
        a[0].tick_params(axis="x", rotation=45)
        for lbl in a[0].get_xticklabels():
            lbl.set_ha("right")

    # 2) batching: burst size (Mpps)
    burst = rows("results/burst.csv")
    if burst:
        pts = sorted((int(r["burst"]), float(r["mpps"])) for r in burst)
        xs, ys = zip(*pts)
        a[1].plot(xs, ys, marker="o")
        a[1].set_xscale("log", base=2)
        a[1].set_title("Batching: burst size"); a[1].set_xlabel("burst"); a[1].set_ylabel("Mpps")
        a[1].grid(True, which="both", alpha=0.3)

    # 3) lockless ring vs mutex (Mpps vs burst)
    lock = defaultdict(list)
    for r in rows("results/lockless.csv"):
        lock[r["config"]].append((int(r["burst"]), float(r["mpps"])))
    for name, pts in sorted(lock.items()):
        pts.sort(); xs, ys = zip(*pts); a[2].plot(xs, ys, marker="o", label=name)
    if lock:
        a[2].set_xscale("log", base=2); a[2].legend()
        a[2].set_title("Lockless ring vs mutex"); a[2].set_xlabel("burst"); a[2].set_ylabel("Mpps")
        a[2].grid(True, which="both", alpha=0.3)

    # 4) optimal map: per-packet time vs payload, line per page-size x copy-mode
    opt = defaultdict(list)
    for r in rows("results/optimal.csv"):
        opt[r["config"]].append((int(r["size"]), float(r["ns_per_pkt"])))
    for name, pts in sorted(opt.items()):
        pts.sort(); xs, ys = zip(*pts); a[3].plot(xs, ys, marker="o", label=name)
    if opt:
        a[3].set_xscale("log", base=2); a[3].set_yscale("log"); a[3].legend()
        a[3].set_title("Optimal config per payload (lowest line wins)")
        a[3].set_xlabel("payload size (bytes)"); a[3].set_ylabel("per-packet time (ns)")
        a[3].grid(True, which="both", alpha=0.3)

    fig.suptitle("DPDK data plane — techniques, and the best config for each data size", fontsize=15)
    fig.tight_layout()
    fig.savefig("results/dpdk_all.png", dpi=110)
    print("wrote results/dpdk_all.png")


if __name__ == "__main__":
    main()
