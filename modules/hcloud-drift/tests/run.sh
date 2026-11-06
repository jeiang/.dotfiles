#!/usr/bin/env bash
# Usage: run.sh <check.sh> <fixtures dir> <the flake's expected JSON file>
# Runs check.sh against recorded hcloud output: a fake `hcloud` reads the case
# directory, and HCLOUD_DRIFT_EXPECTED replaces the flake evaluation.
set -euo pipefail

script=$1
fixtures=$2
flake_expected=$3

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

export HCLOUD_TOKEN=test

hcloud() {
  if [ -e "$HCLOUD_TEST_DIR/fail" ]; then
    echo "fake hcloud: simulated failure" >&2
    return 1
  fi
  case "$1 $2" in
  "firewall describe") cat "$HCLOUD_TEST_DIR/firewall.json" ;;
  "server list") cat "$HCLOUD_TEST_DIR/servers.json" ;;
  "volume list") cat "$HCLOUD_TEST_DIR/volumes.json" ;;
  *)
    echo "fake hcloud: unhandled args: $*" >&2
    return 1
    ;;
  esac
}
export -f hcloud

fail=0
status=0

run_case() {
  local name=$1 dir=$2 expected=$3
  status=0
  HCLOUD_TEST_DIR=$dir HCLOUD_DRIFT_EXPECTED=$(cat "$expected") bash "$script" >"$work/$name.out" 2>&1 || status=$?
}

report() {
  echo "FAIL $1: $2" >&2
  cat "$work/$1.out" >&2
  fail=1
}

expect_clean() {
  if [ "$status" -ne 0 ] || ! grep -qF "no drift" "$work/$1.out"; then
    report "$1" "expected no drift, exit $status"
  fi
}

expect_failure() {
  local name=$1 needle
  shift
  [ "$status" -ne 0 ] || report "$name" "expected a nonzero exit, got 0"
  for needle in "$@"; do
    grep -qF "$needle" "$work/$name.out" || report "$name" "missing '$needle' in output"
  done
}

fixture() {
  run_case "$1" "$fixtures/$1" "$fixtures/expected.json"
}

fixture baseline
expect_clean baseline

fixture all_drift
expect_failure all_drift "rules drift" "attachments drift" "Volumes drift"

fixture source_ips_narrowed
expect_failure source_ips_narrowed "rules drift"

fixture ipv4_only
expect_failure ipv4_only "rules drift"

fixture icmp_added
expect_clean icmp_added

fixture hcloud_fails
expect_failure hcloud_fails "simulated failure"
if grep -qF "no drift" "$work/hcloud_fails.out"; then
  report hcloud_fails "printed 'no drift' despite the hcloud failure"
fi

# Live state rendered from the flake's own expected JSON must show no drift.
flake="$work/flake"
mkdir "$flake"
jq '.firewall.attachments + [.volumes[].node] | unique | to_entries | map({id: (.key + 1), name: .value})' \
  "$flake_expected" >"$flake/servers.json"
jq --slurpfile servers "$flake/servers.json" '
  ($servers[0] | map({(.name): .id}) | add) as $ids
  | {
      id: 1,
      name: .firewall.name,
      rules: [.firewall.rules[] | {direction, protocol, port, source_ips: .sourceIps, destination_ips: [], description: null}],
      applied_to: [.firewall.attachments[] | {type: "server", server: {id: $ids[.]}}]
    }
' "$flake_expected" >"$flake/firewall.json"
jq --slurpfile servers "$flake/servers.json" '
  ($servers[0] | map({(.name): .id}) | add) as $ids
  | [.volumes[] | {id: (.id | tonumber), name, size: .sizeGiB, server: $ids[.node]}]
' "$flake_expected" >"$flake/volumes.json"
run_case flake "$flake" "$flake_expected"
expect_clean flake

exit "$fail"
