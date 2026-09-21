"""jev-alert-triage: HTTP listener, bound to artemis's NetBird address, that
Alertmanager on legion-node3 posts to. Judges each firing alert with Jev
(page_now / digest / suppress, a "restart-fixable" noul, and a blast-radius
score) and only forwards page_now alerts to the Hermes webhook, with an
investigate-and-report-only prompt -- the 27B agent investigates, it never
self-remediates from this route. digest items accumulate in a file that
jev_alert_digest.py sends once a day; suppress is only journaled.

Never blocks alerting: a Jev/network failure falls back to "digest" (still
seen, just not paged) instead of dropping the alert (see
jev_common.call_jev's fail-open contract). Runs as the jev user; the secrets it
needs (TYPESAFE_API_KEY, WEBHOOK_SECRET, JEV_ALERT_TOKEN) come from Hermes'
own env blob via LoadCredential, which is how a non-hermes unit reads a file
sops-nix restricts to the hermes user."""

import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

logging.basicConfig(level=logging.INFO, format="jev-alert: %(message)s")

load_credential_env("hermes-env")

BIND_HOST = os.environ["JEV_ALERT_BIND_HOST"]
BIND_PORT = int(os.environ["JEV_ALERT_BIND_PORT"])
# Alertmanager cannot be configured (out of this PR's file scope, see AGENTS.md)
# to send a bearer header, so JEV_ALERT_TOKEN -- if the operator later wires it
# into Alertmanager's http_config -- is checked when present; otherwise this
# falls back to a source-IP allowlist for legion-node3's NetBird address.
JEV_ALERT_TOKEN = os.environ.get("JEV_ALERT_TOKEN", "")
ALERTMANAGER_IP = os.environ.get("JEV_ALERT_SOURCE_IP", "")

STATE_DIR = os.environ.get("STATE_DIRECTORY", ".")
DIGEST_PATH = os.path.join(STATE_DIR, "digest.jsonl")

WEBHOOK_HOST = os.environ.get("HERMES_WEBHOOK_HOST", "127.0.0.1")
WEBHOOK_PORT = os.environ.get("HERMES_WEBHOOK_PORT", "8644")
WEBHOOK_ROUTE = os.environ.get("HERMES_WEBHOOK_ROUTE_ALERT_PAGE", "jev-alert-page")
WEBHOOK_SECRET = os.environ.get("WEBHOOK_SECRET", "")

# Ported from the pre-Jev module (`git show 31c10b9^:modules/nixos/hermes/default.nix`):
# investigate-and-report only, never self-remediate.
INVESTIGATE_PROMPT = """\
A fleet alert fired via Alertmanager and Jev judged it worth paging now. Investigate before concluding anything -- don't just restate the payload.

1. Read the alert below: unit/node, condition, since when.
2. Investigate: VictoriaLogs first (SERVERS.md "Logs: VictoriaLogs"), `systemctl status`/journalctl as fallback, VictoriaMetrics if it's a resource/threshold alert.
3. Do NOT take any action from this turn -- no `systemctl restart`/`stop`, no `netbird expose`, no `sudo` command of any kind, not even a tier-1-safe one. This route is investigate-and-report only; it never self-remediates, regardless of how confident you are in a fix.
4. End with a clear diagnosis for Aidan: what fired, what you found, and the specific action you'd recommend. This response IS the Telegram message he sees -- there's no separate step to send it. If he says go, the fix happens in the normal Telegram conversation, under the usual tier policy.

Alert:
{alert}
"""


def judge(alert):
    state = {
        "alertname": alert.get("labels", {}).get("alertname", ""),
        "labels": alert.get("labels", {}),
        "annotations": alert.get("annotations", {}),
        "status": alert.get("status", ""),
        "startsAt": alert.get("startsAt", ""),
    }
    questions = {
        "action": {
            "type": "choice",
            "instructions": "How this fleet alert should be handled right now.",
            "criteria": {
                "page_now": "Wake Aidan / have the agent investigate immediately: a real, currently-broken service.",
                "digest": "Worth knowing about, but fine to summarize in the next morning digest.",
                "suppress": "Noise: flapping, expected, or not actionable.",
            },
        },
        "restart_fixable": {
            "type": "noul",
            "instructions": "This looks like a single failed systemd unit that a plain restart would likely fix.",
        },
        "blast_radius": {
            "type": "score",
            "instructions": "How much of the fleet this alert affects.",
            "criteria": [
                "Single non-critical component, no user impact.",
                "One service degraded, limited user impact.",
                "A critical service or several services affected.",
                "Fleet-wide or data-loss risk.",
            ],
        },
    }
    return call_jev(state, questions)


def append_digest(alert, answers):
    try:
        with open(DIGEST_PATH, "a", encoding="utf-8") as fh:
            fh.write(json.dumps({"alert": alert, "jev": answers}) + "\n")
    except OSError as exc:
        logging.warning("failed to append digest: %s", exc)


def handle_alert(alert):
    if alert.get("status") != "firing":
        return
    answers = judge(alert)
    alertname = alert.get("labels", {}).get("alertname", "")
    if answers is None:
        logging.warning("no judgment for %s; treated as digest", alertname)
        append_digest(alert, None)
        return

    action = answers.get("action", {}).get("choice", "digest")
    logging.info(
        "%s action=%s restart_fixable=%.2f blast_radius=%.2f",
        alertname, action,
        answers.get("restart_fixable", {}).get("noul", 0.0),
        answers.get("blast_radius", {}).get("score", 0.0),
    )
    if action == "page_now":
        prompt = INVESTIGATE_PROMPT.format(alert=json.dumps(alert, indent=2))
        post_hermes_webhook(WEBHOOK_HOST, int(WEBHOOK_PORT), WEBHOOK_ROUTE, WEBHOOK_SECRET, {"prompt": prompt})
    elif action == "digest":
        append_digest(alert, answers)
    # suppress: nothing further than the log line above.


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        logging.info(fmt, *args)

    def _authorized(self):
        auth = self.headers.get("Authorization", "")
        if JEV_ALERT_TOKEN:
            if auth == f"Bearer {JEV_ALERT_TOKEN}":
                return True
            if auth:
                return False
        return not ALERTMANAGER_IP or self.client_address[0] == ALERTMANAGER_IP

    def do_POST(self):
        if self.path != "/alert":
            self.send_response(404)
            self.end_headers()
            return
        if not self._authorized():
            self.send_response(403)
            self.end_headers()
            return
        length = int(self.headers.get("Content-Length", 0) or 0)
        raw = self.rfile.read(length) if length else b""
        # 202 immediately: triage runs off the request thread so a slow Jev
        # call can never make Alertmanager's own webhook delivery time out.
        self.send_response(202)
        self.end_headers()
        threading.Thread(target=self._process, args=(raw,), daemon=True).start()

    def _process(self, raw):
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            logging.warning("unparseable payload")
            return
        for alert in payload.get("alerts", []) or []:
            try:
                handle_alert(alert)
            except Exception:
                logging.exception("failed to triage one alert; skipped")


def main():
    os.makedirs(STATE_DIR, exist_ok=True)
    server = ThreadingHTTPServer((BIND_HOST, BIND_PORT), Handler)
    logging.info("listening on %s:%s", BIND_HOST, BIND_PORT)
    server.serve_forever()


if __name__ == "__main__":
    main()
