"""Stubbed harness for the hermes-ops tier-2 gate.

Loads the built plugin and drives its pre_tool_call hook. The commands come
from the plugin's own tiers.json, so the fleet's unit names can change without
rewriting the expectations.
"""

import importlib.util
import json
import os
import sys

plugin_dir = os.environ["TIER2_PLUGIN"]
spec = importlib.util.spec_from_file_location("hermes_ops_tier2", f"{plugin_dir}/__init__.py")
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)

tiers = json.loads(open(f"{plugin_dir}/tiers.json", encoding="utf-8").read())
node = sorted(tiers)[0]
tier1 = tiers[node]["tier1"][0]
tier2 = next(c for c in tiers[node]["tier2"] if c != "systemctl reboot")

failures = []


def check(label, command, expected, tool_name="terminal", arg="command"):
    result = gate._on_pre_tool_call(tool_name=tool_name, args={arg: command})
    action = None if result is None else result.get("action")
    if action != expected:
        failures.append(f"{label}: expected {expected}, got {action} ({command!r})")
    return result


check("tier 1 runs unasked", f"ssh {node} -- sudo {tier1}", None)
check("tier 1 without --", f"ssh {node} sudo {tier1}", None)
check("tier 1 by absolute path",
      f"ssh {node} -- sudo /run/current-system/sw/bin/{tier1}", None)
check("tier 2 asks", f"ssh {node} -- sudo {tier2}", "approve")
check("tier 2 quoted remote", f'ssh {node} "sudo {tier2}"', "approve")
check("tier 2 behind an ssh option",
      f"ssh -o BatchMode=yes {node} -- sudo {tier2}", "approve")
check("reboot asks", f"ssh {node} -- sudo systemctl reboot", "approve")
check("tier 3 is refused", f"ssh {node} -- sudo systemctl restart sshd.service", "block")
check("tier 0 passes", f"ssh {node} -- journalctl -u sshd.service -n 50", None)
check("a chained tier-2 command is refused",
      f"ssh {node} -- sudo {tier2} && sudo systemctl reboot", "block")
check("sudo reached any other way is refused",
      f"bash -c 'ssh {node} sudo {tier2}'", "block")
check("an unrelated command passes", "systemctl status llm-server.service", None)
check("another tool passes", f"ssh {node} -- sudo {tier2}", None, tool_name="write_file")
check("the code sandbox may not reach the fleet",
      f'subprocess.run(["ssh", "{node}", "sudo", "{tier2}"])', "block",
      tool_name="execute_code", arg="code")
check("unrelated code passes", "print(1 + 1)", None, tool_name="execute_code", arg="code")

# Every node must be able to reboot under approval, and no tier-2 command may
# also be free at tier 1.
for name, entries in tiers.items():
    if "systemctl reboot" not in entries["tier2"]:
        failures.append(f"{name}: reboot missing from tier 2")
    overlap = set(entries["tier1"]) & set(entries["tier2"])
    if overlap:
        failures.append(f"{name}: commands in both tiers: {sorted(overlap)}")

# Approval is per invocation: two identical commands never share a rule key.
first = check("repeat asks again", f"ssh {node} -- sudo {tier2}", "approve")
second = check("repeat asks again", f"ssh {node} -- sudo {tier2}", "approve")
if first and second and first["rule_key"] == second["rule_key"]:
    failures.append("rule_key repeated across invocations")
if first and tier2 not in first["message"]:
    failures.append("the approval message does not name the command")

if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)
print("hermes-ops tier-2 gate: ok")
