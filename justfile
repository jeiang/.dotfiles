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

# Preview dns/dnsconfig.js against live Cloudflare; read-only — the push happens in CI on merge to main
dns-preview *args:
  CLOUDFLARE_API_TOKEN=$(sops -d --extract '["caddy"]["cloudflare-dns-token"]' modules/edge/secrets.yaml) dnscontrol preview --config dns/dnsconfig.js --creds dns/creds.json {{args}}

disko-format system sudo="sudo":
  {{sudo}} disko -f .#{{system}} --mode destroy,format,mount

# Run ON artemis, as root, BEFORE switching to a persistence.* change — impermanence never migrates data into /persist on its own
migrate-persist flake="." sudo="sudo":
  {{sudo}} nix shell nixpkgs#jq nixpkgs#rsync -c ./modules/hosts/artemis/migrate-persist.sh {{flake}}

install system sudo="sudo":
  {{sudo}} nixos-install --flake .#{{system}}

# Run after bumping the netbird-tap input and switching. `brew upgrade --cask` alone leaves the `netbird` formula (the daemon
# binary) behind, and a formula-only upgrade swaps /opt/homebrew/bin/netbird under the running launchd job without restarting it.
# The cask's installer.sh boots the old job out and its `netbird service start` can leave the plist unloaded, so re-bootstrap it
# (the plist has RunAtLoad=false, hence the kickstart).

# Upgrade the NetBird brew formula and cask, then restart the launchd job
netbird-update:
  brew upgrade netbirdio/tap/netbird netbirdio/tap/netbird-ui
  sudo launchctl bootout system/netbird 2>/dev/null || true
  sudo launchctl bootstrap system /Library/LaunchDaemons/netbird.plist
  sudo launchctl kickstart -k system/netbird
  netbird status | grep -i version

nh *args:
  NH_FLAKE={{justfile_directory()}} nh {{args}}

# Passes --skip-checks itself; add only other deploy-rs flags (e.g. just deploy-legion --remote-build)
deploy-legion *args:
  @for node in $(nix eval --raw '.#lib.legionNodes' --apply 'nodes: builtins.concatStringsSep "\n" (builtins.attrNames nodes)'); do just deploy "$node" --skip-checks {{args}}; done

legion-run *command:
  @for node in $(nix eval --raw '.#lib.legionNodes' --apply 'nodes: builtins.concatStringsSep "\n" (builtins.attrNames nodes)'); do ssh "${node#legion-}.jeiang.dev" -- {{command}}; done

# Recolor new images from assets/wallpapers/ into assets/wallpapers-kanabox/. Files already there are left alone, so a photo
# kept in its original colors is just a copy; delete the recolored outputs before re-running after a palette change.

# Recolor new wallpapers from assets/wallpapers/ into assets/wallpapers-kanabox/
wallpaper:
  @for f in assets/wallpapers/*.jpg assets/wallpapers/*.png; do [ -e "$f" ] || continue; [ -e "assets/wallpapers-kanabox/$(basename "$f")" ] && continue; nix run nixpkgs#lutgen -- apply -o "assets/wallpapers-kanabox/$(basename "$f")" "$f" -- $(nix eval --raw '.#lib.palette.kanaboxDarkHard' --apply 'p: builtins.concatStringsSep " " (map (c: builtins.substring 1 6 c) (builtins.attrValues p))'); done
