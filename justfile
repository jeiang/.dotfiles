default:
  @just --list

# Format all files
fmt:
  nix fmt
  statix fix
  # anything that could not be autofixed would be reported here
  statix check

# Check for nix errors
check extraArgs="":
  nix flake check --impure --keep-going {{extraArgs}}

clean-deploy system address *args:
  nix run github:nix-community/nixos-anywhere -- --generate-hardware-config nixos-facter ./modules/hosts/{{system}}/facter.json  --flake .#{{system}} --target-host root@{{address}} {{args}}

deploy system *args:
  deploy .#{{system}} {{args}} -- --impure

# Run this after editing .sops.yaml
sops-updatekeys:
  sops updatekeys $(fd "secrets.(yaml|env|ini|json)" | fzf)

# Edit or view the secrets
sops-edit:
  sops $(fd "secrets.([^.]+.)?(yaml|env|ini|json)" | fzf)

sops-create path:
  sops {{path}}

disko-format system sudo="sudo":
  {{sudo}} disko -f .#{{system}} --mode destroy,format,mount

# Run ON artemis, as root, before rebooting into a persistence.* change —
# impermanence never migrates existing data into /persist on its own.
# jq/rsync aren't guaranteed to be on PATH outside the dev shell, so pull
# them in explicitly rather than assuming the target environment has them.
migrate-persist flake="." sudo="sudo":
  {{sudo}} nix shell nixpkgs#jq nixpkgs#rsync -c ./modules/hosts/artemis/migrate-persist.sh {{flake}}

install system sudo="sudo":
  {{sudo}} nixos-install --flake .#{{system}}

nh *args:
  NH_FLAKE={{justfile_directory()}} nh {{args}}

deploy-legion *args:
  @for node in $(nix eval --impure --raw '.#deploy.nodes' --apply 'nodes: builtins.concatStringsSep "\n" (builtins.attrNames nodes)'); do just deploy "$node" {{args}}; done

legion-run *command:
  @for host in $(nix eval --impure --raw '.#deploy.nodes' --apply 'nodes: builtins.concatStringsSep "\n" (builtins.attrValues (builtins.mapAttrs (_: node: node.hostname) nodes))'); do ssh "$host" -- {{command}}; done
