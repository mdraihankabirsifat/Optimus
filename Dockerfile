# Escave -- headless authoritative game server.
#
# Build:  docker build -t escave-server .
# Run:    docker run --rm -p 8910:8910 escave-server
# Client: connect to ws://127.0.0.1:8910 from Play > Online Race.
#
# On Render this runs as a Web Service. Render injects PORT and terminates TLS, so players
# connect to wss://<your-service>.onrender.com. See docs/NETWORKING.md.

FROM debian:bookworm-slim

ARG GODOT_VERSION=4.7.2
ARG GODOT_RELEASE=stable

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates wget unzip libfontconfig1 \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-${GODOT_RELEASE}/Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_linux.x86_64.zip" -O /tmp/godot.zip \
    && unzip -q /tmp/godot.zip -d /tmp/godot \
    && mv "/tmp/godot/Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_linux.x86_64" /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm -rf /tmp/godot /tmp/godot.zip

# Run as an unprivileged user. It must own /app itself, not just the files in it, or the
# import step below cannot create /app/.godot and every class_name fails to resolve.
RUN useradd --create-home --shell /usr/sbin/nologin godot \
    && mkdir -p /app \
    && chown godot:godot /app
WORKDIR /app
COPY --chown=godot:godot . /app
USER godot

# Import once at build time so the script class cache exists. Without it a headless run
# cannot resolve class_name scripts and idles silently (see CLAUDE.md).
RUN godot --headless --path /app --editor --quit

ENV PORT=8910
EXPOSE 8910

CMD ["sh", "-c", "exec godot --headless --path /app -- --server --port=${PORT}"]
