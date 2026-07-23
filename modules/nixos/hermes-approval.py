import argparse
import grp
import hashlib
import json
import os
import pathlib
import pwd
import re
import selectors
import secrets
import shutil
import signal
import stat
import subprocess
import sys
import time
import urllib.parse
import urllib.request


MAX_REQUEST_SIZE = 16 * 1024
MAX_COMMAND_LENGTH = 2_000
MAX_OUTPUT = 64 * 1024
DEFAULT_TIMEOUT = 600
MAX_TIMEOUT = 3_600
REQUEST_ID = re.compile(r"(?:pub|cmd|svc|cancel)-[0-9]{10}-[0-9a-f]{8}")
BRANCH_NAME = re.compile(r"codex/[A-Za-z0-9][A-Za-z0-9._/-]{0,120}")
COMMIT_HASH = re.compile(r"[0-9a-f]{40}")
SERVICE_ACTIONS = {
    "hermes-agent.service": {"start", "stop", "restart", "status"},
    "hermes-approval-broker.service": {"restart", "status"},
    "hermes-snapshot-aggregate.service": {"start", "status"},
    "hermes-memory-batch.service": {"start", "status"},
    "restic-backups-hermes.service": {"start", "status"},
    "hermes-snapshot-aggregate.timer": {"start", "stop", "restart", "status"},
    "hermes-memory-batch.timer": {"start", "stop", "restart", "status"},
    "restic-backups-hermes.timer": {"start", "stop", "restart", "status"},
}
TERMINAL_STATES = {
    "cancelled",
    "completed",
    "failed",
    "rejected",
    "timed_out",
    "uncertain",
}


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def request_hash(request):
    unsigned = {key: value for key, value in request.items() if key != "request_hash"}
    return hashlib.sha256(canonical(unsigned).encode()).hexdigest()


def validate_identifier(identifier):
    if not isinstance(identifier, str) or not REQUEST_ID.fullmatch(identifier):
        raise ValueError("invalid request ID")
    return identifier


def validate_relative_cwd(value):
    if not isinstance(value, str) or not value or "\0" in value:
        raise ValueError("invalid working directory")
    if len(value) > 500:
        raise ValueError("working directory is too long")
    path = pathlib.PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts:
        raise ValueError("working directory must stay inside the workspace")
    return value


def validate_request(request, sources=None):
    if not isinstance(request, dict) or request.get("version") != 1:
        raise ValueError("unsupported request version")
    identifier = validate_identifier(request.get("id"))
    kind = request.get("kind")
    prefixes = {
        "publication": "pub-",
        "command": "cmd-",
        "service": "svc-",
        "cancel": "cancel-",
    }
    if kind not in prefixes or not identifier.startswith(prefixes[kind]):
        raise ValueError("request ID prefix does not match its kind")
    if request.get("request_hash") != request_hash(request):
        raise ValueError("request hash does not match its contents")

    common = {"version", "id", "kind", "reason", "request_hash"}
    if not isinstance(request.get("reason"), str) or not request["reason"].strip():
        raise ValueError("request reason is required")
    if len(request["reason"]) > 500:
        raise ValueError("request reason is too long")

    if kind == "publication":
        expected = common | {"source", "branch", "commit", "title", "body"}
        if set(request) != expected:
            raise ValueError("publication request fields are invalid")
        if sources is not None and request["source"] not in sources:
            raise ValueError("publication source is outside policy")
        if not BRANCH_NAME.fullmatch(request["branch"]):
            raise ValueError("publication branch is outside policy")
        if not COMMIT_HASH.fullmatch(request["commit"]):
            raise ValueError("publication commit is invalid")
        if not isinstance(request["title"], str) or not request["title"].strip():
            raise ValueError("publication title is required")
        if len(request["title"]) > 200:
            raise ValueError("publication title is too long")
        if not isinstance(request["body"], str):
            raise ValueError("publication body is invalid")
        if len(request["body"]) > 8_000:
            raise ValueError("publication body is too long")
    elif kind == "command":
        expected = common | {"command", "cwd", "timeout"}
        if set(request) != expected:
            raise ValueError("command request fields are invalid")
        command = request["command"]
        if not isinstance(command, str) or not command or "\0" in command:
            raise ValueError("command is required")
        if len(command) > MAX_COMMAND_LENGTH:
            raise ValueError(f"command exceeds {MAX_COMMAND_LENGTH} characters")
        validate_relative_cwd(request["cwd"])
        timeout = request["timeout"]
        if not isinstance(timeout, int) or isinstance(timeout, bool):
            raise ValueError("command timeout is invalid")
        if not 1 <= timeout <= MAX_TIMEOUT:
            raise ValueError(f"command timeout must be between 1 and {MAX_TIMEOUT} seconds")
    elif kind == "service":
        expected = common | {"unit", "action"}
        if set(request) != expected:
            raise ValueError("service request fields are invalid")
        if request["unit"] not in SERVICE_ACTIONS:
            raise ValueError("service unit is outside policy")
        if request["action"] not in SERVICE_ACTIONS[request["unit"]]:
            raise ValueError("service action is outside policy")
    elif kind == "cancel":
        expected = common | {"target"}
        if set(request) != expected:
            raise ValueError("cancel request fields are invalid")
        validate_identifier(request["target"])
        if not request["target"].startswith("cmd-"):
            raise ValueError("only command requests can be cancelled")
    return identifier, kind


