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
  nix run github:nix-community/nixos-anywhere -- --generate-hardware-config nixos-facter ./modules/hosts/{{system}}/facter.json  --flake .#{{system}} --target-host root@{{address}} {{args}}

deploy system *args:
  deploy .#{{system}} {{args}}

# Run this after editing .sops.yaml
sops-updatekeys:
  sops updatekeys $(fd "secrets.([^.]+.)?(yaml|env|ini|json)" | fzf)

# Edit or view the secrets
sops-edit:
  sops $(fd "secrets.([^.]+.)?(yaml|env|ini|json)" | fzf)

sops-create path:
  sops {{path}}

# Preview dns/dnsconfig.js against live Cloudflare; read-only — the push happens in CI on merge to main
dns-preview *args:
  CLOUDFLARE_API_TOKEN=$(sops -d --extract '["caddy"]["cloudflare-dns-token"]' modules/nixos/edge/secrets.yaml) dnscontrol preview --config dns/dnsconfig.js --creds dns/creds.json {{args}}

disko-format system sudo="sudo":
  {{sudo}} disko -f .#{{system}} --mode destroy,format,mount

# Run ON artemis, as root, before rebooting into a persistence.* change — impermanence never migrates data into /persist on its own
migrate-persist flake="." sudo="sudo":
  {{sudo}} nix shell nixpkgs#jq nixpkgs#rsync -c ./modules/hosts/artemis/migrate-persist.sh {{flake}}

install system sudo="sudo":
  {{sudo}} nixos-install --flake .#{{system}}

darwin-switch:
  sudo darwin-rebuild switch --flake .#zakkart

nh *args:
  NH_FLAKE={{justfile_directory()}} nh {{args}}

deploy-legion *args:
  @for node in $(nix eval --raw '.#deploy.nodes' --apply 'nodes: builtins.concatStringsSep "\n" (builtins.attrNames nodes)'); do just deploy "$node" {{args}}; done

legion-run *command:
  @for host in $(nix eval --raw '.#deploy.nodes' --apply 'nodes: builtins.concatStringsSep "\n" (builtins.attrValues (builtins.mapAttrs (_: node: node.hostname) nodes))'); do ssh "$host" -- {{command}}; done

# Recolor new images from assets/wallpapers/ into assets/wallpapers-kanabox/. Files already there are left alone, so a photo
# kept in its original colors is just a copy; delete the recolored outputs before re-running after a palette change.
wallpaper:
  @for f in assets/wallpapers/*.jpg assets/wallpapers/*.png; do [ -e "$f" ] || continue; [ -e "assets/wallpapers-kanabox/$(basename "$f")" ] && continue; nix run nixpkgs#lutgen -- apply -o "assets/wallpapers-kanabox/$(basename "$f")" "$f" -- $(nix eval --raw '.#lib.palette.kanaboxDarkHard' --apply 'p: builtins.concatStringsSep " " (map (c: builtins.substring 1 6 c) (builtins.attrValues p))'); done
