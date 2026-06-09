# dpdk-dataplane

**How to process packets ~30× faster than the kernel** — and a measurement of
*what each technique actually buys you*.

Sending packets through the kernel network stack means a syscall and a copy per
packet, plus interrupts and scheduler jitter. [DPDK](https://www.dpdk.org "Data Plane Development Kit — userspace poll-mode packet processing")
bypasses all of that: a userspace **poll-mode** driver, **zero-copy** buffers,
**hugepages**, **lockless rings**, **batching**, and **pinned cores**. This repo
builds the same packet-processing pipeline every way — kernel sockets, a naive
userspace version, and DPDK with each technique toggled — and benchmarks them.

Runs on a plain Linux box or **WSL2 — no special hardware, no NIC, no VM.**

## Results

![DPDK data plane results](results/dpdk_all.png)

One run of `sudo ./scripts/run_all.sh` produces the chart above:

- **Cumulative techniques** — start from the OS default (`kernel-udp`) and a
  naive userspace pipeline, then add one technique at a time. Each rung is a real
  jump; kernel-bypass + lockless ring + batching together give the headline ~30×.
- **Hugepage size** — 4 KB vs 2 MB vs 1 GB pages on the optimized pipeline (fewer
  TLB misses → higher throughput).
- **Zero-copy vs copy** — flat at small packets (a copy is ~free), but the gap
  grows fast with payload size: it's a *per-byte* technique.
- **Batching** — throughput vs burst size; amortizing per-packet overhead rises,
  then plateaus.
- **Lockless ring vs mutex** — the mutex hurts most at burst 1 (a lock per
  packet); the gap shrinks as batching amortizes it.

Takeaway: **kernel bypass and avoiding per-packet overhead (lockless + batching)
are the big wins; zero-copy and hugepages matter in their own regimes.** Each
technique has a regime where it shines — that's the whole point of measuring them
separately.

> [!NOTE]
> Cumulative ablation is order-dependent: whichever technique removes the current
> bottleneck gets the biggest rung. The ladder shows contribution, not a fixed ranking.

## Reproduce

```bash
./scripts/setup.sh                  # install DPDK + tools (WSL2 is fine)
sudo ./scripts/hugepages.sh 2m 1024 # reserve 2 GB of 2 MB hugepages
make
sudo ./scripts/run_all.sh           # all sweeps -> results/dpdk_all.png
```

> [!NOTE]
> 4 KB and 2 MB pages work directly in WSL2. **1 GB** pages need a boot-time
> reservation — add `kernelCommandLine = default_hugepagesz=1G hugepagesz=1G hugepages=4`
> under `[wsl2]` in `.wslconfig`, then `wsl --shutdown`. The 1 GB bar is skipped
> if unavailable.

## How it's built

- `src/dpdk_pipeline.c` — producer lcore → queue → consumer lcore. Flags toggle
  each technique: `--malloc` (vs `rte_mempool`), `--locked-queue` (vs `rte_ring`),
  `--burst N`, `--copy` (vs zero-copy), `--no-pin`; page size via EAL.
- `src/udp_bench.c` — kernel UDP-loopback baseline (no DPDK).
- `scripts/run_all.sh` → CSVs in `results/`; `results/plot_all.py` → the image.

Sibling repo: [rdma-matmul](https://github.com/aviNaftalis/rdma-matmul) — the same
kernel-bypass idea applied to *remote memory* (RDMA) instead of packets.
