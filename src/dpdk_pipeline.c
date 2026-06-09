// DPDK packet-processing pipeline with per-technique toggles, so each can be
// switched off to measure its contribution. producer lcore -> queue -> consumer
// lcore; each "packet" gets a light per-packet transform. Reports Mpps, Gbps,
// and CPU cycles/packet.
//
// Techniques (default = all on; flags disable one at a time):
//   mempool mbufs (--malloc off it), rte_ring lockless (--locked-queue),
//   burst (--burst 1), zero-copy (--copy forces a per-packet memcpy),
//   pinned lcores (--no-pin runs floating pthreads).
// Hugepage size is an EAL choice: --no-huge (4k) or --huge-dir (2m/1g) — set by
// the runner. EAL args come before `--`, app args after:
//   ./dpdk_pipeline -l 0-2 --no-huge -- --label dpdk --packets 20000000 --burst 32
#include <getopt.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <rte_cycles.h>
#include <rte_eal.h>
#include <rte_lcore.h>
#include <rte_mbuf.h>
#include <rte_mempool.h>
#include <rte_ring.h>

#define MAX_PKT 65000u  // mbuf data room is uint16_t — cap a bit below 64 KB
#define RING_SZ 4096u   // power of two

static struct {
    unsigned burst, size;
    uint64_t packets;
    int copy, locked_queue, use_malloc, no_pin;
    const char *label;
} cfg = {.burst = 32, .size = 64, .packets = 20000000ull, .label = "dpdk"};

static struct rte_mempool *pool;
static struct rte_ring *ring;

// Mutex-guarded ring buffer for the --locked-queue ablation.
static void *lq[RING_SZ];
static uint64_t lq_head, lq_tail;
static pthread_mutex_t lq_lock = PTHREAD_MUTEX_INITIALIZER;

static volatile uint64_t produced, consumed, checksum;

static inline void *alloc_pkt(void) {
    return cfg.use_malloc ? malloc(cfg.size) : rte_pktmbuf_alloc(pool);
}
static inline void free_pkt(void *p) {
    if (cfg.use_malloc) free(p);
    else rte_pktmbuf_free((struct rte_mbuf *)p);
}
static inline uint8_t *pkt_data(void *p) {
    return cfg.use_malloc ? (uint8_t *)p
                          : rte_pktmbuf_mtod((struct rte_mbuf *)p, uint8_t *);
}

static unsigned q_enqueue(void **objs, unsigned n) {
    if (!cfg.locked_queue) return rte_ring_enqueue_burst(ring, objs, n, NULL);
    unsigned done = 0;
    pthread_mutex_lock(&lq_lock);
    while (done < n && (lq_head - lq_tail) < RING_SZ) lq[lq_head++ & (RING_SZ - 1)] = objs[done++];
    pthread_mutex_unlock(&lq_lock);
    return done;
}
static unsigned q_dequeue(void **objs, unsigned n) {
    if (!cfg.locked_queue) return rte_ring_dequeue_burst(ring, objs, n, NULL);
    unsigned done = 0;
    pthread_mutex_lock(&lq_lock);
    while (done < n && lq_head != lq_tail) objs[done++] = lq[lq_tail++ & (RING_SZ - 1)];
    pthread_mutex_unlock(&lq_lock);
    return done;
}

static int producer(void *arg) {
    (void)arg;
    void *batch[256];
    uint64_t made = 0;
    while (made < cfg.packets) {
        unsigned want = cfg.burst;
        if (made + want > cfg.packets) want = (unsigned)(cfg.packets - made);
        unsigned got = 0;
        while (got < want) {
            void *p = alloc_pkt();
            if (!p) continue;  // pool momentarily drained; consumer will free
            uint8_t *d = pkt_data(p);
            d[0] = 64;                   // fake TTL field
            d[1] = (uint8_t)made;        // touch a second byte
            batch[got++] = p;
        }
        unsigned sent = 0;
        while (sent < want) sent += q_enqueue(batch + sent, want - sent);
        made += want;
    }
    produced = made;
    return 0;
}

static int consumer(void *arg) {
    (void)arg;
    void *batch[256];
    uint8_t scratch[MAX_PKT];
    uint64_t done = 0, sum = 0;
    while (done < cfg.packets) {
        unsigned n = q_dequeue(batch, cfg.burst);
        if (!n) continue;  // ring empty; producer will fill
        for (unsigned i = 0; i < n; i++) {
            uint8_t *d = pkt_data(batch[i]);
            if (cfg.copy) { memcpy(scratch, d, cfg.size); d = scratch; }
            d[0]--;            // "decrement TTL" — the per-packet work
            sum += d[0] + d[1];
            free_pkt(batch[i]);
        }
        done += n;
    }
    consumed = done;
    checksum = sum;
    return 0;
}

