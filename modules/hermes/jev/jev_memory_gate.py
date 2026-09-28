"""Hermes shell pre_tool_call hook (services.hermes-agent.settings.hooks.pre_tool_call,
matcher "memory|fact_store") that gates writes to the built-in 'memory' tool
(MEMORY.md/USER.md) and the holographic 'fact_store' tool. Jev judges each
candidate write as durable/worth-keeping and, for an add, as possibly
contradicting the target store: below the durability floor the write is
dropped, and a likely contradiction is bounced back so the agent replaces
(memory) or contradicts (fact_store) the old entry instead (a hook can only
allow or block a call, not itself invoke a different tool).

A Jev/network failure prints the empty/allow response, never blocking the
write -- see jev_common.call_jev's fail-open contract. Non-gated tool calls
(reads, 'remove', anything but memory/fact_store) fall through untouched."""

import sys

logging.basicConfig(level=logging.INFO, stream=sys.stderr, format="jev-memory-gate: %(message)s")

DURABLE_THRESHOLD = 0.5  # set once; below this, the write is dropped.
CONTRADICTION_THRESHOLD = 0.5  # set once; at/above this, the write is bounced back.

# Only the actions that write new content; 'remove' and every read/reasoning
# action (search, probe, related, reason, contradict, list) pass through.
GATED_ACTIONS = {"memory": {"add", "replace"}, "fact_store": {"add", "update"}}


def allow():
    print("{}")


def block(message):
    print(json.dumps({"action": "block", "message": message}))


def memory_file_path(target):
    home = os.environ.get("HERMES_HOME") or os.path.join(os.environ.get("HOME", ""), ".hermes")
    return os.path.join(home, "memories", "USER.md" if target == "user" else "MEMORY.md")


def candidate_content(tool_input):
    return tool_input.get("content") or tool_input.get("new_text") or tool_input.get("old_text") or ""


def main():
    payload = json.load(sys.stdin)
    tool_name = payload.get("tool_name") or ""
    tool_input = payload.get("tool_input") or {}

    action = tool_input.get("action")
    gated = GATED_ACTIONS.get(tool_name)
    if not gated or action not in gated:
        allow()
        return

    content = candidate_content(tool_input)
    if not content:
        allow()
        return

    target = tool_input.get("target")
    try:
        with open(memory_file_path(target), encoding="utf-8") as fh:
            existing = fh.read()[:4000]
    except OSError:
        existing = ""

    if tool_name == "fact_store":
        store = "the assistant's searchable fact store, recalled on demand"
    elif target == "user":
        store = "Aidan's user profile, loaded into every future conversation"
    else:
        store = "the assistant's notes, loaded into every future conversation"

    questions = {
        "durable": {
            "type": "noul",
            "instructions": "Aidan's personal assistant wants to save `candidate_entry` to `store`. Is it worth keeping?",
            "criteria": {
                "true": (
                    "A standing preference, instruction, or convention Aidan wants followed; a lasting "
                    "fact about Aidan, the people and things in his life, or his systems; or a lesson "
                    "that keeps the assistant from repeating a mistake."
                ),
                "false": (
                    "A record of a one-off event or task progress, a state that will change within "
                    "days, or general knowledge any capable assistant already has."
                ),
            },
        },
    }
    # A replace/update is how a contradiction gets resolved, and it always
    # conflicts with the entry it supersedes.
    if action == "add":
        questions["contradicts"] = {
            "type": "noul",
            "instructions": "Does `candidate_entry` contradict an entry in `existing_entries`?",
            "criteria": {
                "true": "It states something that cannot be true at the same time as an existing entry.",
                "false": "It is new, compatible, or only adds detail to an existing entry.",
            },
        }

    answers = call_jev({"candidate_entry": content, "store": store, "existing_entries": existing}, questions)
    if answers is None:
        logging.warning("no judgment (Jev unavailable); allowing %s(%s)", tool_name, action)
        allow()
        return

    durable = answers.get("durable", {}).get("noul", 0.0)
    contradicts = answers.get("contradicts", {}).get("noul", 0.0)
    logging.info("%s(%s) durable=%.2f contradicts=%.2f", tool_name, action, durable, contradicts)

    if contradicts >= CONTRADICTION_THRESHOLD:
        resolve = (
            "fact_store(action='contradict')" if tool_name == "fact_store"
            else "memory(action='replace') on the conflicting entry instead of adding a new one"
        )
        block(f"jev-memory-gate: this may contradict existing memory (p={contradicts:.2f}). Resolve it with {resolve}.")
    elif durable < DURABLE_THRESHOLD:
        block(f"jev-memory-gate: not durable enough to store (p={durable:.2f}). Write dropped.")
    else:
        allow()


if __name__ == "__main__":
    try:
        main()
    except Exception:
        logging.exception("crashed; allowing (fail open)")
        allow()
