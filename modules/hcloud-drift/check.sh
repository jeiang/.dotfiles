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

# HCLOUD_DRIFT_EXPECTED lets a fixture (modules/checks.nix's hcloud-drift
# flake check, or a manual test) stand in for the flake evaluation.
expected_json="${HCLOUD_DRIFT_EXPECTED:-$(nix eval --raw '.#lib.hcloudDriftExpectedJson')}"

drift=0

# Prints every line only one side has, labelled by which side, and keeps
# going: all three categories below always run and report in the same
# invocation. diff's exit 1 ("differs") is the expected drift signal, so
# it's captured explicitly rather than left to trip `set -e`; diff exiting
# >1 (a real diff failure) still aborts the script, fail-closed.
diff_lines() {
  local label=$1 expected=$2 live=$3
  local result status
  result=$(diff <(printf '%s\n' "$expected") <(printf '%s\n' "$live") 2>&1) && status=0 || status=$?
  case "$status" in
  0) return 0 ;;
  1)
    drift=1
    echo "== $label drift =="
    echo "$result" | sed -e 's/^</  expected only: /' -e 's/^>/  live only:     /' -e '/^---$/d'
    ;;
  *)
    echo "error: diff failed comparing $label (exit $status)" >&2
    echo "$result" >&2
    exit "$status"
    ;;
  esac
}

fw_name=$(jq -r '.firewall.name' <<<"$expected_json")
live_fw=$(hcloud firewall describe "$fw_name" -o json)
live_servers=$(hcloud server list -o json)
server_name_by_id=$(jq -c '[.[] | {(.id | tostring): .name}] | add // {}' <<<"$live_servers")

expected_rules=$(jq -S -c '.firewall.rules[] | .sourceIps |= sort' <<<"$expected_json" | sort -u)
# ICMP stays operator-managed (AGENTS.md); it must never fail this check.
live_rules=$(jq -S -c '.rules[] | select(.protocol != "icmp") | {direction, protocol, port, sourceIps: (.source_ips | sort)}' <<<"$live_fw" | sort -u)
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
