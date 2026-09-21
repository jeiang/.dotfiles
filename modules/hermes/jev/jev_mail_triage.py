"""jev-mail-triage: every 15 minutes, keep only unread or flagged mail in the
iCloud INBOX. Each INBOX message is judged once with Jev (bucket choice, "needs
a reply today" noul, importance score, destination folder choice): urgent mail
is flagged and goes into one Telegram digest per run. A later run moves a
message that is read and not flagged to its judged folder, or to Misc when that
choice was not confident, so unflagging an urgent message files it. An
urgent line stays queued in jev-mail.db until Hermes accepts a digest that
carries it, so a Hermes outage delays the digest instead of dropping it.
Idempotent: a message already logged in jev-mail.db is never re-judged. Never
blocks mail: a per-message failure (himalaya or Jev) is logged and skipped, so
one bad message can't stop the run, and an unjudged message is simply retried
next timer tick (see jev_common.call_jev's fail-open contract).

The himalaya calls below target the v2 shared API: mailboxes (not folders),
`-m/--mailbox`, `--json`, and JSON payloads wrapped in a single key
("envelopes", "mailboxes").
"""

import sqlite3
import subprocess

logging.basicConfig(level=logging.INFO, format="jev-mail: %(message)s")

ACCOUNT = "icloud"
INBOX = "INBOX"
# iCloud's own system mailboxes plus the common equivalents. Their contents say
# nothing about where a sender's mail belongs, and none of them is a triage
# destination, so they stay out of the history and out of Jev's choices.
SYSTEM_MAILBOXES = {
    "sent messages", "sent", "deleted messages", "trash",
    "junk", "junk mail", "spam", "drafts", "notes",
}
DEST_CONFIDENCE_THRESHOLD = 0.7  # set once; raise to send more read mail to FALLBACK_FOLDER.
FALLBACK_FOLDER = "Misc"
SEED_CAP_PER_FOLDER = 200
# himalaya pages envelopes (25 per page by default); one page this size covers a
# run's INBOX and the per-folder seeding cap in a single call.
PAGE_SIZE = SEED_CAP_PER_FOLDER

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


def himalaya_json(key, *args):
    """Run a himalaya command with --json and return the list under `key`
    ("envelopes", "mailboxes"), or None when the command or the parse failed."""
    out = himalaya(*args, "--json")
    if out is None:
        return None
    try:
        payload = json.loads(out)
    except json.JSONDecodeError:
        logging.warning("could not parse himalaya JSON for %s", args)
        return None
    rows = payload.get(key) if isinstance(payload, dict) else None
    if not isinstance(rows, list):
        logging.warning("himalaya %s returned no %r list", args, key)
        return None
    return rows


def is_system_mailbox(name):
    """Match the last path segment, so an "INBOX/Drafts" style name is caught too."""
    return name.rsplit("/", 1)[-1].strip().lower() in SYSTEM_MAILBOXES


