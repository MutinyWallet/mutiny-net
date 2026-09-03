# Self-contained Spark Operator image for MutinyNet.
# Clones pinned upstream (buildonspark/spark) and builds SO + frost signer.
# Override the pin with --build-arg SPARK_REF=<sha>.
ARG SPARK_REF=0b3a32a05c9ac06cc411683551dd1f1bde9d0caa

FROM alpine/git AS src
ARG SPARK_REF
RUN git clone https://github.com/buildonspark/spark /spark \
 && cd /spark && git checkout ${SPARK_REF} && git rev-parse HEAD

FROM golang:1.27-bookworm AS builder-go
RUN apt-get update && apt-get install -y libzmq3-dev && rm -rf /var/lib/apt/lists
COPY --from=src /spark/spark/go.mod /spark/spark/go.sum spark/
RUN cd spark && go mod download
COPY --from=src /spark/spark spark
RUN cd spark && CGO_ENABLED=1 go build -o /go/bin/spark-operator ./bin/operator
RUN GRPC_HEALTH_PROBE_VERSION=v0.4.13 && \
    wget -qO/bin/grpc_health_probe https://github.com/grpc-ecosystem/grpc-health-probe/releases/download/${GRPC_HEALTH_PROBE_VERSION}/grpc_health_probe-linux-amd64 && \
    chmod +x /bin/grpc_health_probe

FROM rust:1.92-slim-bookworm AS builder-rust
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
