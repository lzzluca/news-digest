# news-digest

Turns the sources collected in a self-hosted FreshRSS (articles, newsletters, podcasts, YouTube) into summaries, using Claude CLI. Everything runs in one Docker container on the VPS, next to FreshRSS.

Work in progress: the weekly digest of text sources and the YouTube and podcast summaries are built; podcasts are the newest part.

## Setup on the server

1. In FreshRSS: enable the API (Administration > Authentication) and set an **API password** for your user (Settings > Profile).
2. On a machine with a browser: `claude setup-token`, then copy the token.
3. On the server:

```sh
git clone https://github.com/lzzluca/news-digest.git && cd news-digest
cp .env.example .env && chmod 600 .env   # fill in the values
docker compose up -d --build
```

`compose.yaml` has one value specific to my server: the `freshrss_default` network (`docker network ls`).

### Dedicated user

The container runs as a host user that exists only for it: no login, no sudo, not in the `docker` group. If something escaped the container, that is all it would get. Its uid and gid go in `.env` (`APP_UID`, `APP_GID`; without them the container runs as uid 1001).

```sh
sudo useradd --system --user-group --no-create-home --shell /usr/sbin/nologin news-digest
id news-digest                                   # put uid and gid in .env as APP_UID / APP_GID
sudo chown -R news-digest:news-digest out        # the only place it writes
docker compose down
docker volume rm news-digest_home                # recreated owned by the new user (the Whisper model downloads again)
docker compose up -d --build
docker compose exec news-digest id               # expect uid=<APP_UID>
```

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

## YouTube: Gemini

YouTube refuses subtitles and audio to this server (HTTP 429, datacenter IP), so YouTube videos are summarized by Gemini (`gemini-3.1-flash-lite`), which reads the video from Google's servers. Put `GEMINI_API_KEY` in `.env`, then `docker compose up -d --force-recreate`. Use a key from an AI Studio project without billing: on the free tier the limit is 8 hours of YouTube per day and nothing can be charged; a project with billing is not on the free tier and gets refused when its credits run out. Only public videos work.

## Video and podcast summaries

`media.py` takes every unread YouTube video of the last 7 days in a `<topic>_media` category, has Gemini summarize it (see above) and writes `out/summaries-<topic>.xml`. Then it marks the video as read in FreshRSS, so read/unread is the only state. Videos that fail (quota, private video, a premiere not out yet) stay unread and are retried on the next run.

Podcasts work the same way: subscribe to the show's public RSS feed in a `<topic>_media` category, and every unread episode with an audio file (the feed's enclosure) is downloaded directly, transcribed in the container with Whisper (`small`, CPU; the first run also downloads the model), summarized with Claude CLI (Haiku) and added to the same `summaries-<topic>.xml`. The audio URL comes from a third-party feed, so only https is followed (redirects included), which keeps it away from the plain-http services on the Docker network; files over 500 MB are skipped. Long episodes take a long time to transcribe on this CPU: check the first ones in the log.

```sh
docker compose exec news-digest python media.py --limit 1   # one video, to try it
docker compose exec news-digest python media.py             # all new videos
```

Run it every night from the host's crontab. `flock -n` skips a night if the previous run (hours, with a backlog) is still going:

```cron
0 1 * * * cd $HOME/docker-compose-files/news-digest && flock -n /tmp/news-digest-media.lock docker compose exec -T news-digest python media.py >> $HOME/news-digest-media.log 2>&1
```

In FreshRSS, subscribe to `http://news-digest:8080/summaries-<topic>.xml` (e.g. `summaries-ai.xml`) in the matching text category: the summaries then end up in the weekly digest. Each run rewrites the feed with that run's videos only; FreshRSS keeps the entries it already imported.

## Weekly digest

`digest.py` summarizes the last 7 days of every FreshRSS category except the `*_media` ones, with Claude CLI, into `out/digest.xml`. The container serves it on the Docker network only: in FreshRSS, subscribe to `http://news-digest:8080/digest.xml` (one entry per category per week).

Topic priorities for the Highlights live in the `PRIORITIES` map in `digest.py`, keyed by category name. A category without a key gets the generic prompt. The key must match the FreshRSS category name exactly, case included: after renaming a category in FreshRSS, rename its key too, or its priorities are silently dropped.

```sh
docker compose exec news-digest python digest.py          # all categories
docker compose exec news-digest python digest.py "AI"     # one category, cheaper while testing
```

Run it every Sunday from the host's crontab (`crontab -e` as the user that runs Docker). Cron uses the server's time zone (`timedatectl`); on this server it is Europe/Berlin, so this line runs at 05:00 Italian time all year:

```cron
0 5 * * 0 cd $HOME/docker-compose-files/news-digest && docker compose exec -T news-digest python digest.py >> $HOME/news-digest.log 2>&1
```

## License

[MIT](LICENSE)