def atomic_json(path, value, mode=0o660):
    path = pathlib.Path(path)
    temporary = path.with_name(f".{path.name}.{secrets.token_hex(4)}.tmp")
    descriptor = os.open(
        temporary,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
        mode,
    )
    try:
        payload = (canonical(value) + "\n").encode()
        os.write(descriptor, payload)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    os.chmod(temporary, mode)
    os.replace(temporary, path)


def safe_json_file(path, expected_uid=None, expected_mode=None):
    path = pathlib.Path(path)
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
            raise ValueError("request is not a single regular file")
        if expected_uid is not None and metadata.st_uid != expected_uid:
            raise ValueError("request owner is invalid")
        if expected_mode is not None and stat.S_IMODE(metadata.st_mode) != expected_mode:
            raise ValueError("request mode is invalid")
        if metadata.st_size > MAX_REQUEST_SIZE:
            raise ValueError("request is too large")
        payload = os.read(descriptor, MAX_REQUEST_SIZE + 1)
        if len(payload) > MAX_REQUEST_SIZE:
            raise ValueError("request is too large")
    finally:
        os.close(descriptor)
    value = json.loads(payload)
    if not isinstance(value, dict):
        raise ValueError("request is not an object")
    return value


def read_sources(path):
    with open(path, encoding="utf-8") as file:
        sources = json.load(file)
    if not isinstance(sources, dict):
        raise ValueError("publication sources must be an object")
    for name, source in sources.items():
        if not isinstance(name, str) or not isinstance(source, dict):
            raise ValueError("publication source is invalid")
        if set(source) != {"repository", "worktree"}:
            raise ValueError("publication source fields are invalid")
        if not all(isinstance(value, str) for value in source.values()):
            raise ValueError("publication source values are invalid")
    return sources


def run_checked(*args, cwd=None, env=None):
    result = subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()[-500:]
        raise RuntimeError(f"{args[0]} failed: {detail}")
    return result.stdout.strip()


def status_path(status_dir, identifier):
    return pathlib.Path(status_dir) / f"{validate_identifier(identifier)}.json"


def write_status(status_dir, identifier, state, **details):
    value = {
        "id": validate_identifier(identifier),
        "state": state,
        "updated_at": int(time.time()),
        **details,
    }
    atomic_json(status_path(status_dir, identifier), value)
    return value


def read_status(status_dir, identifier):
    path = status_path(status_dir, identifier)
    if not path.is_file():
        return {"id": identifier, "state": "unknown"}
    with open(path, encoding="utf-8") as file:
        return json.load(file)


