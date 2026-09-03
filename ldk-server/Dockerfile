# Self-contained ldk-server image for MutinyNet (bitcoind backend).
# Clones pinned upstream. Override with --build-arg LDK_SERVER_REF=<sha>.
ARG LDK_SERVER_REF=6d6d810714706c225ce7effc2163eff6a1b54221

# Capped for the same reason as spark/Dockerfile: bitcoind shares this host.
ARG BUILD_JOBS=2

FROM rust:1.85 AS builder
ARG LDK_SERVER_REF
ARG BUILD_JOBS
ENV CARGO_BUILD_JOBS=${BUILD_JOBS}
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*
RUN git clone https://github.com/lightningdevkit/ldk-server /app \
 && cd /app && git checkout ${LDK_SERVER_REF}
WORKDIR /app
RUN cargo build --release --locked -p ldk-server -p ldk-server-cli

FROM debian:bookworm-slim AS final
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates gettext-base \
 && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/ldk-server /usr/local/bin/ldk-server
COPY --from=builder /app/target/release/ldk-server-cli /usr/local/bin/ldk-server-cli
COPY ldk-server-entrypoint.sh /usr/local/bin/ldk-server-entrypoint.sh
RUN chmod +x /usr/local/bin/ldk-server-entrypoint.sh
EXPOSE 9735 3536
ENTRYPOINT ["/usr/local/bin/ldk-server-entrypoint.sh"]
