default:
  @just --list

# Format all files
fmt:
  nix fmt
  statix fix
  statix check

# Check for nix errors
check extraArgs="":
  nix flake check --impure --keep-going {{extraArgs}}

# Same checks as `just check`, built in parallel; skips what the substituters already have
fast-check extraArgs="":
  nix-fast-build --flake '.#checks' --skip-cached --no-nom {{extraArgs}}

# Re-render docs/topology/ from the host configurations; commit the result
topology:
  #!/usr/bin/env bash
  set -euo pipefail
  system=$(nix eval --impure --raw --expr builtins.currentSystem)
  out=$(nix build --no-link --print-out-paths ".#topology.$system.config.output")
  mkdir -p docs/topology
  rm -f docs/topology/*.svg
  install -m 644 "$out"/*.svg docs/topology/

clean-deploy system address *args:
  #!/usr/bin/env bash
  set -euo pipefail
  case "{{system}}" in
    legion-node*) facter=modules/hosts/legion/facter.json ;;
    *) facter=modules/hosts/{{system}}/facter.json ;;
  esac
  nix run github:nix-community/nixos-anywhere/1.13.0 -- --generate-hardware-config nixos-facter "$facter" --flake .#{{system}} --target-host root@{{address}} {{args}}

deploy system *args:
  deploy .#{{system}} {{args}}

# Run this after a .sops.yaml recipient change; re-keys every shard
sops-updatekeys:
  fd '^secrets(\.[^.]+)?\.(yaml|env|ini|json)$' modules -x sops updatekeys -y

# Edit or view the secrets
sops-edit:
  #!/usr/bin/env bash
  set -euo pipefail
  file=$(fd "secrets.([^.]+.)?(yaml|env|ini|json)" | fzf)
  [ -n "$file" ] && sops "$file"

sops-create path:
  sops {{path}}

# Regenerate dns/nodes.json from flake.lib.legionNodes; the legion-nodes-json check fails while it is stale
dns-nodes:
  nix eval --raw '.#lib.legionNodesJson' > dns/nodes.json

# Preview dns/dnsconfig.js against live Cloudflare; read-only — the push happens in CI on merge to main
dns-preview *args:
  CLOUDFLARE_API_TOKEN=$(sops -d --extract '["caddy"]["cloudflare-dns-token"]' modules/edge/secrets.yaml) dnscontrol preview --config dns/dnsconfig.js --creds dns/creds.json {{args}}

# Compare live Hetzner Cloud firewall/Volume state to the flake; read-only, uses the operator's hcloud context
hcloud-drift:
  ./modules/hcloud-drift/check.sh

disko-format system sudo="sudo":
  {{sudo}} disko -f .#{{system}} --mode destroy,format,mount

# Run ON artemis, as root, BEFORE switching to a persistence.* change — impermanence never migrates data into /persist on its own
migrate-persist flake="." sudo="sudo":
  {{sudo}} nix shell nixpkgs#jq nixpkgs#rsync -c ./modules/hosts/artemis/migrate-persist.sh {{flake}}

install system sudo="sudo":
  {{sudo}} nixos-install --flake .#{{system}}

# Free artemis's dGPU for a game; the gamemode hooks do this automatically
llm-stop:
  ssh artemis.jeiang.vpn doas systemctl stop llm-server.service

# Start the artemis model server again after a manual llm-stop
llm-start:
  ssh artemis.jeiang.vpn doas systemctl start llm-server.service

# Show the artemis model server unit and, when rocm-smi is there, its VRAM use
llm-status:
  ssh artemis.jeiang.vpn 'systemctl status llm-server.service --no-pager -n 5; command -v rocm-smi >/dev/null && rocm-smi --showmeminfo vram; true'

# Generate an image with Qwen-Image 2.1 (sd-cli args, e.g. -p "..." -o out.png; add -r in.png to edit); the first run downloads 11 GB of weights to ~/.cache/qwen-image-2.1
[no-cd, positional-arguments]
qwen-image *args:
  nix run {{justfile_directory()}}#qwen-image -- "$@"

# A formula-only brew upgrade swaps the daemon binary without restarting the
# running launchd job, so kickstart re-bootstraps it after the upgrade.

# Upgrade the NetBird brew formula and cask, then restart the launchd job
netbird-update:
  brew upgrade netbirdio/tap/netbird netbirdio/tap/netbird-ui
  sudo launchctl bootout system/netbird 2>/dev/null || true
  sudo launchctl bootstrap system /Library/LaunchDaemons/netbird.plist
  sudo launchctl kickstart -k system/netbird
  netbird status | grep -i version

# Read-only check of the self-hosted NetBird control-plane against modules/netbird-invariants's expected invariants; needs NETBIRD_API_TOKEN (an Auditor-role PAT)
netbird-invariants:
  nix shell --inputs-from . nixpkgs#jq nixpkgs#curl -c ./modules/netbird-invariants/check.sh

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
    if just deploy "$node" --skip-checks {{args}}; then
      summary+="  $node ok"$'\n'
    else
      summary+="  $node FAILED"$'\n'
      failed=1
    fi
  done
  echo "deploy-legion summary:"
  printf '%s' "$summary"
  exit "$failed"

legion-run *command:
  #!/usr/bin/env bash
  set -euo pipefail
  summary=""
  failed=0
  for node in $(nix eval --raw '.#lib.legionNodes' --apply 'nodes: builtins.concatStringsSep "\n" (builtins.attrNames nodes)'); do
    if ssh "${node#legion-}.jeiang.dev" -- {{command}}; then
      summary+="  $node ok"$'\n'
    else
      summary+="  $node FAILED"$'\n'
      failed=1
    fi
  done
  echo "legion-run summary:"
  printf '%s' "$summary"
  exit "$failed"

# Delete assets/wallpapers-kanabox/ outputs before re-running after a palette change; existing files are left alone.

# Recolor new wallpapers from assets/wallpapers/ into assets/wallpapers-kanabox/
wallpaper:
  @for f in assets/wallpapers/*.jpg assets/wallpapers/*.png; do [ -e "$f" ] || continue; [ -e "assets/wallpapers-kanabox/$(basename "$f")" ] && continue; nix run nixpkgs#lutgen -- apply -o "assets/wallpapers-kanabox/$(basename "$f")" "$f" -- $(nix eval --raw '.#lib.palette.kanaboxDarkHard' --apply 'p: builtins.concatStringsSep " " (map (c: builtins.substring 1 6 c) (builtins.attrValues p))'); done

# Register the ~/.omp/agent/mcp.json servers with Claude Code, in user scope
mcp-register-claude:
  #!/usr/bin/env bash
  set -euo pipefail
  for s in $(jq -r '.mcpServers | keys[]' ~/.omp/agent/mcp.json); do
    claude mcp remove --scope user "$s" >/dev/null 2>&1 || true
    claude mcp add-json --scope user "$s" "$(jq -c ".mcpServers.$s" ~/.omp/agent/mcp.json)"
  done

# Register the ~/.omp/agent/mcp.json servers with Codex
mcp-register-codex:
  #!/usr/bin/env bash
  set -euo pipefail
  for s in $(jq -r '.mcpServers | keys[]' ~/.omp/agent/mcp.json); do
    codex mcp remove "$s" >/dev/null 2>&1 || true
    mapfile -t args < <(jq -r ".mcpServers.$s.args[]? // empty" ~/.omp/agent/mcp.json)
    codex mcp add "$s" -- "$(jq -r ".mcpServers.$s.command" ~/.omp/agent/mcp.json)" "${args[@]}"
  done

# Register the ~/.omp/agent/mcp.json servers with Claude Code and Codex
mcp-register: mcp-register-claude mcp-register-codex