class Broker:
    def __init__(self, root):
        self.root = pathlib.Path(root).resolve()
        self.dropbox = pathlib.Path(os.environ["HERMES_APPROVAL_REQUESTS"]).resolve()
        self.status_dir = pathlib.Path(os.environ["HERMES_APPROVAL_STATUS"]).resolve()
        self.mirrors = pathlib.Path(os.environ["HERMES_APPROVAL_MIRRORS"]).resolve()
        self.dispatch = self.root / "dispatch"
        self.announced = self.root / "announced"
        self.completed = self.root / "completed"
        self.rejected = self.root / "rejected"
        self.sources = read_sources(os.environ["HERMES_APPROVAL_SOURCES_FILE"])
        self.agent_uid = pwd.getpwnam(
            os.environ.get("HERMES_APPROVAL_AGENT_USER", "hermes")
        ).pw_uid
        self.allowed_user = str(os.environ["HERMES_PUBLISHER_TELEGRAM_ALLOWED_USER"])
        self.token = os.environ["HERMES_PUBLISHER_TELEGRAM_BOT_TOKEN"]
        for directory in (
            self.dropbox,
            self.status_dir,
            self.mirrors,
            self.dispatch,
            self.announced,
            self.completed,
            self.rejected,
        ):
            if not directory.is_dir():
                raise RuntimeError(f"required approval directory is missing: {directory}")

    def telegram(self, method, **data):
        payload = urllib.parse.urlencode(data).encode()
        with urllib.request.urlopen(
            f"https://api.telegram.org/bot{self.token}/{method}",
            payload,
            timeout=35,
        ) as response:
            return json.load(response)

    def reply(self, chat_id, text):
        self.telegram("sendMessage", chat_id=chat_id, text=text[:4000])

    def mirror_path(self, repository):
        return self.mirrors / f"{repository.replace('/', '__')}.git"

    def ensure_mirror(self, repository):
        mirror = self.mirror_path(repository)
        if not mirror.is_dir():
            run_checked("git", "init", "--bare", "--initial-branch=main", str(mirror))
        run_checked(
            "git",
            "--git-dir",
            str(mirror),
            "fetch",
            "--no-tags",
            f"https://github.com/{repository}.git",
            "+refs/heads/main:refs/heads/main",
        )
        return mirror

    def publication(self, request):
        source = self.sources[request["source"]]
        worktree = pathlib.Path(source["worktree"]).resolve()
        if not (worktree / ".git").exists():
            raise ValueError("publication worktree is not initialized")
        return source["repository"], worktree

    def fetch_pinned(self, request):
        repository, worktree = self.publication(request)
        mirror = self.mirror_path(repository)
        if not mirror.is_dir():
            run_checked("git", "init", "--bare", "--initial-branch=main", str(mirror))
        run_checked(
            "git",
            "--git-dir",
            str(mirror),
            "-c",
            f"safe.directory={worktree}",
            "fetch",
            "--no-tags",
            str(worktree),
            f"+refs/heads/{request['branch']}:refs/approval/request",
        )
        fetched = run_checked(
            "git", "--git-dir", str(mirror), "rev-parse", "refs/approval/request"
        )
        if fetched != request["commit"]:
            raise ValueError(
                f"branch tip {fetched[:12]} no longer matches pinned commit "
                f"{request['commit'][:12]}"
            )
        return repository

    def diff_summary(self, request):
        try:
            repository = self.fetch_pinned(request)
            mirror = self.ensure_mirror(repository)
            summary = run_checked(
                "git",
                "--git-dir",
                str(mirror),
                "diff",
                "--stat=72",
                f"main...{request['commit']}",
            )
            return summary or "(no changes against main)"
        except RuntimeError as error:
            return f"(diff summary unavailable: {error})"

    def announcement(self, request):
        identifier = request["id"]
        if request["kind"] == "publication":
            repository, _ = self.publication(request)
            summary = self.diff_summary(request)
            return (
                f"Publication request {identifier}\n"
                f"Source: {request['source']}\n"
                f"Repository: {repository}\n"
                f"Branch: {request['branch']}\n"
                f"Commit: {request['commit']}\n"
                f"Title: {request['title']}\n"
                f"Hash: {request['request_hash']}\n\n"
                f"{summary}\n\n"
                f"Reply /approve {identifier} or /reject {identifier}"
            )
        if request["kind"] == "command":
            return (
                f"Command request {identifier}\n"
                f"CWD: {request['cwd']}\n"
                f"Timeout: {request['timeout']} seconds\n"
                f"Reason: {request['reason']}\n"
                f"Hash: {request['request_hash']}\n\n"
                f"{request['command']}\n\n"
                f"Reply /approve {identifier} or /reject {identifier}"
            )
        return (
            f"Service request {identifier}\n"
            f"Action: {request['action']}\n"
            f"Unit: {request['unit']}\n"
            f"Reason: {request['reason']}\n"
            f"Hash: {request['request_hash']}\n\n"
            f"Reply /approve {identifier} or /reject {identifier}"
        )

    def archive(self, path, directory):
        destination = directory / path.name
        if destination.exists():
            raise ValueError("request ID was already used")
        os.replace(path, destination)

    def ingest(self, path):
        identifier = path.stem
        validate_identifier(identifier)
        if (self.completed / path.name).exists() or (self.rejected / path.name).exists():
            raise ValueError("request ID was already used")
        request = safe_json_file(path, self.agent_uid, 0o640)
        validated_id, kind = validate_request(request, self.sources)
        if validated_id != identifier:
            raise ValueError("request ID does not match its filename")
        if kind == "cancel":
            self.request_cancellation(request["target"])
            path.unlink()
            write_status(
                self.status_dir,
                identifier,
                "completed",
                kind=kind,
                target=request["target"],
            )
            return
        if kind == "service" and request["action"] == "status":
            self.dispatch_request(request)
            path.unlink()
            write_status(
                self.status_dir,
                identifier,
                "approved",
                kind=kind,
            )
            return
        immutable = self.announced / path.name
        if immutable.exists():
            raise ValueError("request ID was already announced")
        atomic_json(immutable, request, 0o440)
        path.unlink()
        try:
            self.reply(self.allowed_user, self.announcement(request))
        except Exception:
            immutable.unlink(missing_ok=True)
            raise
        write_status(self.status_dir, identifier, "awaiting_approval", kind=kind)

    def scan_dropbox(self):
        with os.scandir(self.dropbox) as entries:
            paths = sorted(
                pathlib.Path(entry.path)
                for entry in entries
                if entry.name.endswith(".json")
            )
        for path in paths:
            identifier = path.stem
            try:
                self.ingest(path)
            except Exception as error:
                try:
                    if REQUEST_ID.fullmatch(identifier):
                        write_status(
                            self.status_dir,
                            identifier,
                            "rejected",
                            error=str(error),
                        )
                    path.unlink(missing_ok=True)
                finally:
                    self.reply(
                        self.allowed_user,
                        f"Request {identifier} was rejected automatically: {error}",
                    )

    def load_announced(self, identifier):
        path = self.announced / f"{validate_identifier(identifier)}.json"
        if not path.is_file():
            raise FileNotFoundError("unknown or already handled request")
        request = safe_json_file(path, os.getuid(), 0o440)
        validate_request(request, self.sources)
        return path, request

    def dispatch_request(self, request):
        path = self.dispatch / f"{request['id']}.json"
        if path.exists():
            raise ValueError("request was already dispatched")
        atomic_json(path, request, 0o440)

    def publish(self, request):
        repository = self.fetch_pinned(request)
        mirror = self.mirror_path(repository)
        run_checked(
            "git",
            "--git-dir",
            str(mirror),
            "push",
            f"https://github.com/{repository}.git",
            f"{request['commit']}:refs/heads/{request['branch']}",
        )
        existing = json.loads(
            run_checked(
                "gh",
                "pr",
                "list",
                "--repo",
                repository,
                "--head",
                request["branch"],
                "--state",
                "open",
                "--json",
                "number,isDraft",
            )
        )
        if not existing:
            run_checked(
                "gh",
                "pr",
                "create",
                "--repo",
                repository,
                "--head",
                request["branch"],
                "--base",
                "main",
                "--title",
                request["title"],
                "--body",
                request["body"],
            )
        elif existing[0]["isDraft"]:
            run_checked(
                "gh",
                "pr",
                "ready",
                str(existing[0]["number"]),
                "--repo",
                repository,
            )
        return repository

    def approve(self, chat_id, identifier):
        path, request = self.load_announced(identifier)
        self.archive(path, self.completed)
        write_status(
            self.status_dir,
            identifier,
            "approved",
            kind=request["kind"],
        )
        try:
            if request["kind"] == "publication":
                repository = self.publish(request)
                write_status(
                    self.status_dir,
                    identifier,
                    "completed",
                    repository=repository,
                    branch=request["branch"],
                    commit=request["commit"],
                )
                response = (
                    f"Published {request['branch']} to {repository} as a ready PR."
                )
            else:
                self.dispatch_request(request)
                response = f"Approved {request['kind']} request {identifier}."
        except Exception as error:
            write_status(
                self.status_dir,
                identifier,
                "failed",
                kind=request["kind"],
                error=str(error),
            )
            raise
        self.reply(chat_id, response)

    def reject(self, chat_id, identifier):
        path, request = self.load_announced(identifier)
        self.archive(path, self.rejected)
        write_status(
            self.status_dir,
            identifier,
            "rejected",
            kind=request["kind"],
        )
        self.reply(chat_id, f"Rejected {identifier}.")

    def request_cancellation(self, identifier):
        identifier = validate_identifier(identifier)
        announced = self.announced / f"{identifier}.json"
        if announced.exists():
            request = safe_json_file(announced, os.getuid(), 0o440)
            if request["kind"] != "command":
                raise ValueError("only command requests can be cancelled")
            self.archive(announced, self.rejected)
            write_status(self.status_dir, identifier, "cancelled")
            return
        if read_status(self.status_dir, identifier).get("state") in TERMINAL_STATES:
            raise ValueError("command request already finished")
        control = {
            "version": 1,
            "id": f"cancel-{int(time.time()):010d}-{secrets.token_hex(4)}",
            "kind": "cancel",
            "target": identifier,
            "reason": "cancelled through approval bot",
        }
        control["request_hash"] = request_hash(control)
        validate_request(control, self.sources)
        self.dispatch_request(control)
        write_status(self.status_dir, identifier, "cancellation_requested")

    def cancel(self, chat_id, identifier):
        self.request_cancellation(identifier)
        self.reply(chat_id, f"Cancellation requested for {identifier}.")

    def show_status(self, chat_id, identifier):
        value = read_status(self.status_dir, validate_identifier(identifier))
        output = value.pop("stdout", "")
        error = value.pop("stderr", "")
        text = canonical(value)
        if output:
            text += f"\n\nstdout:\n{output[-1500:]}"
        if error:
            text += f"\n\nstderr:\n{error[-1500:]}"
        self.reply(chat_id, text)

    def loop(self):
        run_checked("gh", "auth", "setup-git")
        for repository in sorted({source["repository"] for source in self.sources.values()}):
            try:
                self.ensure_mirror(repository)
            except Exception as error:
                print(
                    f"mirror seed for {repository} failed: {error}",
                    file=sys.stderr,
                    flush=True,
                )
        offset = 0
        while True:
            try:
                self.scan_dropbox()
                updates = self.telegram("getUpdates", offset=offset, timeout=30).get(
                    "result", []
                )
                for update in updates:
                    offset = update["update_id"] + 1
                    message = update.get("message", {})
                    sender = str(message.get("from", {}).get("id", ""))
                    chat = message.get("chat", {})
                    chat_id = chat.get("id")
                    command = message.get("text", "").split()
                    if (
                        sender != self.allowed_user
                        or chat.get("type") != "private"
                        or not chat_id
                        or len(command) != 2
                    ):
                        continue
                    try:
                        if command[0] == "/approve":
                            self.approve(chat_id, command[1])
                        elif command[0] == "/reject":
                            self.reject(chat_id, command[1])
                        elif command[0] == "/status":
                            self.show_status(chat_id, command[1])
                        elif command[0] == "/cancel":
                            self.cancel(chat_id, command[1])
                    except Exception as error:
                        self.reply(chat_id, f"Request failed: {error}")
            except Exception as error:
                print(error, file=sys.stderr, flush=True)
                time.sleep(5)


