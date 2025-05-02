# syntax=docker/dockerfile:1

############################
# build-time arguments
############################
ARG ENVOY_VERSION=1.28.1
ARG CONSUL_VERSION=1.20.6

############################
# Stage 1 ─ Envoy (glibc)
############################
FROM envoyproxy/envoy:v${ENVOY_VERSION} AS envoy-builder
# envoy binary lives at /usr/local/bin/envoy in this image

############################
# Stage 2 ─ Consul (glibc)
############################
FROM hashicorp/consul:${CONSUL_VERSION} AS consul-builder
# consul binary lives at /bin/consul

############################
# Stage 3 ─ slim Debian runtime (glibc)
############################
FROM debian:stable-slim

# re-declare for labels
ARG ENVOY_VERSION
ARG CONSUL_VERSION

LABEL maintainer="Knut Olav Bøhmer <knobo@example.com>" \
      org.opencontainers.image.source="https://example.com/your-repo" \
      org.opencontainers.image.version="${CONSUL_VERSION}-envoy-${ENVOY_VERSION}" \
      org.opencontainers.image.description="Consul client + Envoy sidecar (all-glibc, Debian slim)"


########### packages ###########
RUN apt-get update -y \
 && apt-get install -y --no-install-recommends \
      dumb-init curl jq ca-certificates tzdata procps iproute2 net-tools \
 && rm -rf /var/lib/apt/lists/*

########### copy binaries ###########
COPY --from=envoy-builder  /usr/local/bin/envoy  /usr/local/bin/envoy
COPY --from=consul-builder /bin/consul           /usr/local/bin/consul



########### non-root user ###########
RUN useradd -r -u 1001 envoy \
 && mkdir -p /etc/consul/config /etc/consul/central-config \
 && chown -R envoy:envoy /etc/consul /usr/local/bin/envoy /usr/local/bin/consul

USER envoy

########### environment ###########
ENV LANG=C.UTF-8 \
    CONSUL_HTTP_ADDR="http://consul-server-test2:8500" \
    CONNECT_BOOTSTRAP_ADDR="http://0.0.0.0:8500" \
    ENTRYPOINT_LOG_LEVEL="INFO" \
    WAIT_FOR_CONSUL="true" \
    CONSUL_WAIT_TIMEOUT="60s" \
    CONSUL_WAIT_INTERVAL="2s" \
    CONSUL_CONFIG_DIR="/etc/consul/config" \
    CONSUL_CENTRAL_CONFIG_DIR="/etc/consul/central-config" \
    SERVICE_CONFIG_FILE="" \
    CENTRAL_CONFIG_FILES=""

########### entrypoint ###########
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/bin/dumb-init", "--", "/usr/local/bin/entrypoint.sh"]

