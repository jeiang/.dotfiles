import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import time
import urllib.parse
import urllib.request


root = pathlib.Path(sys.argv[1]).resolve()
pending = pathlib.Path(os.environ["HERMES_PUBLISHER_PENDING"]).resolve()
mirrors = pathlib.Path(os.environ["HERMES_PUBLISHER_MIRRORS"]).resolve()
completed = root / "completed"
rejected = root / "rejected"
for directory in (pending, mirrors, completed, rejected):
    directory.mkdir(parents=True, exist_ok=True)

allowed_user = str(os.environ["HERMES_PUBLISHER_TELEGRAM_ALLOWED_USER"])
token = os.environ["HERMES_PUBLISHER_TELEGRAM_BOT_TOKEN"]
with open(os.environ["HERMES_PUBLISHER_REPOSITORIES_FILE"], encoding="utf-8") as file:
    repositories = json.load(file)
request_id = re.compile(r"[A-Za-z0-9_-]{1,80}")
branch_name = re.compile(r"codex/[A-Za-z0-9][A-Za-z0-9._/-]{0,120}")
commit_hash = re.compile(r"[0-9a-f]{40}")


def telegram(method, **data):
    payload = urllib.parse.urlencode(data).encode()
    with urllib.request.urlopen(
        f"https://api.telegram.org/bot{token}/{method}", payload, timeout=35
    ) as response:
        return json.load(response)


def reply(chat_id, text):
    telegram("sendMessage", chat_id=chat_id, text=text[:4000])


def run(*args, cwd=None):
    result = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()[-500:]
        raise RuntimeError(f"{args[0]} {args[1]} failed: {detail}")
    return result.stdout.strip()


def load_request(identifier):
    if not request_id.fullmatch(identifier):
        raise ValueError("invalid request ID")
    path = pending / f"{identifier}.json"
    if not path.is_file():
        raise FileNotFoundError("unknown or already completed request")
    if (completed / path.name).exists() or (rejected / path.name).exists():
        raise ValueError("request ID was already used")
    request = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(request, dict):
        raise ValueError("request is not an object")
    return path, request


def validate(request):
    repository = request.get("repository")
    branch = request.get("branch")
    commit = request.get("commit")
    title = request.get("title")
    body = request.get("body", "")
    if not all(isinstance(value, str) for value in (repository, branch, commit, title, body)):
        raise ValueError("request fields have invalid types")
    if repository not in repositories:
        raise ValueError("request is outside the publication policy")
    if not branch_name.fullmatch(branch) or not commit_hash.fullmatch(commit):
        raise ValueError("request is outside the publication policy")
    worktree = pathlib.Path(repositories[repository]).resolve()
    if not (worktree / ".git").exists():
        raise ValueError("request worktree is not initialized")
    return repository, worktree, branch, commit, title, body


def mirror_path(repository):
    return mirrors / f"{repository.replace('/', '__')}.git"


def archive(path, directory):
    # ReadWritePaths creates distinct bind mounts, so rename can return EXDEV.
    shutil.move(str(path), directory / path.name)


def ensure_mirror(repository):
    """Create the publisher-private bare mirror and refresh its main branch
    from GitHub. Hermes clones its worktrees from this local path, so it
    never needs a GitHub credential of its own."""
    mirror = mirror_path(repository)
    if not mirror.is_dir():
        run("git", "init", "--bare", "--initial-branch=main", str(mirror))
    run("git", "--git-dir", str(mirror), "fetch", "--no-tags", f"https://github.com/{repository}.git", "+refs/heads/main:refs/heads/main")
    return mirror


def fetch_pinned(repository, worktree, branch, commit):
    """Fetch the requested branch from the Hermes worktree into the
    publisher-private mirror and verify its tip is exactly the pinned
    commit. Git only ever executes here with publisher-owned repository
    config; the Hermes-owned worktree is accessed as an untrusted remote."""
    mirror = mirror_path(repository)
    if not mirror.is_dir():
        run("git", "init", "--bare", "--initial-branch=main", str(mirror))
    run(
        "git",
        "--git-dir",
        str(mirror),
        # The worktree belongs to the hermes user; upload-pack refuses to
        # serve a repository with dubious ownership unless it is allowed
        # here, in protected (command-line) configuration.
        "-c",
        f"safe.directory={worktree}",
        "fetch",
        "--no-tags",
        str(worktree),
        f"+refs/heads/{branch}:refs/publisher/request",
    )
    fetched = run("git", "--git-dir", str(mirror), "rev-parse", "refs/publisher/request")
    if fetched != commit:
        raise ValueError(f"branch tip {fetched[:12]} no longer matches the pinned commit {commit[:12]}")


def diff_summary(repository, commit):
    try:
        mirror = ensure_mirror(repository)
        stat = run("git", "--git-dir", str(mirror), "diff", "--stat=72", f"main...{commit}")
        return stat or "(no changes against main)"
    except RuntimeError as error:
        return f"(diff summary unavailable: {error})"


def announce(chat_id, identifier, request):
    repository, worktree, branch, commit, title, body = validate(request)
    fetch_pinned(repository, worktree, branch, commit)
    summary = diff_summary(repository, commit)
    reply(
        chat_id,
        f"Publication request {identifier}\n"
        f"Repository: {repository}\n"
        f"Branch: {branch}\n"
        f"Commit: {commit}\n"
        f"Title: {title}\n\n"
        f"{summary}\n\n"
        f"Reply /approve {identifier} or /reject {identifier}",
    )


def publish(request):
    repository, worktree, branch, commit, title, body = validate(request)
    fetch_pinned(repository, worktree, branch, commit)
    mirror = mirror_path(repository)
    run(
        "git",
        "--git-dir",
        str(mirror),
        "push",
        f"https://github.com/{repository}.git",
        f"{commit}:refs/heads/{branch}",
    )
    try:
        run(
            "gh", "pr", "create", "--repo", repository, "--head", branch,
            "--base", "main", "--draft", "--title", title, "--body", body,
        )
    except RuntimeError as error:
        existing = run("gh", "pr", "list", "--repo", repository, "--head", branch, "--json", "number")
        if not json.loads(existing):
            raise error
    return repository, branch


run("gh", "auth", "setup-git")
for repository in repositories:
    try:
        ensure_mirror(repository)
    except Exception as error:
        print(f"mirror seed for {repository} failed: {error}", file=sys.stderr, flush=True)
announced = set()
offset = 0
while True:
    try:
        for path in sorted(pending.glob("*.json")):
            identifier = path.stem
            if identifier in announced or not request_id.fullmatch(identifier):
                continue
            announced.add(identifier)
            try:
                _, request = load_request(identifier)
                announce(allowed_user, identifier, request)
            except Exception as error:
                archive(path, rejected)
                reply(allowed_user, f"Request {identifier} was rejected automatically: {error}")
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
                    archive(path, rejected)
                    reply(chat_id, "Request rejected.")
                    continue
                repository, branch = publish(request)
                archive(path, completed)
                reply(chat_id, f"Published {branch} to {repository} as a draft PR.")
            except Exception as error:
                reply(chat_id, f"Request was not published: {error}")
    except Exception as error:
        print(error, file=sys.stderr, flush=True)
        time.sleep(5)
