import json
import os
import pathlib
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request


root = pathlib.Path(sys.argv[1]).resolve()
pending = pathlib.Path(os.environ["HERMES_PUBLISHER_PENDING"]).resolve()
completed = root / "completed"
rejected = root / "rejected"
for directory in (pending, completed, rejected):
    directory.mkdir(parents=True, exist_ok=True)

allowed_user = str(os.environ["HERMES_PUBLISHER_TELEGRAM_ALLOWED_USER"])
token = os.environ["HERMES_PUBLISHER_TELEGRAM_BOT_TOKEN"]
repositories = {
    "jeiang/.dotfiles": "/mnt/hermes/worktrees/cornn-flaek",
    "jeiang/infrastructure-knowledge": "/mnt/hermes/worktrees/infrastructure-knowledge",
}
request_id = re.compile(r"[A-Za-z0-9_-]{1,80}")
branch_name = re.compile(r"codex/[A-Za-z0-9][A-Za-z0-9._/-]{0,120}")


def telegram(method, **data):
    payload = urllib.parse.urlencode(data).encode()
    with urllib.request.urlopen(
        f"https://api.telegram.org/bot{token}/{method}", payload, timeout=30
    ) as response:
        return json.load(response)


def reply(chat_id, text):
    telegram("sendMessage", chat_id=chat_id, text=text)


def load_request(identifier):
    if not request_id.fullmatch(identifier):
        raise ValueError("invalid request ID")
    path = pending / f"{identifier}.json"
    if not path.is_file():
        raise FileNotFoundError("unknown or already completed request")
    request = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(request, dict):
        raise ValueError("request is not an object")
    return path, request


def validate(request):
    repository = request.get("repository")
    worktree = request.get("worktree")
    branch = request.get("branch")
    title = request.get("title")
    body = request.get("body", "")
    if not all(isinstance(value, str) for value in (repository, worktree, branch, title, body)):
        raise ValueError("request fields have invalid types")
    if repository not in repositories or not branch_name.fullmatch(branch):
        raise ValueError("request is outside the publication policy")
    expected = pathlib.Path(repositories[repository]).resolve()
    if pathlib.Path(worktree).resolve() != expected or not (expected / ".git").exists():
        raise ValueError("request worktree is not approved")
    return repository, expected, branch, title, body


def publish(request):
    repository, worktree, branch, title, body = validate(request)
    subprocess.run(["gh", "auth", "setup-git"], check=True)
    subprocess.run(
        [
            "git",
            "-C",
            worktree,
            "-c",
            "core.hooksPath=/dev/null",
            "push",
            f"https://github.com/{repository}.git",
            f"HEAD:refs/heads/{branch}",
        ],
        check=True,
    )
    subprocess.run(
        [
            "gh",
            "pr",
            "create",
            "--repo",
            repository,
            "--head",
            branch,
            "--base",
            "main",
            "--draft",
            "--title",
            title,
            "--body",
            body,
        ],
        check=True,
    )
    return repository, branch


offset = 0
while True:
    try:
        updates = telegram("getUpdates", offset=offset, timeout=30).get("result", [])
        for update in updates:
            offset = update["update_id"] + 1
            message = update.get("message", {})
            sender = str(message.get("from", {}).get("id", ""))
            chat = message.get("chat", {})
            chat_id = chat.get("id")
            command = message.get("text", "").split()
            if sender != allowed_user or chat.get("type") != "private" or not chat_id:
                continue
            if len(command) != 2 or command[0] not in {"/approve", "/reject"}:
                continue
            try:
                path, request = load_request(command[1])
                if command[0] == "/reject":
                    path.rename(rejected / path.name)
                    reply(chat_id, "Request rejected.")
                    continue
                repository, branch = publish(request)
                path.rename(completed / path.name)
                reply(chat_id, f"Published {branch} to {repository} as a draft PR.")
            except Exception as error:
                reply(chat_id, f"Request was not published: {error}")
    except Exception as error:
        print(error, file=sys.stderr, flush=True)
        time.sleep(5)
