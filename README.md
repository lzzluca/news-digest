# news-digest

Turns the sources collected in a self-hosted FreshRSS (articles, newsletters, podcasts, YouTube) into summaries, using Claude CLI. Everything runs in one Docker container on the VPS, next to FreshRSS.

Work in progress: the weekly digest of text sources works; podcasts and YouTube come next.

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

# Claude CLI, no tools: prints ok (the prompt goes first: --tools takes several values)
claude -p "Reply with: ok" --model haiku --tools ''

# Python stack
python -c "import faster_whisper, av, feedgen; print(av.__version__)"
```

## Weekly digest

`digest.py` summarizes the last 7 days of every FreshRSS category except the `*_media` ones, with Claude CLI, into `out/digest.xml`. The container serves it on the Docker network only: in FreshRSS, subscribe to `http://news-digest:8080/digest.xml` (one entry per category per week).

```sh
docker compose exec news-digest python digest.py          # all categories
docker compose exec news-digest python digest.py "AI"     # one category, cheaper while testing
```

Run it every Sunday from the host's crontab (`crontab -e` as the user that runs Docker). Cron uses the server's time zone (`timedatectl`); this line is 04:00 UTC, i.e. 05:00 in Italy in winter and 06:00 in summer:

```cron
0 4 * * 0 cd $HOME/docker-compose-files/news-digest && docker compose exec -T news-digest python digest.py >> $HOME/news-digest.log 2>&1
```

## License

[MIT](LICENSE)
