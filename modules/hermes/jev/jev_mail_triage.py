"""jev-mail-triage: every 15 minutes, judge each unseen iCloud INBOX message with
Jev (bucket choice, "needs a reply today" noul, importance score, destination
folder choice) and act on the result -- flag urgent mail, move mail above a
confidence floor, and send one Telegram digest of urgent items per run.
Idempotent: a message already logged in jev-mail.db is never re-judged. Never
blocks mail: a per-message failure (himalaya or Jev) is logged and skipped, so
one bad message can't stop the run, and an unjudged message is simply retried
next timer tick (see jev_common.call_jev's fail-open contract).

himalaya subcommand names/flags (flag add, message move) are the ones the real
CLI is believed to use; only "envelope list --output json", "message read", and
"folder list --output json" were given as verified in the assignment. Worth a
quick check against the installed himalaya version once the account exists.
"""

import sqlite3
import subprocess

logging.basicConfig(level=logging.INFO, format="jev-mail: %(message)s")

ACCOUNT = "icloud"
INBOX = "INBOX"
DEST_CONFIDENCE_THRESHOLD = 0.7  # set once; raise to move fewer messages, lower to move more.
SEED_CAP_PER_FOLDER = 200

HERMES_HOME = os.environ.get("HERMES_HOME") or os.path.join(os.environ.get("HOME", ""), ".hermes")
DB_PATH = os.path.join(HERMES_HOME, "jev-mail.db")

WEBHOOK_HOST = os.environ.get("HERMES_WEBHOOK_HOST", "127.0.0.1")
WEBHOOK_PORT = os.environ.get("HERMES_WEBHOOK_PORT", "8644")
WEBHOOK_ROUTE = os.environ.get("HERMES_WEBHOOK_ROUTE_DIGEST", "jev-digest")
WEBHOOK_SECRET = os.environ.get("WEBHOOK_SECRET", "")


def himalaya(*args):
    result = subprocess.run(
        ["himalaya", "--account", ACCOUNT, *args],
        capture_output=True, text=True, timeout=60, check=False,
    )
    if result.returncode != 0:
        logging.warning("himalaya %s failed: %s", args, result.stderr.strip())
        return None
    return result.stdout


def himalaya_json(*args):
    out = himalaya(*args, "--output", "json")
    if out is None:
        return None
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        logging.warning("could not parse himalaya JSON for %s", args)
        return None


