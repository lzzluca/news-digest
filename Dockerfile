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

RUN npm install -g @anthropic-ai/claude-code
# Updates come from rebuilding the image, not from the CLI updating itself.
ENV DISABLE_AUTOUPDATER=1
# yt-dlp needs a JavaScript runtime to solve YouTube's player challenges.
RUN npm install -g deno

# Home for the runtime user (uid set in compose.yaml): Claude CLI config and the Whisper model cache.
# Created here so the named volume mounted on it inherits this ownership.
ARG APP_UID=1001
ARG APP_GID=1001
RUN mkdir -p /home/app/.cache && chown -R ${APP_UID}:${APP_GID} /home/app
ENV HOME=/home/app
# The repository is mounted read-only: Python must not try to write __pycache__ into it.
ENV PYTHONDONTWRITEBYTECODE=1

WORKDIR /workspace
# Main process: serve the generated feeds (out/) to FreshRSS on the Docker network.
# The scripts (digest.py, media.py) run beside it with `docker compose exec`, from cron.
CMD ["python", "-m", "http.server", "8080", "--directory", "/workspace/out"]
