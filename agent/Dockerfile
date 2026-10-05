# PingDuck headless agent: pingduck-core built with libpcap for raw ARP sniffing.
#
# Build (from the repo root):
#   docker build -f agent/Dockerfile -t pingduck-agent .
# Run (host networking + raw sockets are required to see the LAN):
#   docker run --rm --net=host --cap-add=NET_RAW --cap-add=NET_ADMIN pingduck-agent
#
# Phase 1: the entrypoint is the CLI doing a one-shot scan. Phase 4 replaces it
# with the long-running daemon that syncs to Supabase.

FROM debian:bookworm-slim AS build
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential cmake libpcap-dev ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY core/CMakeLists.txt core/
COPY core/include core/include
COPY core/src core/src
COPY core/cli core/cli
RUN cmake -S core -B build -DCMAKE_BUILD_TYPE=Release -DPINGDUCK_PCAP=ON -DPINGDUCK_BUILD_SHARED=OFF \
 && cmake --build build -j"$(nproc)"
RUN curl -fsSL -o /oui.csv https://standards-oui.ieee.org/oui/oui.csv

FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends libpcap0.8 \
 && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/build/pingduck_cli /usr/local/bin/pingduck
COPY --from=build /oui.csv /usr/share/pingduck/oui.csv
ENTRYPOINT ["pingduck"]
CMD ["scan", "--arp", "--oui", "/usr/share/pingduck/oui.csv"]
