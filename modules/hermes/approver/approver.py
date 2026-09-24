"""Tier-2 approver: holds the hermes-t2 key and runs an allowlisted
systemctl command on a Legion node only after the operator approves it in
Telegram."""

import json
import logging
import os
import secrets
import socket
import socketserver
import subprocess
import threading
import time
import urllib.error
import urllib.request

TELEGRAM_API = "https://api.telegram.org"
SYSTEMCTL = "/run/current-system/sw/bin/systemctl"
# Hermes' terminal tool kills a command after 180 s by default. The approval
# window plus the remote command plus one poll overrun must stay inside it.
APPROVAL_TIMEOUT = 120
REMOTE_TIMEOUT = 40
POLL_SECONDS = 20
HTTP_TIMEOUT = 10
MAX_REASON = 500
MAX_OUTPUT = 3000

BOT_TOKEN = os.environ["APPROVER_TELEGRAM_BOT_TOKEN"]
USER_ID = int(os.environ["APPROVER_TELEGRAM_USER_ID"])
SSH_CONFIG = os.environ["APPROVER_SSH_CONFIG"]
SOCKET_PATH = os.environ["APPROVER_SOCKET"]
with open(os.environ["APPROVER_ALLOWLIST"]) as f:
    ALLOWED = {
        (node, c["verb"], c["unit"])
        for node, commands in json.load(f).items()
        for c in commands
    }

pending_lock = threading.Lock()
update_offset = 0


def telegram(method, http_timeout=HTTP_TIMEOUT, **params):
    body = json.dumps(params).encode()
    req = urllib.request.Request(
        f"{TELEGRAM_API}/bot{BOT_TOKEN}/{method}",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=http_timeout) as resp:
        result = json.load(resp)
    if not result.get("ok"):
        raise RuntimeError(f"Telegram {method}: {result}")
    return result["result"]


def best_effort(method, **params):
    try:
        telegram(method, **params)
    except Exception as exc:
        logging.warning("Telegram %s failed: %s", method, exc)


def skip_stale_updates():
    global update_offset
    try:
        updates = telegram("getUpdates", offset=-1, timeout=0)
    except urllib.error.HTTPError:
        raise
    except OSError as exc:
        logging.warning("could not skip stale Telegram updates: %s", exc)
        return
    if updates:
        update_offset = updates[-1]["update_id"] + 1


def wait_for_decision(nonce, deadline):
    """Return "approve", "deny" or None (expired)."""
    global update_offset
    while (remaining := deadline - time.monotonic()) > 0:
        poll = max(1, min(POLL_SECONDS, int(remaining)))
        try:
            updates = telegram(
                "getUpdates",
                http_timeout=HTTP_TIMEOUT + poll,
                offset=update_offset,
                timeout=poll,
                allowed_updates=["callback_query"],
            )
        except OSError as exc:
            logging.warning("getUpdates failed, retrying: %s", exc)
            time.sleep(min(2, max(0, deadline - time.monotonic())))
            continue
        for update in updates:
            update_offset = update["update_id"] + 1
            query = update.get("callback_query")
            if not query:
                continue
            action, _, query_nonce = query.get("data", "").partition(":")
            if query["from"]["id"] != USER_ID:
                best_effort(
                    "answerCallbackQuery",
                    callback_query_id=query["id"],
                    text="Not allowed.",
                )
                logging.warning(
                    "ignored callback from user %s", query["from"]["id"]
                )
                continue
            if query_nonce != nonce or action not in ("approve", "deny"):
                best_effort(
                    "answerCallbackQuery",
                    callback_query_id=query["id"],
                    text="This request is no longer pending.",
                )
                continue
            best_effort("answerCallbackQuery", callback_query_id=query["id"])
            return action
    return None


def run_remote(node, verb, unit):
    argv = [
        "ssh", "-F", SSH_CONFIG, node,
        "sudo", "-n", SYSTEMCTL, verb, f"{unit}.service",
    ]
    try:
        proc = subprocess.run(
            argv,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=REMOTE_TIMEOUT,
        )
    except subprocess.TimeoutExpired:
        return 124, (
            f"ssh did not return within {REMOTE_TIMEOUT} s; the systemd job "
            "may still be running, check the unit's status."
        )
    return proc.returncode, (proc.stdout + proc.stderr)[-MAX_OUTPUT:]


