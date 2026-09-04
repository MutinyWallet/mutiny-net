# Self-contained Spark Operator image for MutinyNet.
# Clones the pinned Spark fork and builds the SO and frost signer. The fork
# exposes the authenticated counter-swap RPC required by a self-hosted SSP.
# Override the source and pin with build arguments.
ARG SPARK_REPO=https://github.com/benthecarman/spark
ARG SPARK_REF=06614d2e3535385f15aef3749b2c8a780f679ebc
# Build parallelism is capped: this host runs bitcoind alongside the build and
# a full-width build OOMs it. Raise BUILD_JOBS on a machine with more headroom.
ARG BUILD_JOBS=2

FROM alpine/git AS src
ARG SPARK_REPO
ARG SPARK_REF
RUN git clone ${SPARK_REPO} /spark \
 && cd /spark && git checkout ${SPARK_REF} && git rev-parse HEAD
# Upstream bug: MarkKeyshareForDepositAddress carries no network field, so a
# non-coordinator infers the network from the address prefix, testing Testnet
# before Signet. Signet and testnet share the "tb1" HRP, so on signet the peer
# stores deposit addresses as TESTNET while the coordinator stores SIGNET, and
# finalize_deposit_tree_creation's NetworkEQ(SIGNET) lookup then finds nothing
# on the peer -- no deposit can ever be claimed. Test Signet first. The greps
# make the build fail loudly if upstream changes this line.
RUN cd /spark && f=spark/so/handler/internal_deposit_handler.go \
 && grep -q 'btcnetwork.Testnet, btcnetwork.Signet' "$f" \
 && sed -i 's/btcnetwork\.Testnet, btcnetwork\.Signet/btcnetwork.Signet, btcnetwork.Testnet/' "$f" \
 && grep -q 'btcnetwork.Signet, btcnetwork.Testnet' "$f"

FROM golang:1.27-bookworm AS builder-go
ARG BUILD_JOBS
RUN apt-get update && apt-get install -y libzmq3-dev && rm -rf /var/lib/apt/lists
COPY --from=src /spark/spark/go.mod /spark/spark/go.sum spark/
RUN cd spark && go mod download
COPY --from=src /spark/spark spark
RUN cd spark && CGO_ENABLED=1 GOMAXPROCS=${BUILD_JOBS} go build -p ${BUILD_JOBS} -o /go/bin/spark-operator ./bin/operator
RUN GRPC_HEALTH_PROBE_VERSION=v0.4.13 && \
    wget -qO/bin/grpc_health_probe https://github.com/grpc-ecosystem/grpc-health-probe/releases/download/${GRPC_HEALTH_PROBE_VERSION}/grpc_health_probe-linux-amd64 && \
    chmod +x /bin/grpc_health_probe

FROM rust:1.92-slim-bookworm AS builder-rust
ARG BUILD_JOBS
ENV CARGO_BUILD_JOBS=${BUILD_JOBS}
RUN apt-get update && apt-get install -y protobuf-compiler && rm -rf /var/lib/apt/lists/*
WORKDIR /signer
COPY --from=src /spark/signer ./
COPY --from=src /spark/protos /protos
RUN cargo build --release

FROM arigaio/atlas:1.0.0-community AS atlas

FROM debian:bookworm-slim AS final
RUN addgroup --system --gid 1000 spark \
 && adduser --system --uid 1000 --home /home/spark --ingroup spark spark \
 && apt-get update && apt-get install -y --no-install-recommends \
      libzmq5 ca-certificates openssl python3 python3-ecdsa postgresql-client gettext-base \
 && rm -rf /var/lib/apt/lists
COPY --from=atlas /atlas /usr/local/bin/atlas
RUN chmod 0755 /usr/local/bin/atlas
COPY --from=builder-go /go/bin/spark-operator /usr/local/bin/spark-operator
COPY --from=builder-go /bin/grpc_health_probe /usr/local/bin/grpc_health_probe
COPY --from=builder-rust /signer/target/release/spark-frost-signer /usr/local/bin/spark-frost-signer
# Migrations baked in (entrypoint applies them per operator DB).
COPY --from=src /spark/spark/so/ent/migrate/migrations /opt/spark/migrations
COPY --from=src /spark/spark/so/entephemeral/migrate/migrations /opt/spark/ephemeral_migrations
EXPOSE 10009
ENTRYPOINT ["spark-operator"]