class Dispatcher:
    def __init__(self, root):
        self.root = pathlib.Path(root)
        self.dispatch = pathlib.Path(os.environ["HERMES_APPROVAL_DISPATCH"])
        self.status_dir = pathlib.Path(os.environ["HERMES_APPROVAL_STATUS"])
        self.jobs = self.root / "jobs"
        self.cancel = self.root / "cancel"
        self.inflight = self.root / "inflight"
        self.processed = self.root / "processed"
        self.sources = read_sources(os.environ["HERMES_APPROVAL_SOURCES_FILE"])
        self.broker_uid = pwd.getpwnam(
            os.environ.get(
                "HERMES_APPROVAL_BROKER_USER",
                "hermes-approval-broker",
            )
        ).pw_uid
        self.command_gid = grp.getgrnam(
            os.environ.get("HERMES_COMMAND_GROUP", "hermes-command")
        ).gr_gid

    def recover_inflight(self):
        for path in self.inflight.glob("*.json"):
            identifier = path.stem
            if REQUEST_ID.fullmatch(identifier):
                write_status(
                    self.status_dir,
                    identifier,
                    "uncertain",
                    error="dispatcher restarted after claiming the request",
                )
            os.replace(path, self.processed / path.name)

    def process(self, source_path):
        request = safe_json_file(source_path, self.broker_uid, 0o440)
        identifier, kind = validate_request(request, self.sources)
        if source_path.stem != identifier:
            raise ValueError("dispatch filename does not match request ID")
        claimed = self.inflight / source_path.name
        if claimed.exists() or (self.processed / source_path.name).exists():
            raise ValueError("dispatch request was already claimed")
        os.replace(source_path, claimed)

        if kind == "command":
            destination = self.jobs / claimed.name
            os.replace(claimed, destination)
            os.chown(destination, 0, self.command_gid)
            os.chmod(destination, 0o440)
            write_status(self.status_dir, identifier, "queued", kind=kind)
            return
        if kind == "cancel":
            marker = self.cancel / request["target"]
            descriptor = os.open(
                marker,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                0o440,
            )
            os.close(descriptor)
            os.chown(marker, 0, self.command_gid)
            os.replace(claimed, self.processed / claimed.name)
            return

        result = subprocess.run(
            ["systemctl", request["action"], request["unit"]],
            capture_output=True,
            text=True,
        )
        state = (
            "completed"
            if result.returncode == 0 or request["action"] == "status"
            else "failed"
        )
        write_status(
            self.status_dir,
            identifier,
            state,
            kind=kind,
            unit=request["unit"],
            action=request["action"],
            stdout=result.stdout.strip()[-3000:],
            stderr=result.stderr.strip()[-1000:],
        )
        os.replace(claimed, self.processed / claimed.name)

    def loop(self):
        self.recover_inflight()
        while True:
            for path in sorted(self.dispatch.glob("*.json")):
                try:
                    self.process(path)
                except Exception as error:
                    identifier = path.stem
                    if REQUEST_ID.fullmatch(identifier):
                        write_status(
                            self.status_dir,
                            identifier,
                            "failed",
                            error=str(error),
                        )
                    path.unlink(missing_ok=True)
            time.sleep(1)


