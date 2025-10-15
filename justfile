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
    nix flake check --impure {{extraArgs}}

clean-deploy system address:
    nix run github:nix-community/nixos-anywhere -- --generate-hardware-config nixos-facter ./systems/{{system}}/facter.json  --flake .#{{system}} --target-host root@{{address}}

deploy system profile="":
    deploy .#{{system}}{{ if profile == "" { "" } else { "." + profile } }} -- --impure

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

install system sudo="sudo":
  {{sudo}} nixos-install --flake .#{{system}}

nixos action system="" sudo="sudo":
  {{sudo}} nixos-rebuild {{action}} --flake .#{{system}}

