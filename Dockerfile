# WPG Dedicated Server (Godot Headless)
#
# Traffic boundary:
# - This image exposes ENet/UDP gameplay only (default 24567/udp).
# - WildBoat HTTPS/business APIs are NOT served here.
# - Do not treat Cloudflare Workers / HTTP gateways as ENet/UDP proxies.
#
# Targets:
#   docker build -t wpg-dedicated-server .
#       Multi-stage: export Linux Dedicated Server inside the image (reproducible).
#   docker build --target runtime-local -t wpg-dedicated-server:local .
#       Uses pre-exported build/dedicated_server/wpg_server.x86_64
#       (run ./tools/server/export_dedicated.sh first).
#
# Run (dev):
#   docker run --rm -p 24567:24567/udp \
#     -e WPG_GAME_PORT=24567 -e WPG_MAX_PLAYERS=4 -e WPG_ADMISSION_MODE=dev -e WPG_DEV_TOKEN=dev \
#     wpg-dedicated-server
#
# Run (wildboat — inject S2S credential via env ONLY; never bake into image):
#   docker run --rm -p 24567:24567/udp \
#     -e WPG_ADMISSION_MODE=wildboat \
#     -e WPG_WILDBOAT_BASE_URL=http://host.docker.internal:8080 \
#     -e DEDICATED_SERVER_CREDENTIAL="$DEDICATED_SERVER_CREDENTIAL" \
#     -e WPG_ADVERTISE_HOST=127.0.0.1 \
#     wpg-dedicated-server:phase2b

# syntax=docker/dockerfile:1

ARG GODOT_VERSION=4.6.2

FROM barichello/godot-ci:${GODOT_VERSION} AS export
WORKDIR /src
COPY . .
RUN mkdir -p /out \
	&& godot --headless --path /src --export-release "Linux Dedicated Server" /out/wpg_server.x86_64 \
	&& test -f /out/wpg_server.x86_64 \
	&& chmod +x /out/wpg_server.x86_64

FROM debian:bookworm-slim AS runtime-base
RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates \
	&& rm -rf /var/lib/apt/lists/* \
	&& groupadd --system --gid 10001 wpg \
	&& useradd --system --uid 10001 --gid wpg --home-dir /opt/wpg --shell /usr/sbin/nologin wpg \
	&& mkdir -p /opt/wpg /var/lib/wpg \
	&& chown -R wpg:wpg /opt/wpg /var/lib/wpg

FROM runtime-base AS runtime-local
COPY build/dedicated_server/wpg_server.x86_64 /opt/wpg/wpg_server.x86_64
RUN chmod +x /opt/wpg/wpg_server.x86_64 \
	&& chown wpg:wpg /opt/wpg/wpg_server.x86_64
USER wpg
WORKDIR /opt/wpg
ENV WPG_DEDICATED_SERVER=1 \
	WPG_GAME_PORT=24567 \
	WPG_MAX_PLAYERS=4 \
	WPG_TICK_HZ=20 \
	WPG_READY_FILE=/var/lib/wpg/ready \
	WPG_MATCH_ID=dev_match \
	HOME=/opt/wpg
EXPOSE 24567/udp
HEALTHCHECK --interval=10s --timeout=3s --start-period=15s --retries=3 \
	CMD test -f /var/lib/wpg/ready || exit 1
ENTRYPOINT ["/opt/wpg/wpg_server.x86_64"]
CMD ["--headless", "--", "--dedicated-server"]

FROM runtime-base AS runtime
COPY --from=export /out/wpg_server.x86_64 /opt/wpg/wpg_server.x86_64
RUN chmod +x /opt/wpg/wpg_server.x86_64 \
	&& chown wpg:wpg /opt/wpg/wpg_server.x86_64
USER wpg
WORKDIR /opt/wpg
ENV WPG_DEDICATED_SERVER=1 \
	WPG_GAME_PORT=24567 \
	WPG_MAX_PLAYERS=4 \
	WPG_TICK_HZ=20 \
	WPG_READY_FILE=/var/lib/wpg/ready \
	WPG_MATCH_ID=dev_match \
	HOME=/opt/wpg
EXPOSE 24567/udp
HEALTHCHECK --interval=10s --timeout=3s --start-period=15s --retries=3 \
	CMD test -f /var/lib/wpg/ready || exit 1
ENTRYPOINT ["/opt/wpg/wpg_server.x86_64"]
CMD ["--headless", "--", "--dedicated-server"]