def append_bounded(buffer, chunk):
    truncated = len(buffer) + len(chunk) > MAX_OUTPUT
    buffer.extend(chunk)
    if len(buffer) > MAX_OUTPUT:
        del buffer[: len(buffer) - MAX_OUTPUT]
    return truncated


def terminate_process(process):
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()


def run_bounded(command, cwd, timeout, cancel_path=None, shell="/bin/bash"):
    process = subprocess.Popen(
        [shell, "-c", command],
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ, "stdout")
    selector.register(process.stderr, selectors.EVENT_READ, "stderr")
    outputs = {"stdout": bytearray(), "stderr": bytearray()}
    truncated = {"stdout": False, "stderr": False}
    started = time.monotonic()
    state = None

    while selector.get_map():
        if cancel_path is not None and pathlib.Path(cancel_path).exists():
            state = "cancelled"
            terminate_process(process)
        elif time.monotonic() - started >= timeout:
            state = "timed_out"
            terminate_process(process)
        for key, _ in selector.select(timeout=0.2):
            chunk = os.read(key.fileobj.fileno(), 8192)
            if chunk:
                truncated[key.data] |= append_bounded(outputs[key.data], chunk)
            else:
                selector.unregister(key.fileobj)
        if state is not None and process.poll() is not None:
            continue

    return_code = process.wait()
    process.stdout.close()
    process.stderr.close()
    if state is None:
        state = "completed" if return_code == 0 else "failed"
    return {
        "state": state,
        "exit_code": return_code,
        "stdout": outputs["stdout"].decode(errors="replace"),
        "stderr": outputs["stderr"].decode(errors="replace"),
        "stdout_truncated": truncated["stdout"],
        "stderr_truncated": truncated["stderr"],
    }


