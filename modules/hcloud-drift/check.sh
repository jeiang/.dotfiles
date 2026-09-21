#!/usr/bin/env bash
# Read-only: compares live Hetzner Cloud firewall/Volume state (via `hcloud`,
# list/describe only) against modules/hcloud-drift's expected JSON, and exits
# non-zero on any discrepancy. See AGENTS.md's Cloud Firewall / Volume
# "Decisions that constrain changes" for what counts as drift.
set -euo pipefail

if [ -z "${HCLOUD_TOKEN:-}" ] && ! hcloud context active >/dev/null 2>&1; then
  echo "error: no HCLOUD_TOKEN and no active hcloud context" >&2
  exit 1
fi

expected_json=$(nix eval --raw '.#lib.hcloudDriftExpectedJson')

drift=0

# Prints every line only one side has, labelled by which side. Reused for
# rules, attachments and volumes: each is reduced to one JSON object per line
# before diffing, so a missing/extra/changed entry is a single readable line.
diff_lines() {
  local label=$1 expected=$2 live=$3
  if [ "$expected" != "$live" ]; then
    drift=1
    echo "== $label drift =="
    diff <(echo "$expected") <(echo "$live") | sed -e 's/^</  expected only: /' -e 's/^>/  live only:     /' -e '/^---$/d'
  fi
}

fw_name=$(jq -r '.firewall.name' <<<"$expected_json")
live_fw=$(hcloud firewall describe "$fw_name" -o json)
live_servers=$(hcloud server list -o json)
server_name_by_id=$(jq -c '[.[] | {(.id | tostring): .name}] | add // {}' <<<"$live_servers")

expected_rules=$(jq -S -c '.firewall.rules[]' <<<"$expected_json" | sort -u)
# ICMP stays operator-managed (AGENTS.md); it must never fail this check.
live_rules=$(jq -S -c '.rules[] | select(.protocol != "icmp") | {direction, protocol, port}' <<<"$live_fw" | sort -u)
diff_lines "firewall '$fw_name' rules" "$expected_rules" "$live_rules"

expected_attachments=$(jq -S -c '.firewall.attachments[]' <<<"$expected_json" | sort -u)
live_attachments=$(jq -S -c --argjson names "$server_name_by_id" '
  .applied_to[] | if .type == "server"
    then ($names[.server.id | tostring] // "server:\(.server.id)")
    else "label_selector:\(.label_selector.selector)"
    end
' <<<"$live_fw" | sort -u)
diff_lines "firewall '$fw_name' attachments" "$expected_attachments" "$live_attachments"

live_volumes_raw=$(hcloud volume list -o json)
expected_volumes=$(jq -S -c '.volumes[]' <<<"$expected_json" | sort -u)
live_volumes=$(jq -S -c --argjson names "$server_name_by_id" '
  .[] | {
    id: (.id | tostring),
    name,
    sizeGiB: .size,
    node: (if .server == null then null else ($names[.server | tostring] // "server:\(.server)") end)
  }
' <<<"$live_volumes_raw" | sort -u)
diff_lines "Volumes" "$expected_volumes" "$live_volumes"

if [ "$drift" -eq 0 ]; then
  echo "no drift: live Hetzner Cloud state matches the flake"
else
  echo "hcloud state has drifted from the flake" >&2
fi

exit "$drift"
