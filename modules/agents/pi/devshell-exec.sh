# Runs a language server inside the devshell that governs the working directory (the lsp extension
# starts servers in their root), the same lookup as the workspace extension's shell. Without one, or when
# it fails to evaluate, the server runs directly. A command that is then still missing runs from
# the nixpkgs attribute in PI_LSP_NIX; the first use fetches it.
# Evaluating a devshell costs a nix call, and a server restarts after an idle stop, so the exports are
# cached under a digest of the input files: an edited flake or lock re-evaluates, and a collected
# devshell keeps its stale exports until one does.
run() {
  if [ -n "${PI_LSP_NIX:-}" ] && ! command -v "$1" >/dev/null; then
    exec nix shell "nixpkgs#$PI_LSP_NIX" -c "$@"
  fi
  exec "$@"
}

inherited=$PATH
root=$PWD
inputs=()
while :; do
  if [ -e "$root/devenv.nix" ]; then
    dev=(devenv print-dev-env --json)
    inputs=("$root/devenv.nix" "$root/devenv.yaml" "$root/devenv.lock")
    break
  elif [ -e "$root/flake.nix" ]; then
    dev=(nix print-dev-env --json "$root")
    inputs=("$root/flake.nix" "$root/.tack/pins.toml" "$root/.tack/pins.lock.json")
    break
  elif [ -e "$root/shell.nix" ]; then
    dev=(nix print-dev-env --json -f "$root/shell.nix")
    inputs=("$root/shell.nix")
    break
  fi
  if [ "$root" = "$HOME" ] || [ "$root" = / ]; then
    run "$@"
  fi
  root=$(dirname "$root")
done

# Same exclusions as `nix develop`.
evaluate() {
  (cd "$root" && "${dev[@]}") | jq -r '
    .variables | to_entries[]
    | select(.value.type == "exported" and (.value.value | type) == "string")
    | select(.key | IN("BASHOPTS", "HOME", "NIX_BUILD_TOP", "NIX_ENFORCE_PURITY", "NIX_LOG_FD", "NIX_REMOTE", "PPID", "SHELL", "SHELLOPTS", "SSL_CERT_FILE", "TEMP", "TEMPDIR", "TERM", "TMP", "TMPDIR", "TZ", "UID") | not)
    | "export \(.key)=\(.value.value | @sh)"'
}

key=$(
  {
    printf '%s\n' "$root"
    for file in ${inputs[@]+"${inputs[@]}"}; do
      if [ -e "$file" ]; then
        printf '%s\n' "$file"
        cat "$file"
      fi
    done
  } | sha256sum | cut -d' ' -f1
)
cache=${XDG_CACHE_HOME:-$HOME/.cache}/pi-devshell-exec
file=$cache/$key.env

if [ -s "$file" ]; then
  exports=$(cat "$file")
else
  exports=$(evaluate) || exports=""
  if [ -n "$exports" ]; then
    # Exports can carry credentials a devshell sets; nobody else needs to read the cache.
    umask 077
    mkdir -p "$cache"
    printf '%s\n' "$exports" >"$file.$$"
    mv -f "$file.$$" "$file"
  fi
fi

if [ -n "$exports" ]; then
  eval "$exports"
  PATH=$PATH:$inherited
else
  echo "pi-devshell-exec: devshell at $root failed; running $1 without it" >&2
fi
run "$@"