class CommandRunner:
    def __init__(self, root):
        self.root = pathlib.Path(root)
        self.jobs = self.root / "jobs"
        self.cancel = self.root / "cancel"
        self.results = pathlib.Path(os.environ["HERMES_COMMAND_RESULTS"])
        self.status_dir = pathlib.Path(os.environ["HERMES_APPROVAL_STATUS"])
        self.workspace = pathlib.Path(os.environ["HERMES_COMMAND_WORKSPACE"]).resolve()
        self.shell = os.environ["HERMES_COMMAND_SHELL"]

    def recover_claims(self):
        for claim in self.results.glob("*.claim"):
            identifier = claim.stem
            status = read_status(self.status_dir, identifier)
            if status.get("state") not in TERMINAL_STATES:
                write_status(
                    self.status_dir,
                    identifier,
                    "failed",
                    error="command runner restarted during execution",
                )

    def run_job(self, path):
        request = safe_json_file(path, 0, 0o440)
        identifier, kind = validate_request(request)
        if kind != "command" or path.stem != identifier:
            raise ValueError("runner received an invalid command job")
        claim = self.results / f"{identifier}.claim"
        try:
            descriptor = os.open(
                claim,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                0o440,
            )
        except FileExistsError:
            return
        os.close(descriptor)

        cwd = (self.workspace / request["cwd"]).resolve()
        if cwd != self.workspace and self.workspace not in cwd.parents:
            raise ValueError("command working directory escaped the workspace")
        if not cwd.is_dir():
            raise ValueError("command working directory does not exist")
        write_status(
            self.status_dir,
            identifier,
            "running",
            command=request["command"],
            cwd=request["cwd"],
        )
        result = run_bounded(
            request["command"],
            cwd,
            request["timeout"],
            self.cancel / identifier,
            self.shell,
        )
        result.update(
            {
                "id": identifier,
                "command": request["command"],
                "cwd": request["cwd"],
                "finished_at": int(time.time()),
            }
        )
        atomic_json(self.results / f"{identifier}.json", result)
        write_status(self.status_dir, identifier, **result)

    def loop(self):
        self.recover_claims()
        while True:
            for path in sorted(self.jobs.glob("cmd-*.json")):
                try:
                    self.run_job(path)
                except Exception as error:
                    identifier = path.stem
                    write_status(
                        self.status_dir,
                        identifier,
                        "failed",
                        error=str(error),
                    )
            time.sleep(1)


