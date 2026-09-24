"""hermes-tier2 <node> <verb> <unit> <reason...>: ask the operator, through
hermes-approver, to run a tier-2 systemctl command on a Legion node. Blocks
until the decision and exits with the remote command's status."""

import json
import socket
import sys

SOCKET_PATH = "@socket@"
# Below the terminal tool's 180 s default, above the approver's own budget.
TIMEOUT = 175


def main():
    if len(sys.argv) < 5:
        sys.exit("usage: hermes-tier2 NODE start|stop|restart UNIT REASON...")
    node, verb, unit = sys.argv[1:4]
    request = {
        "node": node,
        "verb": verb,
        "unit": unit,
        "reason": " ".join(sys.argv[4:]),
    }
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.settimeout(TIMEOUT)
            sock.connect(SOCKET_PATH)
            sock.sendall(json.dumps(request).encode() + b"\n")
            reply = sock.makefile("rb").readline()
    except TimeoutError:
        sys.exit(
            f"hermes-tier2: no answer within {TIMEOUT} s; the outcome is "
            "unknown, check the unit's status before asking again."
        )
    except OSError as exc:
        sys.exit(f"hermes-tier2: approver unavailable ({exc}); nothing ran.")
    if not reply:
        sys.exit("hermes-tier2: approver closed the connection; nothing ran.")
    response = json.loads(reply)
    output = response.get("output", "")
    if output:
        print(output, end="" if output.endswith("\n") else "\n")
    print(f"hermes-tier2: {response['message']}", file=sys.stderr)
    sys.exit(response["exit"])


if __name__ == "__main__":
    main()
