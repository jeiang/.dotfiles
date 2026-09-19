"""Hermes shell pre_tool_call hook (services.hermes-agent.settings.hooks.pre_tool_call,
matcher "memory|fact_store") that gates writes to the built-in 'memory' tool
(MEMORY.md/USER.md) and the holographic 'fact_store' tool. Jev judges each
candidate write as durable/worth-keeping and as possibly contradicting
existing memory: below the durability floor the write is dropped, and a
likely contradiction is bounced back so the agent resolves it with
fact_store(action='contradict') before retrying (a hook can only allow or
block a call, not itself invoke a different tool).

A Jev/network failure prints the empty/allow response, never blocking the
write -- see jev_common.call_jev's fail-open contract. Non-gated tool calls
(reads, 'remove', anything but memory/fact_store) fall through untouched."""

import sys

logging.basicConfig(level=logging.INFO, stream=sys.stderr, format="jev-memory-gate: %(message)s")

DURABLE_THRESHOLD = 0.7  # set once; below this, the write is dropped.
CONTRADICTION_THRESHOLD = 0.5  # set once; at/above this, the write is bounced back.

# Only the actions that write new content; 'remove' and every read/reasoning
# action (search, probe, related, reason, contradict, list) pass through.
GATED_ACTIONS = {"memory": {"add", "replace"}, "fact_store": {"add", "update"}}


def allow():
    print("{}")


def block(message):
    print(json.dumps({"action": "block", "message": message}))


def memory_md_path():
    home = os.environ.get("HERMES_HOME") or os.path.join(os.environ.get("HOME", ""), ".hermes")
    return os.path.join(home, "memories", "MEMORY.md")


def candidate_content(tool_input):
    return tool_input.get("content") or tool_input.get("new_text") or tool_input.get("old_text") or ""


def main():
    payload = json.load(sys.stdin)
    tool_name = payload.get("tool_name") or ""
    tool_input = payload.get("tool_input") or {}

    gated = GATED_ACTIONS.get(tool_name)
    if not gated or tool_input.get("action") not in gated:
        allow()
        return

    content = candidate_content(tool_input)
    if not content:
        allow()
        return

    try:
        with open(memory_md_path(), encoding="utf-8") as fh:
            memory_md = fh.read()[:4000]
    except OSError:
        memory_md = ""

    answers = call_jev(
        {"candidate_write": content, "memory_md": memory_md},
        {
            "durable": {
                "type": "noul",
                "instructions": (
                    "This note is durable, non-obvious, and worth carrying into future "
                    "sessions, as opposed to trivial, transient, or already obvious."
                ),
            },
            "contradicts": {
                "type": "noul",
                "instructions": "This note contradicts something already stated in `memory_md` below.",
            },
        },
    )
    if answers is None:
        logging.warning("no judgment (Jev unavailable); allowing %s(%s)", tool_name, tool_input.get("action"))
        allow()
        return

    durable = answers.get("durable", {}).get("noul", 0.0)
    contradicts = answers.get("contradicts", {}).get("noul", 0.0)
    logging.info("%s(%s) durable=%.2f contradicts=%.2f", tool_name, tool_input.get("action"), durable, contradicts)

    if durable < DURABLE_THRESHOLD:
        block(f"jev-memory-gate: not durable enough to store (p={durable:.2f}). Write dropped.")
    elif contradicts >= CONTRADICTION_THRESHOLD:
        block(
            f"jev-memory-gate: this may contradict existing memory (p={contradicts:.2f}). "
            "Check for conflicts with fact_store(action='contradict') first, then retry."
        )
    else:
        allow()


if __name__ == "__main__":
    try:
        main()
    except Exception:
        logging.exception("crashed; allowing (fail open)")
        allow()
