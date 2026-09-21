#!/usr/bin/env bash
# Read-only: GETs the self-hosted NetBird management API and checks it
# against modules/netbird-invariants's expected JSON, never a mutating
# call. Detects only; a dashboard operator fixes what it reports. See
# AGENTS.md's NetBird DNS decision for why these invariants exist.
set -euo pipefail

base_url="${NETBIRD_API_BASE_URL:-https://netbird.jeiang.dev/api}"

if [ -z "${NETBIRD_API_TOKEN:-}" ]; then
  echo "error: NETBIRD_API_TOKEN is empty" >&2
  exit 1
fi

# NETBIRD_INVARIANTS_EXPECTED lets a fixture (modules/checks.nix's
# netbird-invariants flake check, or a manual test) stand in for the flake
# evaluation.
expected_json="${NETBIRD_INVARIANTS_EXPECTED:-$(nix eval --raw '.#lib.netbirdInvariantsExpectedJson')}"

violations=0

# GETs one endpoint. Fails closed: any transport error, non-200 status, or
# non-JSON body exits the whole script immediately, never printing a
# success line.
api_get() {
  local path=$1 tmp status
  tmp=$(mktemp)
  status=$(curl -sS -o "$tmp" -w '%{http_code}' -H "Authorization: Token ${NETBIRD_API_TOKEN}" "${base_url}${path}") || {
    echo "error: request to GET $path failed" >&2
    rm -f "$tmp"
    exit 1
  }
  if [ "$status" != "200" ]; then
    echo "error: GET $path returned HTTP $status" >&2
    rm -f "$tmp"
    exit 1
  fi
  if ! jq -e . "$tmp" >/dev/null 2>&1; then
    echo "error: GET $path did not return valid JSON" >&2
    rm -f "$tmp"
    exit 1
  fi
  cat "$tmp"
  rm -f "$tmp"
}

# Runs a jq script that prints one violation description per line (no
# output = that category is clean). The jq call's own `||` means a script
# error is one more violation rather than a trap under `set -e`, so a
# failure in one category never hides the rest.
run_check() {
  local label=$1 json=$2 script=$3
  local lines
  if ! lines=$(jq -r --argjson expected "$expected_json" "$script" <<<"$json" 2>&1); then
    violations=$((violations + 1))
    echo "VIOLATION ($label): jq evaluation failed: $lines"
    return 0
  fi
  [ -z "$lines" ] && return 0
  while IFS= read -r line; do
    violations=$((violations + 1))
    echo "VIOLATION ($label): $line"
  done <<<"$lines"
}

dns_groups=$(api_get "/dns/nameservers")
networks=$(api_get "/networks")
accounts=$(api_get "/accounts")
services=$(api_get "/reverse-proxies/services")

# Merges each network's resources and routers into one array for run_check.
networks_detail="[]"
while IFS= read -r net_id; do
  net=$(jq -c --arg id "$net_id" '.[] | select(.id == $id)' <<<"$networks")
  resources=$(api_get "/networks/${net_id}/resources")
  routers=$(api_get "/networks/${net_id}/routers")
  networks_detail=$(jq -c --argjson net "$net" --argjson resources "$resources" --argjson routers "$routers" \
    '. + [$net + {resources: $resources, routers: $routers}]' <<<"$networks_detail")
done < <(jq -r '.[].id' <<<"$networks")

run_check "quad9-search-domain" "$dns_groups" '
  [.[] | select((.domains // []) | index($expected.quad9Domain))] as $matches
  | if ($matches | length) == 0 then
      "no nameserver group matches domain \($expected.quad9Domain)"
    else
      ($matches[] | select(.search_domains_enabled != false)
        | "nameserver group \(.name // .id) matching \($expected.quad9Domain) has search_domains_enabled=\(.search_domains_enabled)")
    end
'

run_check "primary-nameserver-group" "$dns_groups" '
  [.[] | select(.primary == true)] as $primary
  | if ($primary | length) == 0 then
      "no primary (all-domains) nameserver group found"
    elif ($primary | length) > 1 then
      "multiple primary nameserver groups found: \($primary | map(.name // .id) | join(", "))"
    else
      ($primary[0]) as $g
      | [
          (if $g.enabled != true then "primary nameserver group \($g.name // $g.id) is disabled" else empty end),
          (if ($g.nameservers[0].ip // null) != $expected.primaryNameservers[0].ip
            or ($g.nameservers[0].port // null) != $expected.primaryNameservers[0].port
          then
            "primary nameserver group \($g.name // $g.id) primary nameserver is \($g.nameservers[0].ip // "?"):\($g.nameservers[0].port // "?"), expected \($expected.primaryNameservers[0].ip):\($expected.primaryNameservers[0].port)"
          else empty end),
          (if ($g.nameservers[1].ip // null) != $expected.primaryNameservers[1].ip
            or ($g.nameservers[1].port // null) != $expected.primaryNameservers[1].port
          then
            "primary nameserver group \($g.name // $g.id) secondary nameserver is \($g.nameservers[1].ip // "?"):\($g.nameservers[1].port // "?"), expected \($expected.primaryNameservers[1].ip):\($expected.primaryNameservers[1].port)"
          else empty end)
        ][]
    end
'

run_check "legion-node2-network" "$networks_detail" '
  ($expected.legionNode2Ip) as $ip
  | [.[] | . as $net | ($net.resources // [])[]
      | select((.address // "" | sub("/32$"; "")) == $ip)
      | {net: $net, resource: .}] as $matches
  | if ($matches | length) == 0 then
      "no network resource matches \($ip)"
    else
      (
        [$matches[] | select(.resource.enabled != true)
          | "resource \(.resource.name // .resource.id) for \($ip) in network \(.net.name // .net.id) is disabled"]
        + (
            $matches
            | map(select(.resource.enabled == true))
            | unique_by(.net.id)
            | map(select(((.net.routers // []) | any(.enabled == true)) | not))
            | map("network \(.net.name // .net.id) has an enabled resource for \($ip) but no enabled router")
          )
      )[]
    end
'

run_check "client-auto-update" "$accounts" '
  if (length != 1) then
    "expected exactly one account, got \(length)"
  else
    (.[0].settings.auto_update_version) as $v
    | if $v != $expected.autoUpdateVersion then
        "account client auto-update is \($v // "unset"), expected \($expected.autoUpdateVersion)"
      else empty end
  end
'

run_check "reverse-proxy-crowdsec-mode" "$services" '
  .[] | select((.access_restrictions.crowdsec_mode // "off") != $expected.crowdsecMode)
  | "reverse-proxy service \(.domain // .name // .id) CrowdSec mode is \(.access_restrictions.crowdsec_mode // "off"), expected \($expected.crowdsecMode)"
'

if [ "$violations" -gt 0 ]; then
  echo "netbird control-plane invariants violated ($violations)" >&2
  exit 1
fi

echo "ok: netbird control-plane matches the expected invariants"
