// Kernel baseline: UDP-over-loopback packet rate — the OS-default data path,
// one syscall + copy per packet. A receiver thread drains so the sender never
// blocks; we time the sender pushing `packets` datagrams. Same CSV columns as
// dpdk_pipeline (cycles/packet left 0 — this is the kernel reference).
#include <arpa/inet.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

static volatile int stop;
static unsigned g_size = 64;
static uint64_t g_packets = 20000000ull;
static const uint16_t PORT = 18600;

static double now_s(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec * 1e-9;
}

static void *receiver(void *arg) {
    int fd = (int)(intptr_t)arg;
    char buf[2048];
    while (!stop) recv(fd, buf, sizeof buf, 0);  // drain (blocking recv is fine)
    return NULL;
}

int main(int argc, char **argv) {
    const char *label = "kernel-udp";
    for (int i = 1; i + 1 < argc; i++) {
        if (!strcmp(argv[i], "--size")) g_size = (unsigned)atoi(argv[i + 1]);
        else if (!strcmp(argv[i], "--packets")) g_packets = strtoull(argv[i + 1], 0, 10);
        else if (!strcmp(argv[i], "--label")) label = argv[i + 1];
    }
    if (g_size > 2048) g_size = 2048;

    int rfd = socket(AF_INET, SOCK_DGRAM, 0);
    int big = 16 << 20;
    setsockopt(rfd, SOL_SOCKET, SO_RCVBUF, &big, sizeof big);
    struct sockaddr_in addr = {.sin_family = AF_INET, .sin_port = htons(PORT)};
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(rfd, (struct sockaddr *)&addr, sizeof addr) < 0) { perror("bind"); return 1; }

    pthread_t rt;
    pthread_create(&rt, NULL, receiver, (void *)(intptr_t)rfd);

    int sfd = socket(AF_INET, SOCK_DGRAM, 0);
    char buf[2048];
    memset(buf, 1, sizeof buf);

    const double t0 = now_s();
    for (uint64_t i = 0; i < g_packets; i++)
        while (sendto(sfd, buf, g_size, 0, (struct sockaddr *)&addr, sizeof addr) < 0)
            ;  // retry on transient buffer-full
    const double secs = now_s() - t0;

    stop = 1;
    sendto(sfd, buf, 1, 0, (struct sockaddr *)&addr, sizeof addr);  // unblock receiver
    pthread_join(rt, NULL);
    close(sfd);
    close(rfd);

    const double mpps = g_packets / secs / 1e6;
    const double gbps = g_packets * (double)g_size * 8.0 / secs / 1e9;
    printf("%s,%llu,%.3f,%.3f,%.1f,%u\n", label, (unsigned long long)g_packets, mpps, gbps, 0.0,
           g_size);
    return 0;
}
