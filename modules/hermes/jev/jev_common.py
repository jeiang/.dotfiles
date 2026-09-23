"""Shared TypeSafe System One client and Hermes webhook poster for the Jev triage
scripts (concatenated ahead of each script by modules/hermes/jev/default.nix, so
these names are simply in scope -- there is no jev_common module to import at
runtime). Every call here fails open: on any Jev or network problem it returns
None / logs and continues, so a Jev outage never blocks mail triage, alert
delivery, or a memory write (AGENTS.md: Jev judgments run in code in front of
Hermes and must never become the reason something didn't happen)."""

import hashlib
import hmac
import json
import logging
import os
import time
import urllib.error
import urllib.request

JEV_API_URL = "https://api.typesafe.ai/v1/systemone"
JEV_MODEL = "jev-latest"
JEV_MAX_RETRIES = 3


def call_jev(state, questions, timeout=20):
    """POST {state, model, questions} to the System One API. Returns the answers
    dict, or None on a missing key, network failure, or exhausted 429/529
    backoff -- callers treat None as "no judgment" and fail open."""
    api_key = os.environ.get("TYPESAFE_API_KEY", "")
    if not api_key:
        logging.warning("TYPESAFE_API_KEY not set, skipping Jev call")
        return None
    body = json.dumps({"state": state, "model": JEV_MODEL, "questions": questions}).encode()
    req = urllib.request.Request(
        JEV_API_URL,
        data=body,
        method="POST",
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"},
    )
    delay = 1.0
    for attempt in range(JEV_MAX_RETRIES + 1):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return json.load(resp)["answers"]
        except urllib.error.HTTPError as exc:
            if exc.code in (429, 529) and attempt < JEV_MAX_RETRIES:
                time.sleep(delay)
                delay *= 2
                continue
            # The body carries the API's own explanation (bad key, exhausted
            # credits, malformed question); the status alone does not.
            try:
                detail = exc.read().decode("utf-8", "replace").strip()[:500]
            except Exception as read_exc:
                detail = f"<body unreadable: {read_exc}>"
            logging.warning("Jev API call failed with HTTP %s %s: %s", exc.code, exc.reason, detail)
            return None
        except Exception as exc:  # network error, timeout, bad JSON, ...
            logging.warning("Jev API call failed: %s", exc)
            return None
    return None


def post_hermes_webhook(host, port, route, secret, payload, timeout=10):
    """Best-effort POST to a Hermes webhook route, signed the way
    gateway/platforms/webhook.py's generic HMAC V2 scheme verifies it
    (hex HMAC-SHA256 of "<timestamp>.<body>", timestamp in its own header).
    Returns the HTTP status, or None on failure."""
    if not secret:
        logging.warning("no webhook secret configured, dropping delivery to route %s", route)
        return None
    body = json.dumps(payload).encode()
    timestamp = str(int(time.time()))
    signature = hmac.new(secret.encode(), timestamp.encode() + b"." + body, hashlib.sha256).hexdigest()
    req = urllib.request.Request(
        f"http://{host}:{port}/webhooks/{route}",
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "X-Webhook-Timestamp": timestamp,
            "X-Webhook-Signature-V2": signature,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status
    except Exception as exc:
        logging.warning("failed to deliver to Hermes webhook route %s: %s", route, exc)
        return None


def load_credential_env(name):
    """Parse KEY=VALUE lines from a systemd LoadCredential file into os.environ.
    Lets a service read secrets from a file it has no permission to open
    directly: PID 1 reads it as root via LoadCredential= and re-exposes it
    under $CREDENTIALS_DIRECTORY, owned by this unit's own user."""
    directory = os.environ.get("CREDENTIALS_DIRECTORY")
    if not directory:
        return
    path = os.path.join(directory, name)
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, _, value = line.partition("=")
                os.environ.setdefault(key.strip(), value.strip())
    except OSError as exc:
        logging.warning("failed to read credential %s: %s", name, exc)
