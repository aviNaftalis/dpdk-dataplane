#!/usr/bin/env python3
"""One image with every DPDK result: ladder, page size, zero-copy, batching,
lockless-vs-mutex. Reads the CSVs produced by scripts/run_all.sh.

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


def lines(ax, data, key, xlog=True):
    s = defaultdict(list)
    for r in data:
        s[r["config"]].append((int(r[key]), float(r["mpps"]) if key == "burst" else float(r["gbps"])))
    for name, pts in sorted(s.items()):
        pts.sort()
        xs, ys = zip(*pts)
        ax.plot(xs, ys, marker="o", label=name)
    if xlog:
        ax.set_xscale("log", base=2)
    ax.legend()
    ax.grid(True, which="both", alpha=0.3)


def main():
    bench = rows("results/bench.csv")
    fig, ax = plt.subplots(2, 3, figsize=(18, 10))
    a = ax.flat

    ladder = [r for r in bench if not r["config"].startswith("page")]
    if ladder:
        a[0].bar([r["config"] for r in ladder], [float(r["mpps"]) for r in ladder])
        a[0].set_title("Cumulative techniques"); a[0].set_ylabel("Mpps")

    pages = [r for r in bench if r["config"].startswith("page")]
    if pages:
        a[1].bar([r["config"] for r in pages], [float(r["mpps"]) for r in pages])
        a[1].set_title("Hugepage size (optimized pipeline)"); a[1].set_ylabel("Mpps")

    zc = rows("results/zerocopy.csv")
    if zc:
        lines(a[2], zc, "size")
        a[2].set_title("Zero-copy vs copy"); a[2].set_xlabel("payload (B)"); a[2].set_ylabel("Gbps")

    burst = rows("results/burst.csv")
    if burst:
        pts = sorted((int(r["burst"]), float(r["mpps"])) for r in burst)
        xs, ys = zip(*pts)
        a[3].plot(xs, ys, marker="o")
        a[3].set_xscale("log", base=2)
        a[3].set_title("Batching: burst size"); a[3].set_xlabel("burst"); a[3].set_ylabel("Mpps")
        a[3].grid(True, which="both", alpha=0.3)

    lock = rows("results/lockless.csv")
    if lock:
        lines(a[4], lock, "burst")
        a[4].set_title("Lockless ring vs mutex"); a[4].set_xlabel("burst"); a[4].set_ylabel("Mpps")

    a[5].axis("off")
    for x in a[:5]:
        x.tick_params(axis="x", rotation=45)
        for lbl in x.get_xticklabels():
            lbl.set_ha("right")
    fig.suptitle("DPDK data plane — kernel bypass, and what each technique buys", fontsize=15)
    fig.tight_layout()
    fig.savefig("results/dpdk_all.png", dpi=110)
    print("wrote results/dpdk_all.png")


if __name__ == "__main__":
    main()