def validate(request):
    node = request.get("node")
    verb = request.get("verb")
    unit = request.get("unit")
    reason = request.get("reason")
    if not all(isinstance(v, str) for v in (node, verb, unit, reason)):
        return None, "node, verb, unit and reason must all be strings"
    unit = unit.removesuffix(".service")
    reason = reason.strip()
    if not reason:
        return None, "a reason is required"
    if (node, verb, unit) not in ALLOWED:
        return None, (
            f"{verb} {unit}.service on {node} is not a tier-2 command "
            "(see SERVERS.md)"
        )
    return (node, verb, unit, reason[:MAX_REASON]), None


def handle_request(request):
    command, error = validate(request)
    if error:
        logging.info("rejected request %r: %s", request, error)
        return {"status": "rejected", "exit": 1, "message": error}
    node, verb, unit, reason = command
    shown = f"{node}: systemctl {verb} {unit}.service"
    deadline = time.monotonic() + APPROVAL_TIMEOUT
    nonce = secrets.token_urlsafe(16)
    text = (
        "Hermes asks to run a tier-2 command.\n\n"
        f"Node: {node}\nCommand: systemctl {verb} {unit}.service\n\n"
        f"Reason (written by the model, unverified):\n{reason}\n\n"
        f"Expires in {APPROVAL_TIMEOUT} s."
    )
    message = telegram(
        "sendMessage",
        chat_id=USER_ID,
        text=text,
        reply_markup={"inline_keyboard": [[
            {"text": "Approve", "callback_data": f"approve:{nonce}"},
            {"text": "Deny", "callback_data": f"deny:{nonce}"},
        ]]},
    )
    logging.info("asked for approval: %s", shown)
    decision = wait_for_decision(nonce, deadline)
    edit = {"chat_id": USER_ID, "message_id": message["message_id"]}
    if decision != "approve":
        outcome = "Denied" if decision == "deny" else "Expired"
        logging.info("%s: %s", outcome.lower(), shown)
        best_effort("editMessageText", text=f"{text}\n\n{outcome}.", **edit)
        return {
            "status": outcome.lower(),
            "exit": 1,
            "message": f"The operator did not approve {shown} ({outcome}).",
        }
    best_effort("editMessageText", text=f"{text}\n\nApproved.", **edit)
    code, output = run_remote(node, verb, unit)
    logging.info("ran %s: exit %d", shown, code)
    return {
        "status": "executed",
        "exit": code,
        "output": output,
        "message": f"Approved; {shown} exited {code}.",
    }


def post_result(response):
    if response.get("status") != "executed":
        return
    text = response["message"]
    if response["output"].strip():
        text += "\n\n" + response["output"]
    best_effort("sendMessage", chat_id=USER_ID, text=text)


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        line = self.rfile.readline(4096)
        try:
            request = json.loads(line)
            if not isinstance(request, dict):
                raise ValueError("request must be a JSON object")
        except ValueError as exc:
            self.reply({"status": "rejected", "exit": 1, "message": str(exc)})
            return
        if not pending_lock.acquire(blocking=False):
            self.reply({
                "status": "busy",
                "exit": 1,
                "message": "Another tier-2 request is pending; retry later.",
            })
            return
        try:
            response = handle_request(request)
        except Exception as exc:
            logging.exception("request failed")
            response = {"status": "error", "exit": 1, "message": str(exc)}
        finally:
            pending_lock.release()
        self.reply(response)
        post_result(response)

    def reply(self, response):
        try:
            self.wfile.write(json.dumps(response).encode() + b"\n")
        except OSError as exc:
            logging.warning("client went away before the reply: %s", exc)


def notify_ready():
    address = os.environ.get("NOTIFY_SOCKET")
    if not address:
        return
    if address.startswith("@"):
        address = "\0" + address[1:]
    with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as sock:
        sock.connect(address)
        sock.sendall(b"READY=1")


def main():
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    skip_stale_updates()
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)
    server = socketserver.ThreadingUnixStreamServer(SOCKET_PATH, Handler)
    server.daemon_threads = True
    os.chmod(SOCKET_PATH, 0o660)
    notify_ready()
    logging.info("listening on %s", SOCKET_PATH)
    server.serve_forever()


if __name__ == "__main__":
    main()
