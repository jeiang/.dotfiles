# Runs a language server inside the devshell that governs the working directory (pi-lsp starts
# servers in their root), the same lookup as the workspace extension's shell. Without one, or when
# it fails to evaluate, the server runs directly.
inherited=$PATH
root=$PWD
while :; do
  if [ -e "$root/devenv.nix" ]; then
    dev=(devenv print-dev-env --json)
    break
  elif [ -e "$root/flake.nix" ]; then
    dev=(nix print-dev-env --json "$root")
    break
  elif [ -e "$root/shell.nix" ]; then
    dev=(nix print-dev-env --json -f "$root/shell.nix")
    break
  fi
  if [ "$root" = "$HOME" ] || [ "$root" = / ]; then
    exec "$@"
  fi
  root=$(dirname "$root")
done

# Same exclusions as `nix develop`.
if exports=$(cd "$root" && "${dev[@]}" | jq -r '
  .variables | to_entries[]
  | select(.value.type == "exported" and (.value.value | type) == "string")
  | select(.key | IN("BASHOPTS", "HOME", "NIX_BUILD_TOP", "NIX_ENFORCE_PURITY", "NIX_LOG_FD", "NIX_REMOTE", "PPID", "SHELL", "SHELLOPTS", "SSL_CERT_FILE", "TEMP", "TEMPDIR", "TERM", "TMP", "TMPDIR", "TZ", "UID") | not)
  | "export \(.key)=\(.value.value | @sh)"'); then
  eval "$exports"
  PATH=$PATH:$inherited
else
  echo "pi-devshell-exec: devshell at $root failed; running $1 without it" >&2
fi
exec "$@"
