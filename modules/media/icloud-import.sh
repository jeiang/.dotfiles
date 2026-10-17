#!/usr/bin/env bash
# Copies iCloud Drive files or folders into artemis's media import queue, one
# file at a time: reading a file downloads it, rsync verifies it by checksum,
# and brctl evicts it again, so the Mac never holds more than one file.
# Each argument becomes one organizer item (a movie file or a show folder),
# and appears in import/ only once all of its files are verified.
# Nothing is deleted from iCloud.
# Usage: ./icloud-import.sh host media-root PATH...

set -euo pipefail

host=$1
media=$2
shift 2
control=$(mktemp -u "${TMPDIR:-/tmp}/icloud-import.XXXXXX")
ssh_cmd="ssh -o ControlMaster=auto -o ControlPath=$control -o ControlPersist=60"
trap '$ssh_cmd -O exit "$host" 2>/dev/null || true' EXIT

# Single-quotes one argument for the remote login shell, which is fish.
fq() {
  local s=${1//\\/\\\\}
  s=${s//\'/\\\'}
  printf "'%s'" "$s"
}

for src in "$@"; do
  src=${src%/}
  entry=$(basename "$src")
  if $ssh_cmd "$host" test -e "$(fq "$media/import/$entry")"; then
    echo "skip $entry: already in import/"
    continue
  fi

  base=$(dirname "$src")
  while IFS= read -r -d '' file; do
    rel=${file#"$base"/}
    dest="$media/.incoming/$rel"
    echo "copy $rel"
    rsync --checksum --times --mkpath --protect-args -e "$ssh_cmd" "$file" "$host:$dest"
    if ! diff=$(rsync --checksum --dry-run --itemize-changes --protect-args -e "$ssh_cmd" "$file" "$host:$dest") || [[ -n $diff ]]; then
      echo >&2 "error: could not verify $rel on $host"
      exit 1
    fi
    brctl evict "$file" >/dev/null || echo >&2 "warning: could not evict $rel"
  done < <(find "$src" -type f ! -name .DS_Store -print0)

  # The organizer runs as another member of the media group and moves files out.
  staging="$media/.incoming/$entry"
  $ssh_cmd "$host" chmod -R g+rwX "$(fq "$staging")"
  $ssh_cmd "$host" mv "$(fq "$staging")" "$(fq "$media/import/")"
  echo "queued $entry"
done
