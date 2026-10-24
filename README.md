# news-digest

Turns the sources collected in a self-hosted FreshRSS (articles, newsletters, podcasts, YouTube) into summaries, using Claude CLI. Everything runs in one Docker container on the VPS, next to FreshRSS.

Work in progress: for now this repository only contains the container.

## Setup on the server

1. In FreshRSS: enable the API (Administration > Authentication) and set an **API password** for your user (Settings > Profile).
2. On a machine with a browser: `claude setup-token`, then copy the token.
3. On the server:

```sh
git clone https://github.com/lzzluca/news-digest.git && cd news-digest
cp .env.example .env && chmod 600 .env   # fill in the values
docker compose up -d --build
```

`compose.yaml` has two values specific to my server: uid `1001` (owner of this folder: `id -u`) and the `freshrss_default` network (`docker network ls`).

## Check that it works

```sh
docker compose exec news-digest bash

# FreshRSS login through the Google Reader API: prints a line starting with Auth=
curl -s -G "$FRESHRSS_API_URL/accounts/ClientLogin" \
  --data-urlencode "Email=$FRESHRSS_USER" --data-urlencode "Passwd=$FRESHRSS_API_PASSWORD"

# Claude CLI, no tools: prints a short answer
claude -p --model haiku --tools '' "Reply with: ok"

# Python stack
python -c "import faster_whisper, av, feedgen; print(av.__version__)"
```

## License

[MIT](LICENSE)
