FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        iptables \
        iproute2 \
        libasound2 \
        libdbus-1-3 \
        libfontconfig1 \
        libgl1 \
        libglib2.0-0 \
        libx11-6 \
        libxcursor1 \
        libxext6 \
        libxi6 \
        libxinerama1 \
        libxrandr2 \
        libxrender1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
