FROM debian:bookworm-slim

ARG UID=1000
ARG GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    STEAMCMDDIR=/opt/steamcmd \
    HOLDFAST_INSTALL_DIR=/opt/holdfast/server \
    HOLDFAST_SERVER_DIR=/opt/holdfast/server/Holdfast\ Dedicated\ Server

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        dumb-init \
        lib32gcc-s1 \
        lib32stdc++6 \
        procps \
        unzip \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid "${GID}" steam \
    && useradd --uid "${UID}" --gid "${GID}" --create-home --shell /usr/sbin/nologin steam \
    && mkdir -p /opt/steamcmd /opt/holdfast/server /data/config /data/logs /data/runtime \
    && chown -R steam:steam /opt/steamcmd /opt/holdfast /data

RUN curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz -o /tmp/steamcmd.tar.gz \
    && tar -xzf /tmp/steamcmd.tar.gz -C /opt/steamcmd \
    && mkdir -p /home/steam/.steam/sdk32 /home/steam/.steam/sdk64 \
    && ln -sf /opt/steamcmd/linux32/steamclient.so /home/steam/.steam/sdk32/steamclient.so \
    && ln -sf /opt/steamcmd/linux64/steamclient.so /home/steam/.steam/sdk64/steamclient.so \
    && rm -f /tmp/steamcmd.tar.gz \
    && chown -R steam:steam /opt/steamcmd /home/steam/.steam

COPY docker/holdfast-entrypoint.sh /usr/local/bin/holdfast-entrypoint.sh
COPY docker/healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod 0755 /usr/local/bin/holdfast-entrypoint.sh /usr/local/bin/healthcheck.sh

USER steam
WORKDIR /home/steam

ENTRYPOINT ["/usr/bin/dumb-init", "--", "/usr/local/bin/holdfast-entrypoint.sh"]
