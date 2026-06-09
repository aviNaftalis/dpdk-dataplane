# dpdk-dataplane

A kernel-bypass packet-processing benchmark: measure how fast a software data
plane moves and processes packets, and **isolate what each
[DPDK](https://www.dpdk.org "Data Plane Development Kit — userspace poll-mode packet processing") technique
contributes** — zero-copy, batching, lockless rings, core pinning, hugepage size.

Sibling to [rdma-matmul](https://github.com/aviNaftalis/rdma-matmul): both are
**kernel-bypass** data planes — DPDK for packet I/O, RDMA for remote memory.

## What it compares

Same workload (generate packets → parse header → light per-packet transform),
three data planes, fastest last:

| Data plane | how packets move + are processed |
|---|---|
| **kernel UDP** | loopback sockets — the OS default (syscall + copy per packet) |
| **naive userspace** | `malloc`/`free`, `std::mutex`+`std::queue`, one at a time, copy |
| **DPDK** | `rte_mempool` mbufs, `rte_ring` (lockless), burst of 32, zero-copy, pinned lcores, hugepages |

Then DPDK with one technique disabled at a time, to measure its contribution:

| Flag | technique isolated |
|---|---|
| `--burst 1` | batching |
| `--copy` | zero-copy |
| `--locked-queue` | lockless ring |
| `--no-pin` | core pinning |
| `--page 4k\|2m\|1g` | hugepage size (TLB pressure) |

**Metrics:** Mpps, Gbps, ns/packet, CPU cycles/packet. Charts for each axis.

## Setup — WSL2, no VM, no NIC

Needs only DPDK + hugepages; no network card, so no `vfio` and no VM.

```bash
./scripts/setup.sh                 # install DPDK + tools
sudo ./scripts/hugepages.sh 2m 1024
# build + run (coming next): meson build && ninja -C build && ./scripts/run_bench.sh
```

> [!NOTE]
> 4 KB and 2 MB pages work directly in WSL2. **1 GB** pages need a boot-time
> reservation — add `kernelCommandLine = default_hugepagesz=1G hugepagesz=1G hugepages=4`
> under `[wsl2]` in `.wslconfig`, then `wsl --shutdown`. If your WSL kernel
> can't do 1 GB, run that one case in a VM. `hugepages.sh` prints this when needed.

## Roadmap

- [x] Setup: DPDK install + parametrized hugepages (4k/2m/1g)
- [ ] Benchmark binary: kernel-UDP + naive + DPDK pipeline, technique toggles
- [ ] Runner sweeps the matrix → CSV
- [ ] Graphs: Mpps by technique, Mpps by page size, cycles/packet
- [ ] Correctness test on the per-packet transform
