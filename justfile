default:
  @just --list

# Format all files
fmt:
  nix fmt
  statix fix
  statix check

# Check for nix errors
check extraArgs="":
  nix flake check --keep-going {{extraArgs}}

# Same checks as `just check`, built in parallel; skips what the substituters already have
fast-check extraArgs="":
  nix-fast-build --flake '.#checks' --skip-cached --no-nom {{extraArgs}}

# Re-render docs/topology/ from the host configurations; commit the result
topology:
  #!/usr/bin/env bash
  set -euo pipefail
  system=$(nix config show system)
  out=$(nix build --no-link --print-out-paths ".#topology.$system.config.output")
  mkdir -p docs/topology
  rm -f docs/topology/*.svg
  install -m 644 "$out"/*.svg docs/topology/

# Install a host from scratch over root SSH with nixos-anywhere (wipes its disks); passes the host's facter report when one exists
clean-deploy system address *args:
  #!/usr/bin/env bash
  set -euo pipefail
  if [ "$(nix eval --json .#lib.hetznerNodes --apply 'n: n ? "{{system}}"')" = true ]; then
    facter=(--generate-hardware-config nixos-facter modules/hosts/legion/facter.json)
  elif [ -f "modules/hosts/{{system}}/facter.json" ]; then
    facter=(--generate-hardware-config nixos-facter "modules/hosts/{{system}}/facter.json")
  else
    facter=()
  fi
  nix run github:nix-community/nixos-anywhere/1.13.0 -- ${facter[@]+"${facter[@]}"} --flake .#{{system}} --target-host root@{{address}} {{args}}

# Deploy one host with deploy-rs (e.g. just deploy artemis --remote-build)
deploy system *args:
  deploy .#{{system}} {{args}}

# Regenerate .sops.yaml from the shards each host reads; the sops-config check fails while it is stale
sops-config:
  nix eval --raw '.#lib.sopsConfig' > .sops.yaml.tmp && mv .sops.yaml.tmp .sops.yaml

# Run this after `just sops-config` changes a recipient; re-keys every shard
sops-updatekeys:
  fd --full-path "$(nix eval --raw '.#lib.sopsShardRegex')" modules -x sops updatekeys -y

# Edit or create a secrets shard; a new shard needs its consumer and `just sops-config` first. Without a path, pick one with fzf
sops-edit path="":
  #!/usr/bin/env bash
  set -euo pipefail
  file={{quote(path)}}
  [ -n "$file" ] || file=$(fd --full-path "$(nix eval --raw '.#lib.sopsShardRegex')" modules | fzf)
  [ -n "$file" ] && sops "$file"

# Regenerate dns/nodes.json from flake.lib.legionNodes; the legion-nodes-json check fails while it is stale
dns-nodes:
  nix eval --raw '.#lib.legionNodesJson' > dns/nodes.json.tmp && mv dns/nodes.json.tmp dns/nodes.json

# Preview dns/dnsconfig.js against live Cloudflare; read-only — the push happens in CI on merge to main
dns-preview *args:
  CLOUDFLARE_API_TOKEN=$(sops -d --extract '["cloudflare"]["dns-token"]' modules/cloudflare/secrets.yaml) dnscontrol preview --config dns/dnsconfig.js --creds dns/creds.json {{args}}

# Compare live Hetzner Cloud firewall/Volume state to the flake; read-only, uses the operator's hcloud context
hcloud-drift:
  ./modules/hcloud-drift/check.sh

# Run from the installer: wipe, partition, format and mount the host's disks per its disko config
disko-format system sudo="sudo":
  {{sudo}} disko -f .#{{system}} --mode destroy,format,mount

# Run ON artemis, as root, BEFORE switching to a persistence.* change — impermanence never migrates data into /persist on its own
migrate-persist flake="." sudo="sudo":
  {{sudo}} nix shell nixpkgs#jq nixpkgs#rsync -c ./modules/hosts/artemis/migrate-persist.sh {{flake}}

# List paths in artemis's /persist that no persistence.* entry declares (read-only)
persist-orphans *host:
  ./modules/hosts/artemis/persist-orphans.sh . {{host}}

# Run from the installer after disko-format: install the host's configuration
install system sudo="sudo":
  {{sudo}} nixos-install --flake .#{{system}}

# Build every host toplevel and deploy profile that differs from origin/main (Linux hosts on artemis, zakkart here) and push the closures to garret, so PR CI substitutes instead of compiling; run before opening a PR and after an input bump
prepush:
  #!/usr/bin/env bash
  set -euo pipefail
  host=$(nix eval --raw .#deploy.nodes.artemis.hostname)
  push="https://$(nix eval --raw .#lib.cachePushHostname)"
  git fetch origin main
  main="git+file://$PWD?rev=$(git rev-parse origin/main)&shallow=1"
  # The root input's garret, not .nodes.garret: that name can belong to another input's pin.
  garret="github:jeiang/garret/$(jq -r '.nodes[.nodes.root.inputs.garret].locked.rev' flake.lock)#garret"
  differs() { [ "$(nix eval --raw "$main#$1")" != "$(nix eval --raw ".#$1")" ]; }
  linux=()
  for h in $(nix eval --json .#nixosConfigurations --apply builtins.attrNames | jq -r '.[]'); do
    if differs "nixosConfigurations.$h.config.system.build.toplevel.drvPath"; then
      linux+=(".#nixosConfigurations.$h.config.system.build.toplevel" ".#deploy.nodes.$h.profiles.system.path")
    fi
  done
  if [ "${#linux[@]}" -gt 0 ]; then
    outs=$(nix build --eval-store auto --store "ssh-ng://$host" --no-link --print-out-paths "${linux[@]}")
    ssh "$host" bash -s <<EOF
  set -euo pipefail
  g=\$(nix build --no-link --print-out-paths '$garret')/bin/garret
  \$g whoami >/dev/null 2>&1 || \$g login $push
  \$g push $(echo $outs)
  EOF
  fi
  if differs darwinConfigurations.zakkart.config.system.build.toplevel.drvPath; then
    out=$(nix build --no-link --print-out-paths .#darwinConfigurations.zakkart.config.system.build.toplevel)
    g=$(nix build --no-link --print-out-paths "$garret")/bin/garret
    "$g" whoami >/dev/null 2>&1 || "$g" login "$push"
    "$g" push "$out"
  fi

# Generate an image with Qwen-Image 2.1 (sd-cli args, e.g. -p "..." -o out.png; add -r in.png to edit); the first run downloads 11 GB of weights to ~/.cache/qwen-image-2.1
[no-cd, positional-arguments]
qwen-image *args:
  nix run {{justfile_directory()}}#qwen-image -- "$@"

# Copy iCloud movie files or show folders into artemis's media import queue, one verified file at a time; deletes nothing
[no-cd, positional-arguments]
icloud-media-import +paths:
  nix shell --inputs-from {{justfile_directory()}} nixpkgs#rsync -c {{justfile_directory()}}/modules/media/icloud-import.sh "$(nix eval --raw {{justfile_directory()}}#deploy.nodes.artemis.hostname)" "$(nix eval --raw {{justfile_directory()}}#lib.mediaImportDir)" "$(nix eval --raw {{justfile_directory()}}#lib.mediaIncomingDir)" "$@"

# The nb-nix token: $NETBIRD_TOKEN_FILE, else the one in the admin stash
_netbird-token:
  #!/usr/bin/env bash
  set -euo pipefail
  if [ -n "${NETBIRD_TOKEN_FILE:-}" ]; then cat "$NETBIRD_TOKEN_FILE"; else sops -d --extract '["netbird"]["nb-nix-token"]' modules/sops/secrets.admin.yaml; fi

# Plan NetBird management changes (modules/netbird-management) against live state; read-only. Token: $NETBIRD_TOKEN_FILE, else the nb-nix token in the admin stash
netbird-plan *args:
  #!/usr/bin/env bash
  set -euo pipefail
  NETBIRD_API_TOKEN=$({{just_executable()}} _netbird-token)
  export NETBIRD_API_TOKEN
  desired=$(nix build --no-link --print-out-paths .#netbird-desired)
  nix run --inputs-from . nb-nix -- plan -c "$desired" -o .netbird-plan.json {{args}}

# Apply the plan the last `just netbird-plan` wrote (add --allow-risky for deletes and other risky changes); refused if live state changed since
netbird-apply *args:
  #!/usr/bin/env bash
  set -euo pipefail
  NETBIRD_API_TOKEN=$({{just_executable()}} _netbird-token)
  export NETBIRD_API_TOKEN
  nix run --inputs-from . nb-nix -- apply {{args}} .netbird-plan.json

# Enroll over public root SSH after removing the old peer; setup_key_file is a root-only path on the target
netbird-enroll node address setup_key_file identity:
  ssh -i "{{identity}}" -o IdentitiesOnly=yes "root@{{address}}" "systemctl start netbird && netbird up --hostname '{{node}}' --setup-key-file '{{setup_key_file}}' && rm -f '{{setup_key_file}}'"

# nh runs elevated commands with HOME="" on macOS, so root's nix puts its Sentry
# database in ./.cache of the working directory; / is read-only, so none is made.
[doc('Run nh against this flake (e.g. just nh darwin switch)')]
nh *args:
  cd / && NH_FLAKE={{justfile_directory()}} nh {{args}}

# Passes --skip-checks itself; add only other deploy-rs flags (e.g. just deploy-legion --remote-build)
deploy-legion *args:
  #!/usr/bin/env bash
  set -euo pipefail
  summary=""
  failed=0
  for node in $(nix eval --raw '.#lib.legionNodes' --apply 'nodes: builtins.concatStringsSep "\n" (builtins.attrNames nodes)'); do
    if {{just_executable()}} deploy "$node" --skip-checks {{args}}; then
      summary+="  $node ok"$'\n'
    else
      summary+="  $node FAILED"$'\n'
      failed=1
    fi
  done
  echo "deploy-legion summary:"
  printf '%s' "$summary"
  exit "$failed"

# Run a command over SSH on every Legion node; prints a per-node summary and fails if any node failed
legion-run *command:
  #!/usr/bin/env bash
  set -euo pipefail
  summary=""
  failed=0
  for entry in $(nix eval --raw '.#lib' --apply 'lib: builtins.concatStringsSep "\n" (map (node: "${node}=${lib.nodeHostname node}") (builtins.attrNames lib.legionNodes))'); do
    node=${entry%%=*}
    if ssh "${entry#*=}" -- {{command}}; then
      summary+="  $node ok"$'\n'
    else
      summary+="  $node FAILED"$'\n'
      failed=1
    fi
  done
  echo "legion-run summary:"
  printf '%s' "$summary"
  exit "$failed"

# Recolor new wallpapers from assets/wallpapers/ into assets/wallpapers-kanabox/
wallpaper:
  @for f in assets/wallpapers/*.jpg assets/wallpapers/*.png; do [ -e "$f" ] || continue; [ -e "assets/wallpapers-kanabox/$(basename "$f")" ] && continue; nix run nixpkgs#lutgen -- apply -o "assets/wallpapers-kanabox/$(basename "$f")" "$f" -- $(nix eval --raw '.#lib.palette.kanaboxDarkHardHex' --apply 'p: builtins.concatStringsSep " " (builtins.attrValues p)'); done

# Register the omp mcp.json servers with Claude Code, in user scope
mcp-register-claude:
  #!/usr/bin/env bash
  set -euo pipefail
  config=~/$(nix eval --raw .#lib.agentHomes.omp)/mcp.json
  for s in $(jq -r '.mcpServers | keys[]' "$config"); do
    claude mcp remove --scope user "$s" >/dev/null 2>&1 || true
    claude mcp add-json --scope user "$s" "$(jq -c ".mcpServers.$s" "$config")"
  done

# Register the omp mcp.json servers with Codex
mcp-register-codex:
  #!/usr/bin/env bash
  set -euo pipefail
  config=~/$(nix eval --raw .#lib.agentHomes.omp)/mcp.json
  for s in $(jq -r '.mcpServers | keys[]' "$config"); do
    codex mcp remove "$s" >/dev/null 2>&1 || true
    mapfile -t args < <(jq -r ".mcpServers.$s.args[]? // empty" "$config")
    envs=()
    while IFS= read -r kv; do envs+=(--env "$kv"); done < <(jq -r ".mcpServers.$s.env // {} | to_entries[] | \"\(.key)=\(.value)\"" "$config")
    codex mcp add "$s" "${envs[@]}" -- "$(jq -r ".mcpServers.$s.command" "$config")" "${args[@]}"
  done

# Register the omp mcp.json servers with Claude Code and Codex
mcp-register: mcp-register-claude mcp-register-codex
