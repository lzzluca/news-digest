# Sandbox where the pipeline runs and where Claude CLI works on its code.
# Debian bookworm: Node 22 (for Claude CLI) plus the distro's Python 3.11.
FROM node:22-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 python3-venv ffmpeg ca-certificates curl git \
 && rm -rf /var/lib/apt/lists/*

# Python packages live in a virtualenv: Debian forbids pip installs into the system Python.
COPY requirements.txt /tmp/requirements.txt
RUN python3 -m venv /opt/venv \
 && /opt/venv/bin/pip install --no-cache-dir -r /tmp/requirements.txt
ENV PATH="/opt/venv/bin:$PATH"

# Updates come from rebuilding the image, not from the CLI updating itself.
RUN npm install -g @anthropic-ai/claude-code
# yt-dlp needs a JavaScript runtime to solve YouTube's player challenges.
RUN npm install -g deno
ENV DISABLE_AUTOUPDATER=1

# Home for the runtime user (uid set in compose.yaml): Claude CLI config and the Whisper model cache.
# Created here so the named volume mounted on it inherits this ownership.
ARG APP_UID=1001
RUN mkdir -p /home/app/.cache && chown -R ${APP_UID}:${APP_UID} /home/app
ENV HOME=/home/app

WORKDIR /workspace
# Kept alive so we can `docker compose exec` into it; the nightly run comes later.
CMD ["sleep", "infinity"]