// --no-pin path: register the float threads so they keep the mempool per-core
// cache — otherwise this would measure "no cache" instead of "no affinity".
static void *pth_producer(void *a) { rte_thread_register(); producer(a); return NULL; }
static void *pth_consumer(void *a) { rte_thread_register(); consumer(a); return NULL; }

static void parse_args(int argc, char **argv) {
    static struct option o[] = {
        {"burst", required_argument, 0, 'b'},  {"size", required_argument, 0, 's'},
        {"packets", required_argument, 0, 'p'}, {"copy", no_argument, 0, 'c'},
        {"locked-queue", no_argument, 0, 'q'},  {"malloc", no_argument, 0, 'm'},
        {"no-pin", no_argument, 0, 'n'},         {"label", required_argument, 0, 'l'},
        {0, 0, 0, 0}};
    int c;
    optind = 1;
    while ((c = getopt_long(argc, argv, "b:s:p:cqmnl:", o, NULL)) != -1) {
        switch (c) {
            case 'b': cfg.burst = (unsigned)atoi(optarg); break;
            case 's': cfg.size = (unsigned)atoi(optarg); break;
            case 'p': cfg.packets = strtoull(optarg, 0, 10); break;
            case 'c': cfg.copy = 1; break;
            case 'q': cfg.locked_queue = 1; break;
            case 'm': cfg.use_malloc = 1; break;
            case 'n': cfg.no_pin = 1; break;
            case 'l': cfg.label = optarg; break;
            default: break;
        }
    }
    if (cfg.burst < 1) cfg.burst = 1;
    if (cfg.burst > 256) cfg.burst = 256;
    if (cfg.size < 2) cfg.size = 2;
    if (cfg.size > MAX_PKT) cfg.size = MAX_PKT;
}

int main(int argc, char **argv) {
    int n = rte_eal_init(argc, argv);
    if (n < 0) { fprintf(stderr, "EAL init failed\n"); return 1; }
    argc -= n;
    argv += n;
    parse_args(argc, argv);

    if (!cfg.use_malloc) {
        const unsigned room = RTE_PKTMBUF_HEADROOM + cfg.size;  // fits uint16_t (size <= 65000)
        unsigned pool_n = (256u << 20) / (room + 256);          // ~256 MB pool budget
        if (pool_n > 16384) pool_n = 16384;
        if (pool_n < 1024) pool_n = 1024;
        pool = rte_pktmbuf_pool_create("pool", pool_n, 256, 0, (uint16_t)room,
                                       (int)rte_socket_id());
        if (!pool) rte_exit(EXIT_FAILURE, "mempool create failed\n");
    }
    if (!cfg.locked_queue) {
        ring = rte_ring_create("ring", RING_SZ, (int)rte_socket_id(),
                               RING_F_SP_ENQ | RING_F_SC_DEQ);
        if (!ring) rte_exit(EXIT_FAILURE, "ring create failed\n");
    }

    const double hz = (double)rte_get_tsc_hz();
    const uint64_t start = rte_get_tsc_cycles();

    if (cfg.no_pin) {
        pthread_t tp, tc;
        pthread_create(&tc, NULL, pth_consumer, NULL);
        pthread_create(&tp, NULL, pth_producer, NULL);
        pthread_join(tp, NULL);
        pthread_join(tc, NULL);
    } else {
        unsigned lp = rte_get_next_lcore(-1, 1, 0);
        unsigned lc = rte_get_next_lcore(lp, 1, 0);
        if (lp == RTE_MAX_LCORE || lc == RTE_MAX_LCORE)
            rte_exit(EXIT_FAILURE, "need >=3 lcores, e.g. -l 0-2\n");
        rte_eal_remote_launch(consumer, NULL, lc);
        rte_eal_remote_launch(producer, NULL, lp);
        rte_eal_wait_lcore(lp);
        rte_eal_wait_lcore(lc);
    }

    const double secs = (double)(rte_get_tsc_cycles() - start) / hz;
    const double mpps = consumed / secs / 1e6;
    const double gbps = consumed * (double)cfg.size * 8.0 / secs / 1e9;
    const double ns_pkt = consumed ? secs * 1e9 / consumed : 0;
    printf("%s,%llu,%.3f,%.3f,%.1f,%u,%u\n", cfg.label, (unsigned long long)consumed, mpps, gbps,
           ns_pkt, cfg.size, cfg.burst);
    return 0;
}
