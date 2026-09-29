"""seerr: search Seerr and request movies and series as Hermes's own Seerr
user, whose only permission is to request."""

import http.cookiejar
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

API = "@url@/api/v1"
EMAIL = "@email@"
PASSWORD_FILE = "@passwordFile@"

MEDIA_STATUS = {
    1: "unknown",
    2: "pending",
    3: "processing",
    4: "partially available",
    5: "available",
    6: "deleted",
}
REQUEST_STATUS = {
    1: "pending approval",
    2: "approved",
    3: "declined",
    4: "failed",
    5: "completed",
}
USAGE = """usage:
  seerr search QUERY...
  seerr request movie|tv TMDB_ID
  seerr status movie|tv TMDB_ID"""

opener = urllib.request.build_opener(
    urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar())
)


def call(method, path, body=None):
    request = urllib.request.Request(
        API + path,
        data=None if body is None else json.dumps(body).encode(),
        method=method,
        headers={"Content-Type": "application/json"},
    )
    try:
        with opener.open(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")[:300]
        sys.exit(f"seerr: {method} {path}: HTTP {exc.code} {detail}")
    except urllib.error.URLError as exc:
        sys.exit(f"seerr: Seerr is unreachable ({exc.reason})")


def media_status(media):
    status = (media.get("mediaInfo") or {}).get("status")
    return MEDIA_STATUS.get(status, "not requested")


def search(query):
    path = "/search?page=1&query=" + urllib.parse.quote(query, safe="")
    for result in call("GET", path)["results"]:
        if result.get("mediaType") not in ("movie", "tv"):
            continue
        title = result.get("title") or result.get("name")
        date = result.get("releaseDate") or result.get("firstAirDate") or ""
        year = date[:4] or "?"
        print(
            f"{result['mediaType']} {result['id']}\t{title} ({year})"
            f"\t{media_status(result)}"
        )


def request(kind, tmdb_id):
    body = {"mediaType": kind, "mediaId": tmdb_id}
    if kind == "tv":
        body["seasons"] = "all"
    created = call("POST", "/request", body)
    outcome = REQUEST_STATUS.get(created.get("status"), "unknown")
    print(f"{kind} {tmdb_id}: {outcome}")


def status(kind, tmdb_id):
    media = call("GET", f"/{kind}/{tmdb_id}")
    title = media.get("title") or media.get("name")
    print(f"{kind} {tmdb_id}\t{title}\t{media_status(media)}")


def login():
    with open(PASSWORD_FILE) as password_file:
        password = password_file.read().strip()
    call("POST", "/auth/local", {"email": EMAIL, "password": password})


def main():
    args = sys.argv[1:]
    if len(args) >= 2 and args[0] == "search":
        login()
        search(" ".join(args[1:]))
    elif (
        len(args) == 3
        and args[0] in ("request", "status")
        and args[1] in ("movie", "tv")
        and args[2].isdigit()
    ):
        login()
        action = request if args[0] == "request" else status
        action(args[1], int(args[2]))
    else:
        sys.exit(USAGE)


if __name__ == "__main__":
    main()
