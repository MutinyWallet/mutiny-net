FROM debian:bullseye-slim as builder

ARG BITCOIN_VERSION="38351585048e"
ARG TARGETARCH
ARG TRIPLET

RUN  apt-get update && \
     apt-get install -qq --no-install-recommends ca-certificates dirmngr gosu wget libc6 procps python3
WORKDIR /tmp

# install bitcoin binaries
# Set TRIPLET based on TARGETARCH if not provided
RUN if [ -z "$TRIPLET" ]; then \
     if [ "$TARGETARCH" = "arm64" ]; then \
     TRIPLET=aarch64-linux-gnu; \
     elif [ "$TARGETARCH" = "amd64" ]; then \
     TRIPLET=x86_64-linux-gnu; \
     else \
     TRIPLET=x86_64-linux-gnu; \
     fi; \
     fi; \
     echo "Using TRIPLET=$TRIPLET" && \
     BITCOIN_URL="https://github.com/benthecarman/bitcoin/releases/download/mutinynet-inq-29/bitcoin-${BITCOIN_VERSION}-${TRIPLET}.tar.gz" && \
     BITCOIN_FILE="bitcoin-${BITCOIN_VERSION}-${TRIPLET}.tar.gz" && \
     wget -qO "${BITCOIN_FILE}" "${BITCOIN_URL}" && \
     mkdir -p bin && \
     tar -xzvf "${BITCOIN_FILE}" -C /tmp/bin --strip-components=2 "bitcoin-${BITCOIN_VERSION}/bin/bitcoin-cli" "bitcoin-${BITCOIN_VERSION}/bin/bitcoind" "bitcoin-${BITCOIN_VERSION}/bin/bitcoin-wallet" "bitcoin-${BITCOIN_VERSION}/bin/bitcoin-util"

FROM debian:bullseye-slim as custom-signet-bitcoin

LABEL org.opencontainers.image.authors="NBD"
LABEL org.opencontainers.image.licenses=MIT
LABEL org.opencontainers.image.source="https://github.com/nbd-wtf/bitcoin_signet"

ENV BITCOIN_DIR /root/.bitcoin 

ENV NBITS=${NBITS}
ENV SIGNETCHALLENGE=${SIGNETCHALLENGE}
ENV PRIVKEY=${PRIVKEY}
ENV PRIVKEY_MODE=${PRIVKEY_MODE:-"descriptor"}
ENV CHAIN_TIP_AGE=${CHAIN_TIP_AGE:-"7200"}
ENV MINE_GENESIS=${MINE_GENESIS:-"0"}
ENV RPCUSER=${RPCUSER:-"bitcoin"}
ENV RPCPASSWORD=${RPCPASSWORD:-"bitcoin"}
ENV COOKIEFILE=${COOKIEFILE:-"false"}
ENV ONIONPROXY=${ONIONPROXY:-""}
ENV TORPASSWORD=${TORPASSWORD:-""}
ENV TORCONTROL=${TORCONTROL:-""}
ENV I2PSAM=${I2PSAM:-""}

ENV UACOMMENT=${UACOMMENT:-"CustomSignet"}
ENV ZMQPUBRAWBLOCK=${ZMQPUBRAWBLOCK:-"tcp://0.0.0.0:28332"}
ENV ZMQPUBRAWTX=${ZMQPUBRAWTX:-"tcp://0.0.0.0:28333"}
ENV ZMQPUBHASHBLOCK=${ZMQPUBHASHBLOCK:-"tcp://0.0.0.0:28334"}

ENV RPCBIND=${RPCBIND:-"0.0.0.0:38332"}
ENV RPCALLOWIP=${RPCALLOWIP:-"0.0.0.0/0"}
ENV WHITELIST=${WHITELIST:-"0.0.0.0/0"}
ENV ADDNODE=${ADDNODE:-""}
ENV BLOCKPRODUCTIONDELAY=${BLOCKPRODUCTIONDELAY:-""}
ENV MINERENABLED=${MINERENABLED:-"1"}
ENV MINETO=${MINETO:-""}
ENV EXTERNAL_IP=${EXTERNAL_IP:-""} 

VOLUME $BITCOIN_DIR
EXPOSE 28332 28333 28334 38332 38333 38334
RUN  apt-get update && \
     apt-get install -qq --no-install-recommends procps python3 python3-pip jq && \
     apt-get clean
COPY --from=builder "/tmp/bin" /usr/local/bin 
COPY docker-entrypoint.sh /usr/local/bin/entrypoint.sh
COPY miner_imports /usr/local/bin
COPY miner /usr/local/bin/miner
COPY *.sh /usr/local/bin/
COPY rpcauth.py /usr/local/bin/rpcauth.py
RUN pip3 install setuptools

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

CMD ["run.sh"]
