# news-digest

Turns the sources collected in a self-hosted FreshRSS (articles, newsletters, podcasts, YouTube) into summaries, using Claude CLI. Everything runs in one Docker container on the VPS, next to FreshRSS.

Work in progress: the weekly digest of text sources works, YouTube videos are being added; podcasts come next.

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
sudo chgrp news-digest secrets secrets/*.txt     # it reads the secrets through its group...
chmod 750 secrets && chmod 640 secrets/*.txt     # ...while you keep owning them
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

## YouTube cookies

YouTube blocks anonymous requests from datacenter IPs, so yt-dlp uses the cookies of a dedicated Google account (never your personal one: the file gives access to the account).

1. In a **private window**, sign in to youtube.com with the dedicated account.
2. Export the youtube.com cookies in Netscape format with a local extension such as "Get cookies.txt LOCALLY".
3. Close the private window **without signing out** (signing out invalidates the cookies).
4. Copy the file to the server: `secrets/youtube-cookies.txt` next to `compose.yaml`, then `chmod 600` it.

Check, with the URL of a video from a `*_media` category:

```sh
docker compose exec news-digest sh -c 'cp "$YTDLP_COOKIES_FILE" /tmp/cookies.txt && yt-dlp --cookies /tmp/cookies.txt --skip-download --write-auto-subs --sub-langs "en.*" -o "/tmp/%(id)s" "<video URL>" && ls /tmp/*.vtt'
```

yt-dlp rewrites the cookie file it is given, so it always works on a copy: the mounted file stays read-only. When YouTube answers "Sign in to confirm you're not a bot", the cookies have expired: export them again.

## Video summaries

`media.py` takes every unread YouTube video of the last 7 days in a `<topic>_media` category, gets a transcript, summarizes it with Claude CLI (Haiku) and writes `out/summaries-<topic>.xml`. Then it marks the video as read in FreshRSS, so read/unread is the only state. The transcript comes from YouTube's subtitles when possible; when a video has none, or YouTube refuses subtitles to the server (HTTP 429), the audio is downloaded and transcribed in the container with Whisper (`small`, CPU: several minutes per video; the first run also downloads the model). Videos that fail stay unread and are retried on the next run.

```sh
docker compose exec news-digest python media.py --limit 1   # one video, to try it
docker compose exec news-digest python media.py             # all new videos
```

In FreshRSS, subscribe to `http://news-digest:8080/summaries-<topic>.xml` (e.g. `summaries-ai.xml`) in the matching text category: the summaries then end up in the weekly digest. Each run rewrites the feed with that run's videos only; FreshRSS keeps the entries it already imported.

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
