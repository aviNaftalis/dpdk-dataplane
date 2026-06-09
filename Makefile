# dpdk_pipeline needs DPDK (pkg-config libdpdk); udp_bench is plain POSIX.
BUILD := build
DPDK_CFLAGS := $(shell pkg-config --cflags libdpdk 2>/dev/null)
DPDK_LIBS   := $(shell pkg-config --libs libdpdk 2>/dev/null)

.PHONY: all clean
all: $(BUILD)/dpdk_pipeline $(BUILD)/udp_bench

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/dpdk_pipeline: src/dpdk_pipeline.c | $(BUILD)
	@test -n "$(DPDK_LIBS)" || { echo "DPDK not found — run ./scripts/setup.sh"; exit 1; }
	cc -O3 -march=native $(DPDK_CFLAGS) $< -o $@ $(DPDK_LIBS) -lpthread

$(BUILD)/udp_bench: src/udp_bench.c | $(BUILD)
	cc -O3 -march=native $< -o $@ -lpthread

clean:
	rm -rf $(BUILD)
