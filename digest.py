"""Weekly digest, step 1: read the last week's articles of each text category from FreshRSS.

Run inside the container: python digest.py
"""
import os
import time
from urllib.parse import quote

import requests

# FreshRSS categories to summarize, by their exact name in FreshRSS.
CATEGORIES = ["AI", "System design", "Web & frontend", "Finance", "Newsletters"]
DAYS = 7

API = os.environ["FRESHRSS_API_URL"]


def login() -> str:
    """Google Reader ClientLogin: trade the API password for a session token."""
    res = requests.post(
        f"{API}/accounts/ClientLogin",
        data={"Email": os.environ["FRESHRSS_USER"], "Passwd": os.environ["FRESHRSS_API_PASSWORD"]},
        timeout=30,
    )
    res.raise_for_status()
    # The body is lines of KEY=value; we need the Auth one.
    for line in res.text.splitlines():
        if line.startswith("Auth="):
            return line.removeprefix("Auth=")
    raise RuntimeError("FreshRSS login: no Auth token in the response")


def articles(auth: str, category: str, since: int) -> list[dict]:
    """All articles of one category published after `since` (unix seconds), read or unread."""
    # A category is the stream "user/-/label/<name>"; the name may contain spaces and "&".
    url = f"{API}/reader/api/0/stream/contents/" + quote(f"user/-/label/{category}", safe="")
    headers = {"Authorization": f"GoogleLogin auth={auth}"}
    params = {"ot": since, "n": 200, "output": "json"}
    items: list[dict] = []
    while True:
        res = requests.get(url, headers=headers, params=params, timeout=60)
        res.raise_for_status()
        data = res.json()
        items += data.get("items", [])
        # More than 200 articles: the API returns a cursor for the next page.
        if "continuation" not in data:
            return items
        params["c"] = data["continuation"]


def main() -> None:
    auth = login()
    since = int(time.time()) - DAYS * 24 * 3600
    for category in CATEGORIES:
        items = articles(auth, category, since)
        print(f"\n## {category}: {len(items)} articles")
        for item in items:
            source = item.get("origin", {}).get("title", "?")
            print(f"- [{source}] {item.get('title', '(no title)')}")


if __name__ == "__main__":
    main()
