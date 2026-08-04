FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    bind9 \
    dnsutils \
&& rm -rf /var/lib/apt/lists/*

HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=10s \
  CMD dig @localhost . SOA +norecurse || exit 1

### End of File
