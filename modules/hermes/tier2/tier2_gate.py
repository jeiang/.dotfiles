"""hermes-ops tier-2 gate.

A ``pre_tool_call`` plugin hook over the terminal tool. A fleet command that
matches this node's tier-1 allowlist runs untouched; one that matches the
tier-2 allowlist is escalated to Hermes' own human-approval gate, which on
Telegram is an inline-keyboard prompt that fails closed on deny, on timeout
and on every unattended surface; anything else that reaches a Legion node
through sudo is refused here instead of by the remote sudoers file.

A shell hook cannot do this: ``agent/shell_hooks.py`` only translates ``block``
and ``modify``, while the ``approve`` directive that reaches
``tools.approval.request_tool_approval`` is a plugin-hook directive.
"""

import json
import logging
import os
import shlex
import uuid
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)

# {node: {"tier1": [remote argv, ...], "tier2": [...]}} -- generated from
# flake.lib.hermesOpsCommands, the same source as the Legion sudoers rules.
TIERS: Dict[str, Dict[str, List[str]]] = json.loads(
    Path(__file__).with_name("tiers.json").read_text(encoding="utf-8"))

# ssh's single-letter options that consume the next argument; the first token
# that is neither one of these nor an operand of one is the destination.
_SSH_OPTS_WITH_ARG = frozenset("BbcDEeFIiJLlmOopQRSWw")

_SUDO_FLAGS = frozenset({"-n", "--non-interactive", "-H", "--set-home"})

# The sudoers rules pin this prefix; SERVERS.md tells Hermes to use the bare
# name, so both spellings normalise to the same allowlist entry.
_REMOTE_BIN_PREFIX = "/run/current-system/sw/bin/"

_BLOCK_UNPARSED = (
    "BLOCKED by the hermes-ops tier gate: this command reaches a Legion node "
    "through sudo in a shape the gate cannot resolve to a single allowlisted "
    "command. Run one plain `ssh <node> -- sudo <command>` at a time.")

_BLOCK_INDIRECT = (
    "BLOCKED by the hermes-ops tier gate: a fleet command that needs sudo runs "
    "through the terminal tool, which is where the tier check and the approval "
    "prompt live. Call terminal with the `ssh <node> -- sudo <command>` you want.")


def _destination(tokens: List[str]) -> Optional[Tuple[str, List[str]]]:
    """``(destination, remote argv)`` for an ssh invocation, else ``None``."""
    i = 1
    while i < len(tokens) and tokens[i].startswith("-"):
        if tokens[i] == "--":
            return None
        i += 2 if len(tokens[i]) == 2 and tokens[i][1] in _SSH_OPTS_WITH_ARG else 1
    if i >= len(tokens):
        return None
    rest = tokens[i + 1:]
    if rest and rest[0] == "--":
        rest = rest[1:]
    return tokens[i], rest


def _fleet_privileged(command: str) -> bool:
    """True when the text reaches a Legion node and asks for sudo there."""
    return "sudo" in command and any(node in command for node in TIERS)


def _classify(command: str) -> Tuple[str, str, str]:
    """``(verdict, node, remote)``; verdict is ``pass``, ``approve`` or ``block``."""
    unresolved = ("block" if _fleet_privileged(command) else "pass", "", "")
    try:
        tokens = shlex.split(command)
    except ValueError:
        return unresolved
    if not tokens or os.path.basename(tokens[0]) != "ssh":
        return unresolved
    dest = _destination(tokens)
    if dest is None or dest[0] not in TIERS:
        return unresolved
    node, rest = dest
    # `ssh node "sudo systemctl stop x.service"` arrives as one token.
    if len(rest) == 1:
        try:
            rest = shlex.split(rest[0])
        except ValueError:
            return "block", node, ""
    if not rest or rest[0] != "sudo":
        # Tier 0 is read-only and holds no sudo rule anywhere in the fleet.
        return unresolved[0], node, ""
    argv = [token for token in rest[1:] if token not in _SUDO_FLAGS]
    if argv and argv[0].startswith(_REMOTE_BIN_PREFIX):
        argv[0] = argv[0][len(_REMOTE_BIN_PREFIX):]
    # An exact match against the allowlist is the whole test: a pipeline, a
    # second command or an extra argument cannot land on an entry.
    remote = " ".join(argv)
    tiers = TIERS[node]
    if remote in tiers["tier1"]:
        return "pass", node, remote
    if remote in tiers["tier2"]:
        return "approve", node, remote
    return "block", node, remote


def _on_pre_tool_call(tool_name: str = "", args: Any = None, **_: Any) -> Optional[Dict[str, str]]:
    if not isinstance(args, dict):
        return None
    if tool_name == "execute_code":
        # Python in the code sandbox can spawn its own ssh and would carry the
        # hermes-ops key past this gate, while the node's sudoers rules alone
        # cannot tell tier 1 from tier 2.
        code = args.get("code")
        if isinstance(code, str) and _fleet_privileged(code):
            return {"action": "block", "message": _BLOCK_INDIRECT}
        return None
    if tool_name != "terminal":
        return None
    command = args.get("command")
    if not isinstance(command, str) or not command.strip():
        return None
    try:
        verdict, node, remote = _classify(command)
    except Exception:
        logger.exception("hermes-ops tier gate: classification failed, blocking")
        return {"action": "block", "message": _BLOCK_UNPARSED}
    if verdict == "pass":
        return None
    if verdict == "approve":
        return {
            "action": "approve",
            "message": f"hermes-ops tier 2 on {node}: sudo {remote}",
            # A fresh key per invocation: the prompt's "Allow Session" and
            # "Always Allow" buttons key their allowlist off rule_key, and a
            # tier-2 command is approved for one execution or not at all.
            "rule_key": f"hermes-ops-tier2:{node}:{remote}:{uuid.uuid4().hex}",
        }
    if not remote:
        return {"action": "block", "message": _BLOCK_UNPARSED}
    return {
        "action": "block",
        "message": (
            f"BLOCKED by the hermes-ops tier gate: `sudo {remote}` is tier 3 on "
            f"{node} -- it is on neither allowlist, and no sudo rule exists for "
            "it anywhere in the fleet. Print the command for Aidan instead of "
            "trying another invocation."),
    }


def register(ctx) -> None:
    ctx.register_hook("pre_tool_call", _on_pre_tool_call)
