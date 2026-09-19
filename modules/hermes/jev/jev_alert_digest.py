"""jev-alert-digest: runs once a day at 08:00, sends the accumulated "digest"
alerts jev_alert_triage.py set aside overnight as one Telegram message via the
Hermes webhook, then clears the file. Fails open: if delivery fails the file
is left in place for tomorrow's run rather than losing the entries."""


load_credential_env("hermes-env")

STATE_DIR = os.environ.get("STATE_DIRECTORY", ".")
DIGEST_PATH = os.path.join(STATE_DIR, "digest.jsonl")

WEBHOOK_HOST = os.environ.get("HERMES_WEBHOOK_HOST", "127.0.0.1")
WEBHOOK_PORT = os.environ.get("HERMES_WEBHOOK_PORT", "8644")
WEBHOOK_ROUTE = os.environ.get("HERMES_WEBHOOK_ROUTE_DIGEST", "jev-digest")
WEBHOOK_SECRET = os.environ.get("WEBHOOK_SECRET", "")


def main():
    if not os.path.exists(DIGEST_PATH):
        return
    with open(DIGEST_PATH, encoding="utf-8") as fh:
        lines = [line for line in fh if line.strip()]
    if not lines:
        return

    entries = []
    for line in lines:
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    if not entries:
        os.remove(DIGEST_PATH)
        return

    body = "\n".join(
        f"- {entry['alert'].get('labels', {}).get('alertname', '?')}: "
        f"{entry['alert'].get('annotations', {}).get('summary', '')}"
        for entry in entries
    )
    digest = f"Overnight alert digest ({len(entries)} alert(s), Jev triage):\n{body}"
    status = post_hermes_webhook(WEBHOOK_HOST, int(WEBHOOK_PORT), WEBHOOK_ROUTE, WEBHOOK_SECRET, {"digest": digest})
    if status is not None:
        os.remove(DIGEST_PATH)  # only clear once delivery actually succeeded


if __name__ == "__main__":
    main()
