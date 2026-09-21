#!/usr/bin/env bash
# Test double for the one curl invocation shape check.sh uses
# (`curl -sS -o file -w '%{http_code}' -H ... url`), fed by NETBIRD_TEST_DIR
# fixtures. Not general curl emulation; used only by modules/checks.nix's
# netbird-invariants flake check.
set -euo pipefail

dir="${NETBIRD_TEST_DIR:?NETBIRD_TEST_DIR not set}"

if [ -e "$dir/fail" ]; then
  echo "fake curl: simulated network failure" >&2
  exit 7
fi

out=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "-o" ]; then
    out="$arg"
  fi
  prev="$arg"
done

url="$*"
url="${url##* }"
path="${url#*/api/}"
fixture="${path//\//-}"

status=200
[ -f "$dir/$fixture.status" ] && status=$(cat "$dir/$fixture.status")

if [ -f "$dir/$fixture.nojson" ]; then
  printf '<html>not json</html>' >"$out"
elif [ -f "$dir/$fixture.json" ]; then
  cp "$dir/$fixture.json" "$out"
else
  printf '{}' >"$out"
fi

printf '%s' "$status"
