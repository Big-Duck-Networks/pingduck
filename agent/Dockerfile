# PingDuck homelab agent: the Rust pingduck-agent (agent/crates) around
# pingduck-core (C++, with libpcap for raw ARP sniffing). The app finds it on
# the LAN and pairs it.
#
# Build (from the repo root):
#   docker build -f agent/Dockerfile -t pingduck-agent .
# Run (host networking + raw sockets are required to see the LAN; the volume
# keeps the pairing across restarts):
#   docker run -d --name pingduck-agent --restart unless-stopped --net=host \
#     --cap-add=NET_RAW --cap-add=NET_ADMIN -v pingduck:/var/lib/pingduck \
#     ghcr.io/big-duck-networks/pingduck-agent:latest
# Then in the app: Account > Add monitoring unit. If the phone can't reach the
# box's LAN (VLAN, VPN), add -e PINGDUCK_PAIRING_CODE=<code from the app>.
#
# The core CLI stays in the image for debugging:
#   docker run --rm --net=host --cap-add=NET_RAW --entrypoint pingduck pingduck-agent scan --arp

FROM rust:1-bookworm AS build
RUN apt-get update \
    && apt-get install -y --no-install-recommends cmake libpcap-dev curl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY core/CMakeLists.txt core/
COPY core/include core/include
COPY core/src core/src
COPY core/cli core/cli
COPY agent/Cargo.toml agent/Cargo.lock agent/
COPY agent/crates agent/crates
RUN cd agent \
    && cargo test --workspace --release --locked \
    && cargo build --release --locked -p pingduck-agent
RUN cmake -S core -B build-cli -DCMAKE_BUILD_TYPE=Release -DPINGDUCK_PCAP=ON -DPINGDUCK_BUILD_SHARED=OFF \
       -DPINGDUCK_BUILD_TESTS=OFF \
    && cmake --build build-cli -j"$(nproc)" --target pingduck_cli
RUN curl -fsSL -o /oui.csv https://standards-oui.ieee.org/oui/oui.csv

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends libpcap0.8 ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/agent/target/release/pingduck-agent /usr/local/bin/pingduck-agent
COPY --from=build /src/build-cli/pingduck_cli /usr/local/bin/pingduck
COPY --from=build /oui.csv /usr/share/pingduck/oui.csv
VOLUME /var/lib/pingduck
EXPOSE 44480/tcp 1900/udp
ENTRYPOINT ["pingduck-agent"]