def new_request(kind, reason, **fields):
    prefix = {"publication": "pub", "command": "cmd", "service": "svc", "cancel": "cancel"}[
        kind
    ]
    request = {
        "version": 1,
        "id": f"{prefix}-{int(time.time()):010d}-{secrets.token_hex(4)}",
        "kind": kind,
        "reason": reason,
        **fields,
    }
    request["request_hash"] = request_hash(request)
    return request


def submit_request(dropbox, request, sources=None):
    validate_request(request, sources)
    path = pathlib.Path(dropbox) / f"{request['id']}.json"
    descriptor = os.open(
        path,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
        0o640,
    )
    try:
        os.write(descriptor, (canonical(request) + "\n").encode())
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    os.chmod(path, 0o640)
    return request["id"]


def request_main(arguments):
    parser = argparse.ArgumentParser(prog="hermes-request")
    parser.add_argument(
        "--dropbox",
        default=os.environ.get("HERMES_APPROVAL_REQUESTS"),
    )
    parser.add_argument(
        "--status-dir",
        default=os.environ.get("HERMES_APPROVAL_STATUS"),
    )
    subparsers = parser.add_subparsers(dest="operation", required=True)

    publication = subparsers.add_parser("publication")
    publication.add_argument("--source", required=True)
    publication.add_argument("--branch", required=True)
    publication.add_argument("--commit", required=True)
    publication.add_argument("--title", required=True)
    publication.add_argument("--body", default="")
    publication.add_argument("--reason", required=True)

    command = subparsers.add_parser("command")
    command.add_argument("--cwd", default=".")
    command.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT)
    command.add_argument("--reason", required=True)
    command.add_argument("command")

    service = subparsers.add_parser("service")
    service.add_argument("action")
    service.add_argument("unit")
    service.add_argument("--reason", required=True)

    status_parser = subparsers.add_parser("status")
    status_parser.add_argument("id")

    wait_parser = subparsers.add_parser("wait")
    wait_parser.add_argument("id")
    wait_parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT)

    cancel = subparsers.add_parser("cancel")
    cancel.add_argument("id")
    cancel.add_argument("--reason", default="cancelled by Hermes")

    args = parser.parse_args(arguments)
    if args.operation == "status":
        print(json.dumps(read_status(args.status_dir, args.id), indent=2))
        return
    if args.operation == "wait":
        deadline = time.monotonic() + args.timeout
        while time.monotonic() < deadline:
            value = read_status(args.status_dir, args.id)
            if value.get("state") in TERMINAL_STATES:
                print(json.dumps(value, indent=2))
                return
            time.sleep(1)
        raise TimeoutError(f"request {args.id} did not finish within {args.timeout} seconds")

    if not args.dropbox:
        parser.error("approval request dropbox is not configured")
    if args.operation == "publication":
        request = new_request(
            "publication",
            args.reason,
            source=args.source,
            branch=args.branch,
            commit=args.commit,
            title=args.title,
            body=args.body,
        )
    elif args.operation == "command":
        request = new_request(
            "command",
            args.reason,
            command=args.command,
            cwd=args.cwd,
            timeout=args.timeout,
        )
    elif args.operation == "service":
        request = new_request(
            "service",
            args.reason,
            action=args.action,
            unit=args.unit,
        )
    else:
        request = new_request("cancel", args.reason, target=args.id)
    identifier = submit_request(args.dropbox, request)
    print(identifier)


