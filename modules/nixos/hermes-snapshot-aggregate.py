import json
import os
import sys
import time
import urllib.parse
import urllib.request


def get_json(url):
    with urllib.request.urlopen(url, timeout=10) as response:
        return json.load(response)


def write_report(target, report):
    os.makedirs(os.path.dirname(target), exist_ok=True)
    temporary = f"{target}.tmp"
    with open(temporary, "w", encoding="utf-8") as file:
        json.dump(report, file, sort_keys=True)
        file.write("\n")
    os.replace(temporary, target)
    history = os.path.join(os.path.dirname(target), "history")
    os.makedirs(history, exist_ok=True)
    with open(os.path.join(history, f"{int(time.time())}.json"), "w", encoding="utf-8") as file:
        json.dump(report, file, sort_keys=True)
        file.write("\n")


target = sys.argv[1]
metrics_base = sys.argv[2]
snapshots = {}
for address in sys.argv[3:]:
    try:
        snapshots[address] = {"snapshot": get_json(f"http://{address}:9787/current.json")}
    except Exception as error:
        snapshots[address] = {"error": str(error)}

query = urllib.parse.urlencode({"query": "node_memory_MemAvailable_bytes"})
try:
    monitoring = get_json(f"{metrics_base}/api/v1/query?{query}")
except Exception as error:
    monitoring = {"error": str(error)}

write_report(
    target,
    {
        "collected_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "snapshots": snapshots,
        "monitoring": monitoring,
    },
)
