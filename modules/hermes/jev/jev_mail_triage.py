"""jev-mail-triage: every 15 minutes, keep only unread or flagged mail in the
iCloud INBOX. Each INBOX message is judged once with Jev (bucket choice, "needs
a reply today" noul, importance score, destination folder walk). Only unread
mail is escalated: an urgent unread message is flagged and goes into one
Telegram digest per run, while mail the user has already read is never flagged
and never raises an alert. A message that is read and not flagged moves to its
judged folder, or to Misc when the walk did not resolve one, so unflagging an
urgent message files it on the next run. The folder comes from a decision tree
-- a category and its branch question, walked into a name by the mapping below
-- so Jev never names a mailbox itself. An urgent line stays queued in
jev-mail.db until Hermes accepts a digest that carries it, so a Hermes outage
delays the digest instead of dropping it.
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
DEST_CONFIDENCE_THRESHOLD = 0.45  # set once; raise to send more read mail to FALLBACK_FOLDER.
FALLBACK_FOLDER = "Misc"
BANK_TRANSACTION_THRESHOLD = 0.5
# The destination is walked from Jev's answers, so folder names live here and
# never in a judgment: a mailbox added to the account needs an entry below to
# receive mail, and Jev can never name a folder that does not exist.
CATEGORY_FOLDERS = {
    "government": "Government",
    "work": "Work",
    "travel": "Travel",
    "gaming": "Gaming",
    "security_alert": "Alerts/Security",
    "personal": "Personal",
}
BANK_FOLDERS = {"cibc": "CIBC", "fcb": "FCB", "republic": "Republic", "scotia": "Scotia"}
NON_BANK_FINANCE_FOLDERS = {"investments": "Finance/Investments", "insurance": "Finance/Insurance"}
PURCHASE_FOLDERS = {"paypal": "Purchases/PayPal", "utility_bill": "Purchases/Bills", "other": "Purchases"}
TECH_FOLDERS = {"ai": "Dev/AI", "infra": "Dev/Infra", "github": "Dev/GitHub", "tools": "Dev/Tools"}
EDUCATION_FOLDERS = {"uwi": "Education/UWI", "virtana": "Education/Virtana", "other": "Education"}
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
    # The inbox is no longer a destination choice, so a decision naming it
    # would file its message to FALLBACK_FOLDER on a folder Jev never chose.
    inboxed = conn.execute("DELETE FROM decisions WHERE upper(folder) = ?", (INBOX,)).rowcount
    if inboxed:
        logging.info("dropped %d decisions filed to the inbox itself", inboxed)
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
        "category": {
            "type": "choice",
            "instructions": "Which single category this email belongs to.",
            "criteria": {
                "banking_finance": "From a bank, credit union, investment platform, insurer or PayPal.",
                "government": "From a government body: a ministry, tax, immigration, licensing or a .gov address.",
                "purchase": "An order, invoice, receipt, bill or payment notice from a merchant or utility.",
                "tech": "Developer, AI, hosting, infrastructure or software tooling.",
                "education": "From a university, school or course.",
                "work": "From Aidan's employer, colleagues or clients, about his job.",
                "travel": "Flights, hotels, bookings or trip itineraries.",
                "gaming": "Games, game stores or gaming services.",
                "security_alert": "About account security: a sign-in, password, verification code or breach notice.",
                "personal": "From a person writing to Aidan himself, not an organization.",
                "none": "Nothing above describes it.",
            },
        },
        # Branch questions: every one is answered from the same state and cannot
        # see the category answer, so each states its own premise and the walk
        # below reads only the branch its category selected.
        "bank_transaction": {
            "type": "noul",
            "instructions": (
                "Assume this email is from a bank, credit union or other financial institution. "
                "It reports a specific transaction: a card charge, transfer, deposit, withdrawal, "
                "payment or balance alert, rather than a statement, offer or account notice."
            ),
        },
        "institution": {
            "type": "choice",
            "instructions": "Assume this email is about money. Which institution it comes from or concerns.",
            "criteria": {
                "cibc": "CIBC, CIBC Caribbean or FirstCaribbean.",
                "fcb": "First Citizens Bank.",
                "republic": "Republic Bank.",
                "scotia": "Scotiabank.",
                "investments": "An investment, brokerage, pension or trading platform.",
                "insurance": "An insurer or an insurance policy.",
                "paypal": "PayPal.",
                "other": "Some other financial institution, or none of these.",
            },
        },
        "purchase_kind": {
            "type": "choice",
            "instructions": "Assume this email is about a purchase, invoice or bill. Which kind it is.",
            "criteria": {
                "paypal": "A PayPal payment, receipt or dispute notice.",
                "utility_bill": "A bill or statement from a utility or telecom, such as Flow, Digicel or BL&P.",
                "other": "Any other order, receipt, invoice or shipping notice.",
            },
        },
        "tech_kind": {
            "type": "choice",
            "instructions": "Assume this email is about technology. Which area it belongs to.",
            "criteria": {
                "ai": "AI models, AI products or AI research.",
                "infra": "Hosting, servers, domains, networking or cloud providers such as Hetzner, DigitalOcean or Cloudflare.",
                "github": "GitHub: repositories, pull requests, issues, actions or releases.",
                "tools": "Developer tools, libraries, editors or software releases.",
            },
        },
        "education_kind": {
            "type": "choice",
            "instructions": "Assume this email is about education. Which institution it concerns.",
            "criteria": {
                "uwi": "The University of the West Indies.",
                "virtana": "Virtana.",
                "other": "Any other school, course or training provider.",
            },
        },
    }
    return call_jev(state, questions)


def pick(answers, question):
    """The chosen option when the judgment clears the confidence floor, else
    None, so an unsure branch falls through to FALLBACK_FOLDER."""
    answer = answers.get(question) or {}
    if answer.get("confidence", 0.0) < DEST_CONFIDENCE_THRESHOLD:
        return None
    return answer.get("choice") or None


def destination(answers):
    """Walk the category and its branch into a folder name."""
    category = pick(answers, "category")
    if category in CATEGORY_FOLDERS:
        return CATEGORY_FOLDERS[category]
    if category == "banking_finance":
        institution = pick(answers, "institution")
        if institution == "paypal":
            return PURCHASE_FOLDERS["paypal"]
        bank = BANK_FOLDERS.get(institution)
        if answers.get("bank_transaction", {}).get("noul", 0.0) >= BANK_TRANSACTION_THRESHOLD:
            # Only the banks with an alert folder of their own; the rest fall through.
            return f"Alerts/Banking/{bank}" if bank else FALLBACK_FOLDER
        if bank:
            return f"Finance/{bank}"
        return NON_BANK_FINANCE_FOLDERS.get(institution, FALLBACK_FOLDER)
    if category == "purchase":
        return PURCHASE_FOLDERS.get(pick(answers, "purchase_kind"), FALLBACK_FOLDER)
    if category == "tech":
        return TECH_FOLDERS.get(pick(answers, "tech_kind"), FALLBACK_FOLDER)
    if category == "education":
        return EDUCATION_FOLDERS.get(pick(answers, "education_kind"), FALLBACK_FOLDER)
    return FALLBACK_FOLDER


def file_message(conn, envelope, uid, message_id, decision, folders):
    if not has_flag(envelope, "seen") or has_flag(envelope, "flagged"):
        return
    domain, folder = decision[0], decision[1]
    dest = folder if folder in folders else FALLBACK_FOLDER
    if himalaya("message", "move", "--from", INBOX, "--to", dest, uid) is None:
        return
    logging.info("%s filed to %s", message_id, dest)
    if dest != FALLBACK_FOLDER:
        bump_folder_history(conn, domain, dest)
    conn.execute("UPDATE decisions SET moved = 1 WHERE message_id = ?", (message_id,))
    conn.commit()


def judge_message(conn, envelope, uid, message_id, folders):
    """Judge one message and record the decision, returning it as
    (sender_domain, folder, confidence), or None when Jev gave no judgment."""
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
    }
    answers = judge(state)
    if answers is None:
        logging.warning("no judgment for %s (%r); left in INBOX, will retry next run", message_id, subject)
        return None

    bucket = answers.get("bucket", {}).get("choice", "")
    needs_reply = answers.get("needs_reply_today", {}).get("noul", 0.0)
    importance = answers.get("importance", {}).get("score", 0.0)
    category = answers.get("category", {})
    dest_folder, dest_confidence = destination(answers), category.get("confidence", 0.0)

    logging.info(
        "%s bucket=%s needs_reply=%.2f importance=%.2f category=%s(%.2f) dest=%s",
        message_id, bucket, needs_reply, importance,
        category.get("choice", ""), dest_confidence, dest_folder,
    )

    urgent_line = None
    if bucket == "urgent" and not has_flag(envelope, "seen"):
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
    return domain, dest_folder, dest_confidence


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
    if decision is None:
        decision = judge_message(conn, envelope, uid, message_id, folders)
    if decision is not None:
        file_message(conn, envelope, uid, message_id, decision, folders)


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

    # himalaya lists the inbox as "Inbox"; IMAP matches the INBOX name case-insensitively.
    destinations = [folder for folder in folders if folder.upper() != INBOX]
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