def memory_batch_main():
    checkout = pathlib.Path(os.environ["HERMES_MEMORY_CHECKOUT"]).resolve()
    pending_file = pathlib.Path(os.environ["HERMES_MEMORY_PENDING_ID"])
    reviewed_file = pending_file.with_name("last-reviewed-commit")
    status_dir = pathlib.Path(os.environ["HERMES_APPROVAL_STATUS"])
    request_bin = os.environ["HERMES_REQUEST_BIN"]
    branch = run_checked("git", "-C", str(checkout), "branch", "--show-current")
    if branch != "codex/memory":
        raise RuntimeError("memory checkout must be on codex/memory")

    if pending_file.exists():
        pending = json.loads(pending_file.read_text(encoding="utf-8"))
        state = read_status(status_dir, pending["id"]).get("state")
        if state not in TERMINAL_STATES:
            return
        if state == "completed":
            reviewed_file.write_text(pending["commit"] + "\n", encoding="utf-8")
        pending_file.unlink()

    memory_paths = ["memories/hermes/MEMORY.md", "memories/hermes/USER.md"]
    run_checked("git", "-C", str(checkout), "add", "--", *memory_paths)
    staged = subprocess.run(
        ["git", "-C", str(checkout), "diff", "--cached", "--quiet", "--", *memory_paths]
    )
    if staged.returncode not in {0, 1}:
        raise RuntimeError("could not inspect staged memory changes")
    if staged.returncode == 1:
        run_checked(
            "git",
            "-C",
            str(checkout),
            "-c",
            "user.name=Hermes Agent",
            "-c",
            "user.email=31970261+jeiang@users.noreply.github.com",
            "commit",
            "-m",
            "chore(memory): update Hermes memory",
            "--",
            *memory_paths,
        )

    ahead = run_checked(
        "git", "-C", str(checkout), "rev-list", "--count", "main..HEAD"
    )
    if ahead == "0":
        return
    commit = run_checked("git", "-C", str(checkout), "rev-parse", "HEAD")
    if (
        reviewed_file.exists()
        and reviewed_file.read_text(encoding="utf-8").strip() == commit
    ):
        return
    identifier = run_checked(
        request_bin,
        "publication",
        "--source",
        "knowledge-base-memory",
        "--branch",
        "codex/memory",
        "--commit",
        commit,
        "--title",
        "chore(memory): update Hermes memory",
        "--body",
        "Daily review batch for Hermes native memory.",
        "--reason",
        "daily native memory review",
    )
    pending_file.write_text(
        canonical({"id": identifier, "commit": commit}) + "\n",
        encoding="utf-8",
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices={"broker", "dispatch", "run", "request", "memory-batch"})
    parser.add_argument("root", nargs="?")
    args, remaining = parser.parse_known_args()
    if args.mode == "broker":
        Broker(args.root).loop()
    elif args.mode == "dispatch":
        Dispatcher(args.root).loop()
    elif args.mode == "run":
        CommandRunner(args.root).loop()
    elif args.mode == "request":
        request_main(([args.root] if args.root else []) + remaining)
    else:
        memory_batch_main()


if __name__ == "__main__":
    main()