def list_envelopes(mailbox):
    """None when the listing failed, [] when the mailbox is really empty."""
    return himalaya_json("envelopes", "envelope", "list", "--mailbox", mailbox, "--page-size", str(PAGE_SIZE))


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
        CREATE TABLE IF NOT EXISTS urgent_pending (message_id TEXT PRIMARY KEY, line TEXT);
        """
    )
    # Heals a database seeded before system mailboxes were excluded; a no-op
    # afterwards, because nothing writes those rows any more.
    stale = [
        folder
        for (folder,) in conn.execute("SELECT DISTINCT folder FROM folder_history").fetchall()
        if is_system_mailbox(folder or "")
    ]
    if stale:
        conn.executemany("DELETE FROM folder_history WHERE folder = ?", [(folder,) for folder in stale])
        logging.info("dropped seeded history for system mailboxes: %s", ", ".join(stale))
    # A real judgment always has a bucket; a decision without one was recorded
    # from an empty answer, so dropping it lets that message be judged again.
    unjudged = conn.execute("DELETE FROM decisions WHERE bucket = ''").rowcount
    if unjudged:
        logging.info("dropped %d decisions recorded without a judgment", unjudged)
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
    for address in envelope.get("from") or []:
        if isinstance(address, dict) and address.get("email"):
            return address["email"]
    return ""


def sender_domain(address):
    return address.split("@")[-1].lower() if "@" in address else ""


def seed_folder_history(conn, folders, mailboxes_listed):
    """One-time seed from current folder contents (capped per folder), so the
    very first triage run already has sender/folder history to reason from.
    The seed counts as done only when the mailbox list and at least one folder
    listing came back: a misconfigured himalaya lists nothing, and marking that
    run seeded would leave the history permanently empty."""
    if conn.execute("SELECT 1 FROM meta WHERE key = 'seeded'").fetchone():
        return
    seeded_any = False
    for folder in folders:
        envelopes = list_envelopes(folder)
        if envelopes is None:
            continue
        seeded_any = True
        for envelope in envelopes[:SEED_CAP_PER_FOLDER]:
            domain = sender_domain(sender_address(envelope))
            bump_folder_history(conn, domain, folder)
    if not (mailboxes_listed and seeded_any):
        conn.rollback()  # all-or-nothing, so the retry cannot double-count a folder
        logging.warning("folder history not seeded: himalaya listed nothing; retrying next run")
        return
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


def flag_name(flag):
    """himalaya renders a flag as {"raw": "\\Seen", "iana": "seen"}; `iana` is
    absent for a keyword outside the IANA registry."""
    if isinstance(flag, dict):
        return (flag.get("iana") or flag.get("raw") or "").lstrip("\\").lower()
    return str(flag).lstrip("\\").lower()


def has_flag(envelope, name):
    return any(flag_name(flag) == name for flag in envelope.get("flags") or [])


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
                "Which mail folder this message belongs in once it has been read, given "
                "the sender's history in `folder_history` below."
            ),
            "criteria": {
                folder: "Mail that fits no other folder." if folder == FALLBACK_FOLDER else ""
                for folder in state["available_folders"]
            },
        },
    }
    return call_jev(state, questions)


def file_message(conn, envelope, uid, message_id, decision, folders):
    if not has_flag(envelope, "seen") or has_flag(envelope, "flagged"):
        return
    domain, folder, confidence = decision
    confident = confidence > DEST_CONFIDENCE_THRESHOLD and folder in folders
    dest = folder if confident else FALLBACK_FOLDER
    if himalaya("message", "move", "--from", INBOX, "--to", dest, uid) is None:
        return
    logging.info("%s filed to %s", message_id, dest)
    if confident:
        bump_folder_history(conn, domain, dest)
    conn.execute("UPDATE decisions SET moved = 1 WHERE message_id = ?", (message_id,))
    conn.commit()


def process_envelope(conn, envelope, folders):
    # `id` is the backend id (IMAP UID) every himalaya command takes; it is only
    # unique within one mailbox and can be reused after an expunge, so the
    # idempotency key is the RFC 5322 Message-ID when the backend surfaced it.
    uid = str(envelope.get("id") or "")
    message_id = envelope.get("message-id") or uid
    if not uid:
        return
    decision = conn.execute(
        "SELECT sender_domain, folder, confidence FROM decisions WHERE message_id = ?", (message_id,)
    ).fetchone()
    if decision is not None:
        file_message(conn, envelope, uid, message_id, decision, folders)
        return
    # A message is filed in a run after the one that judges it, so the listing
    # already shows the flag an urgent judgment sets.
    subject = envelope.get("subject") or ""
    sender = sender_address(envelope)
    domain = sender_domain(sender)
    snippet = (himalaya("message", "read", uid, "--mailbox", INBOX) or "").strip()[:1000]

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
        return

    bucket = answers.get("bucket", {}).get("choice", "")
    needs_reply = answers.get("needs_reply_today", {}).get("noul", 0.0)
    importance = answers.get("importance", {}).get("score", 0.0)
    dest = answers.get("destination_folder", {})
    dest_folder, dest_confidence = dest.get("choice", ""), dest.get("confidence", 0.0)

    logging.info(
        "%s bucket=%s needs_reply=%.2f importance=%.2f dest=%s(%.2f)",
        message_id, bucket, needs_reply, importance, dest_folder, dest_confidence,
    )

    urgent_line = None
    if bucket == "urgent":
        himalaya("flag", "add", "--mailbox", INBOX, "--flag", "flagged", uid)
        urgent_line = f"- {subject} — {sender}"

    conn.execute(
        "INSERT INTO decisions (message_id, sender, sender_domain, subject, bucket, needs_reply, "
        "importance, folder, confidence, moved, ts) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, strftime('%s','now'))",
        (message_id, sender, domain, subject, bucket, needs_reply, importance, dest_folder, dest_confidence),
    )
    if urgent_line:
        conn.execute("INSERT INTO urgent_pending (message_id, line) VALUES (?, ?)", (message_id, urgent_line))
    conn.commit()


def main():
    if not os.environ.get("TYPESAFE_API_KEY"):
        logging.warning("TYPESAFE_API_KEY not set; every message is left untouched this run")

    os.makedirs(HERMES_HOME, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    init_db(conn)

    mailboxes = himalaya_json("mailboxes", "mailbox", "list")
    names = [m.get("name") for m in mailboxes or [] if isinstance(m, dict) and m.get("name")]
    folders = [name for name in names if not is_system_mailbox(name)] or [INBOX]
    seed_folder_history(conn, folders, mailboxes is not None)

    destinations = [folder for folder in folders if folder != INBOX]
    if destinations:
        for envelope in list_envelopes(INBOX) or []:
            try:
                process_envelope(conn, envelope, destinations)
            except Exception:
                logging.exception("failed to triage one message; skipped, will retry next run")
    else:
        logging.warning("no destination mailboxes listed; nothing judged or filed this run")

    pending = conn.execute("SELECT message_id, line FROM urgent_pending ORDER BY rowid").fetchall()
    if pending:
        digest = "Urgent mail (Jev triage):\n" + "\n".join(line for _, line in pending)
        if post_hermes_webhook(WEBHOOK_HOST, int(WEBHOOK_PORT), WEBHOOK_ROUTE, WEBHOOK_SECRET, {"digest": digest}) is not None:
            conn.executemany("DELETE FROM urgent_pending WHERE message_id = ?", [(message_id,) for message_id, _ in pending])
            conn.commit()


if __name__ == "__main__":
    main()