def init_db(conn):
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS decisions (
            message_id TEXT PRIMARY KEY,
            sender TEXT, sender_domain TEXT, subject TEXT,
            bucket TEXT, needs_reply REAL, importance REAL,
            folder TEXT, confidence REAL, moved INTEGER, ts REAL
        );
        CREATE TABLE IF NOT EXISTS folder_history (
            sender_domain TEXT, folder TEXT, count INTEGER,
            PRIMARY KEY (sender_domain, folder)
        );
        CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
        """
    )
    conn.commit()


def bump_folder_history(conn, sender_domain, folder, by=1):
    if not sender_domain:
        return
    conn.execute(
        "INSERT INTO folder_history (sender_domain, folder, count) VALUES (?, ?, ?) "
        "ON CONFLICT(sender_domain, folder) DO UPDATE SET count = count + excluded.count",
        (sender_domain, folder, by),
    )


def sender_address(envelope):
    frm = envelope.get("from") or {}
    return frm.get("addr") or frm.get("address") or frm.get("email") or ""


def sender_domain(address):
    return address.split("@")[-1].lower() if "@" in address else ""


def seed_folder_history(conn, folders):
    """One-time seed from current folder contents (capped per folder), so the
    very first triage run already has sender/folder history to reason from."""
    if conn.execute("SELECT 1 FROM meta WHERE key = 'seeded'").fetchone():
        return
    for folder in folders:
        envelopes = himalaya_json("envelope", "list", "--folder", folder) or []
        if not isinstance(envelopes, list):
            continue
        for envelope in envelopes[:SEED_CAP_PER_FOLDER]:
            domain = sender_domain(sender_address(envelope))
            bump_folder_history(conn, domain, folder)
    conn.execute("INSERT OR REPLACE INTO meta (key, value) VALUES ('seeded', '1')")
    conn.commit()


def recent_subjects(conn, sender, limit=3):
    rows = conn.execute(
        "SELECT subject FROM decisions WHERE sender = ? ORDER BY ts DESC LIMIT ?", (sender, limit)
    ).fetchall()
    return [row[0] for row in rows]


def folder_counts(conn, domain):
    rows = conn.execute(
        "SELECT folder, count FROM folder_history WHERE sender_domain = ?", (domain,)
    ).fetchall()
    return {folder: count for folder, count in rows}


def is_unseen(envelope):
    flags = envelope.get("flags") or []
    return not any(str(flag).lower() == "seen" for flag in flags)


def judge(state):
    questions = {
        "bucket": {
            "type": "choice",
            "instructions": "Which single bucket best describes this email for an inbox triage system.",
            "criteria": {
                "urgent": "Needs Aidan's attention very soon: time-sensitive, from a person, or about money/security/an outage.",
                "action_needed": "Aidan needs to do something about it, but not urgently today.",
                "reference": "Worth keeping for later lookup (receipt, confirmation, statement) but needs no action.",
                "newsletter": "A subscribed newsletter, digest, or bulk update.",
                "junk": "Unsolicited marketing or spam Aidan would delete unread.",
            },
        },
        "needs_reply_today": {
            "type": "noul",
            "instructions": "This email needs a reply from Aidan today, not just eventually.",
        },
        "importance": {
            "type": "score",
            "instructions": "How important this email is to Aidan.",
            "criteria": [
                "Not important: safe to ignore or delete.",
                "Minor: nice to know, no consequence if missed.",
                "Notable: relevant to Aidan's work or life, worth reading this week.",
                "Critical: financial, security, health, or relationship consequence if missed.",
            ],
        },
        "destination_folder": {
            "type": "choice",
            "instructions": (
                "Which existing mail folder this message belongs in, given the sender's "
                "history in `folder_history` below. Prefer INBOX when unsure."
            ),
            "criteria": {folder: "" for folder in state["available_folders"]},
        },
    }
    return call_jev(state, questions)


def process_envelope(conn, envelope, folders):
    message_id = str(envelope.get("id") or envelope.get("Id") or "")
    if not message_id or not is_unseen(envelope):
        return None
    if conn.execute("SELECT 1 FROM decisions WHERE message_id = ?", (message_id,)).fetchone():
        return None  # idempotent: already judged in a previous run

    subject = envelope.get("subject") or envelope.get("Subject") or ""
    sender = sender_address(envelope)
    domain = sender_domain(sender)
    snippet = (himalaya("message", "read", message_id, "--folder", INBOX) or "").strip()[:1000]

    state = {
        "subject": subject,
        "sender": sender,
        "snippet": snippet,
        "folder_history": folder_counts(conn, domain),
        "recent_subjects_from_sender": recent_subjects(conn, sender),
        "available_folders": folders,
    }
    answers = judge(state)
    if answers is None:
        logging.warning("no judgment for %s (%r); left in INBOX, will retry next run", message_id, subject)
        return None

    bucket = answers.get("bucket", {}).get("choice", "")
    needs_reply = answers.get("needs_reply_today", {}).get("noul", 0.0)
    importance = answers.get("importance", {}).get("score", 0.0)
    dest = answers.get("destination_folder", {})
    dest_folder, dest_confidence = dest.get("choice", INBOX), dest.get("confidence", 0.0)

    logging.info(
        "%s bucket=%s needs_reply=%.2f importance=%.2f dest=%s(%.2f)",
        message_id, bucket, needs_reply, importance, dest_folder, dest_confidence,
    )

    urgent_line = None
    if bucket == "urgent":
        himalaya("flag", "add", message_id, "Flagged", "--folder", INBOX)
        urgent_line = f"- {subject} — {sender}"

    moved = 0
    if dest_confidence > DEST_CONFIDENCE_THRESHOLD and dest_folder and dest_folder != INBOX:
        if himalaya("message", "move", message_id, dest_folder, "--folder", INBOX) is not None:
            bump_folder_history(conn, domain, dest_folder)
            moved = 1

    conn.execute(
        "INSERT INTO decisions (message_id, sender, sender_domain, subject, bucket, needs_reply, "
        "importance, folder, confidence, moved, ts) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, strftime('%s','now'))",
        (message_id, sender, domain, subject, bucket, needs_reply, importance, dest_folder, dest_confidence, moved),
    )
    conn.commit()
    return urgent_line


def main():
    if not os.environ.get("TYPESAFE_API_KEY"):
        logging.warning("TYPESAFE_API_KEY not set; every message is left untouched this run")

    os.makedirs(HERMES_HOME, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    init_db(conn)

    folders_raw = himalaya_json("folder", "list") or []
    folders = [f.get("name") or f.get("Name") for f in folders_raw if isinstance(f, dict)] if isinstance(folders_raw, list) else []
    folders = [f for f in folders if f] or [INBOX]
    seed_folder_history(conn, folders)

    envelopes = himalaya_json("envelope", "list", "--folder", INBOX) or []
    if not isinstance(envelopes, list):
        envelopes = []

    urgent_digest = []
    for envelope in envelopes:
        try:
            line = process_envelope(conn, envelope, folders)
        except Exception:
            logging.exception("failed to triage one message; skipped, will retry next run")
            continue
        if line:
            urgent_digest.append(line)

    if urgent_digest:
        digest = "Urgent mail (Jev triage):\n" + "\n".join(urgent_digest)
        post_hermes_webhook(WEBHOOK_HOST, int(WEBHOOK_PORT), WEBHOOK_ROUTE, WEBHOOK_SECRET, {"digest": digest})


if __name__ == "__main__":
    main()
