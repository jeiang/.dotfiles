import json
import os
import shutil
import socket
import subprocess
import sys
import time


def command(*args):
    # A missing binary raises FileNotFoundError before the process runs, which
    # check=False does not catch; treat any failure to launch as empty output
    # so an absent tool degrades a field instead of crashing the snapshot.
    try:
        return subprocess.run(args, check=False, capture_output=True, text=True).stdout.strip()
    except OSError:
        return ""


def meminfo():
    values = {}
    with open("/proc/meminfo", encoding="utf-8") as file:
        for line in file:
            key, value, *_ = line.split()
            values[key[:-1]] = int(value) * 1024
    return {"total_bytes": values["MemTotal"], "available_bytes": values["MemAvailable"]}


def unit(name):
    properties = command("systemctl", "show", name, "--property=ActiveState,NRestarts", "--value").splitlines()
    return {
        "active": properties[0] == "active" if properties else False,
        "restarts": int(properties[1]) if len(properties) > 1 and properties[1].isdigit() else 0,
    }


def filesystem(path):
    usage = shutil.disk_usage(path)
    return {"path": path, "total_bytes": usage.total, "used_bytes": usage.used, "free_bytes": usage.free}


def backup_units():
    units = command(
        "systemctl",
        "list-units",
        "--type=service",
        "--all",
        "--plain",
        "--no-legend",
        "restic-backups-*.service",
    ).splitlines()
    return {line.split()[0]: unit(line.split()[0]) for line in units if line.split()}


services = filter(None, os.environ.get("HERMES_SNAPSHOT_SERVICES", "").split(","))
volumes = filter(None, os.environ.get("HERMES_SNAPSHOT_VOLUMES", "").split(","))
report = {
    "collected_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "hostname": socket.gethostname(),
    "memory": meminfo(),
    "load_average": list(os.getloadavg()),
    "boot_id": open("/proc/sys/kernel/random/boot_id", encoding="utf-8").read().strip(),
    "generation": os.path.realpath("/run/current-system"),
    "services": {name: unit(name) for name in services},
    "filesystems": [filesystem(path) for path in volumes if os.path.ismount(path)],
    "backup_units": backup_units(),
}
target = sys.argv[1]
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
